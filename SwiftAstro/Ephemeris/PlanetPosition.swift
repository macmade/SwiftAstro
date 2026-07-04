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

/// A planet's low-precision geocentric position, after Schlyter's method.
///
/// A planet's heliocentric position is added to the Sun's, giving the geocentric
/// ecliptic position, which is then reduced to equatorial and (for an observer)
/// horizontal coordinates.
public enum PlanetPosition
{
    /// A planet's geocentric equatorial coordinates at an instant.
    ///
    /// - Parameters:
    ///   - planet: The planet to locate.
    ///   - date:   The instant to evaluate.
    /// - Returns: The planet's right ascension and declination.
    public static func position( of planet: Planet, at date: Date ) -> EquatorialCoordinate
    {
        let dayNumber = Ephemeris.dayNumber( from: date )
        let planetary = planet.elements( dayNumber: dayNumber ).heliocentricEcliptic

        // The Sun's elements (`N = i = 0`) yield the Sun's geocentric ecliptic
        // position; adding it to the planet's heliocentric position gives the
        // planet's geocentric ecliptic position.
        let solar = SolarPosition.elements( dayNumber: dayNumber ).heliocentricEcliptic

        return Ephemeris.equatorial( eclipticX: planetary.x + solar.x, eclipticY: planetary.y + solar.y, eclipticZ: planetary.z + solar.z, dayNumber: dayNumber )
    }

    /// A planet's local horizontal coordinates for an observer at an instant.
    ///
    /// - Parameters:
    ///   - planet:   The planet to locate.
    ///   - date:     The instant to evaluate.
    ///   - location: The observer's location.
    /// - Returns: The planet's azimuth and altitude.
    public static func horizontal( of planet: Planet, at date: Date, location: GeographicLocation ) -> HorizontalCoordinate
    {
        Ephemeris.horizontal( of: self.position( of: planet, at: date ), date: date, location: location )
    }
}
