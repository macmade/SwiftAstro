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
    public var isAboveHorizon: Bool
    {
        self.altitude > 0
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
