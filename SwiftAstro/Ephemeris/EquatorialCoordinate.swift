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

/// A position on the celestial sphere in the geocentric equatorial system.
public struct EquatorialCoordinate: Sendable, Equatable
{
    /// The right ascension, in decimal degrees (`0 ..< 360`).
    public let rightAscension: Double

    /// The declination, in decimal degrees (`-90 ... 90`).
    public let declination: Double

    /// Creates an equatorial coordinate.
    ///
    /// - Parameters:
    ///   - rightAscension: The right ascension, in decimal degrees.
    ///   - declination:    The declination, in decimal degrees.
    public init( rightAscension: Double, declination: Double )
    {
        self.rightAscension = rightAscension
        self.declination    = declination
    }

    /// The angular separation between this coordinate and another, in degrees.
    ///
    /// - Parameter other: The coordinate to measure to.
    /// - Returns: The great-circle angle between the two positions, in degrees
    ///   (`0 ... 180`).
    public func angularSeparation( to other: EquatorialCoordinate ) -> Double
    {
        let dec1        = Ephemeris.radians( self.declination )
        let dec2        = Ephemeris.radians( other.declination )
        let deltaRA     = Ephemeris.radians( self.rightAscension - other.rightAscension )
        let deltaDec    = dec2 - dec1

        // The haversine form stays accurate for the small separations the great-
        // circle `acos` form loses to rounding.
        let haversine   = sin( deltaDec / 2 ) * sin( deltaDec / 2 ) + cos( dec1 ) * cos( dec2 ) * sin( deltaRA / 2 ) * sin( deltaRA / 2 )
        let angle       = 2 * asin( min( haversine.squareRoot(), 1 ) )

        return Ephemeris.degrees( angle )
    }
}
