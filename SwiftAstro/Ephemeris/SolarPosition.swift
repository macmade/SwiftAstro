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

/// The Sun's low-precision position, after Schlyter's method — good to about an
/// arc-minute over 1900–2100, which is ample for a viewer.
public enum SolarPosition
{
    /// The Sun's orbital elements at a day number.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The Sun's elements.
    static func elements( dayNumber: Double ) -> OrbitalElements
    {
        OrbitalElements(
            longitudeOfAscendingNode: 0,
            inclination:              0,
            argumentOfPerihelion:     282.9404 + 4.70935e-5 * dayNumber,
            semiMajorAxis:            1,
            eccentricity:             0.016709 - 1.151e-9 * dayNumber,
            meanAnomaly:              356.0470 + 0.9856002585 * dayNumber
        )
    }

    /// The Sun's mean longitude, in degrees (`Ls = M + w`), used by the sidereal
    /// time.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The mean longitude, in degrees (`0 ..< 360`).
    static func meanLongitude( dayNumber: Double ) -> Double
    {
        let elements = self.elements( dayNumber: dayNumber )

        return Ephemeris.normalizedDegrees( elements.meanAnomaly + elements.argumentOfPerihelion )
    }

    /// The Sun's geocentric equatorial coordinates at an instant.
    ///
    /// - Parameter date: The instant to evaluate.
    /// - Returns: The Sun's right ascension and declination.
    public static func position( at date: Date ) -> EquatorialCoordinate
    {
        let dayNumber = Ephemeris.dayNumber( from: date )

        // For the Sun, `N = i = 0`, so its heliocentric ecliptic coordinates are
        // its geocentric ecliptic position (`z` is zero).
        let ecliptic = self.elements( dayNumber: dayNumber ).heliocentricEcliptic

        return Ephemeris.equatorial( eclipticX: ecliptic.x, eclipticY: ecliptic.y, eclipticZ: ecliptic.z, dayNumber: dayNumber )
    }

    /// The Sun's local horizontal coordinates for an observer at an instant.
    ///
    /// - Parameters:
    ///   - date:     The instant to evaluate.
    ///   - location: The observer's location.
    /// - Returns: The Sun's azimuth and altitude.
    public static func horizontal( at date: Date, location: GeographicLocation ) -> HorizontalCoordinate
    {
        Ephemeris.horizontal( of: self.position( at: date ), date: date, location: location )
    }
}
