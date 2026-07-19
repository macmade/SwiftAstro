/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) 2026, Jean-David Gadina - www.xs-labs.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the Software), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 ******************************************************************************/

import Foundation

/// A position in the observer's local horizontal system.
public struct HorizontalCoordinate: Sendable, Equatable
{
    /// The azimuth, in decimal degrees clockwise from north (`0` = north,
    /// `90` = east, `180` = south, `270` = west).
    public let azimuth: Double

    /// The altitude above the ideal horizon, in decimal degrees (negative below
    /// the horizon).
    public let altitude: Double

    /// Whether the body is above the ideal (`0°`) horizon.
    ///
    /// This is the *geometric* horizon: it ignores atmospheric refraction, so a body
    /// whose true altitude is between about −0.6° and 0° is reported below the horizon
    /// even though refraction lifts it into view. It therefore disagrees with the
    /// refraction-and-semidiameter sunrise/sunset convention `TwilightEvents` uses
    /// (−0.833°): for the minutes the Sun's centre sits in that band it is *after* the
    /// reported sunrise yet `isAboveHorizon` is still `false`. Use
    /// ``isAboveHorizon(refraction:)`` for the apparent horizon.
    public var isAboveHorizon: Bool
    {
        self.altitude > 0
    }

    /// The standard atmospheric refraction at the horizon, in degrees (about 34′).
    ///
    /// A body whose true altitude is this far below the ideal horizon still appears
    /// above it, refraction lifting it into view.
    public static let horizonRefraction = 0.583

    /// Whether the body appears above the horizon once atmospheric refraction is
    /// allowed for.
    ///
    /// Unlike ``isAboveHorizon`` (the ideal `0°` horizon), this uses the *apparent*
    /// horizon: the body is up when its true altitude exceeds `−refraction`. Pass the
    /// default ``horizonRefraction`` (about 34′) for a point source such as a planet
    /// or star; pass `0.833` to include a body's semidiameter, matching the Sun-centre
    /// sunrise/sunset threshold `TwilightEvents` uses.
    ///
    /// - Parameter refraction: The atmospheric-refraction lift at the horizon, in
    ///   degrees. Defaults to ``horizonRefraction``.
    /// - Returns: Whether the body appears above the refraction-adjusted horizon.
    public func isAboveHorizon( refraction: Double = HorizontalCoordinate.horizonRefraction ) -> Bool
    {
        self.altitude > -refraction
    }

    /// Creates a horizontal coordinate.
    ///
    /// - Parameters:
    ///   - azimuth:  The azimuth, in decimal degrees clockwise from north.
    ///   - altitude: The altitude above the horizon, in decimal degrees.
    public init( azimuth: Double, altitude: Double )
    {
        self.azimuth  = azimuth
        self.altitude = altitude
    }
}
