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
        let planetary = self.heliocentricEcliptic( of: planet, dayNumber: dayNumber )
        let longitude = Ephemeris.radians( planetary.longitude )
        let latitude  = Ephemeris.radians( planetary.latitude )

        // The perturbed heliocentric ecliptic position, back in rectangular form.
        let x = planetary.distance * cos( latitude ) * cos( longitude )
        let y = planetary.distance * cos( latitude ) * sin( longitude )
        let z = planetary.distance * sin( latitude )

        // The Sun's elements (`N = i = 0`) yield the Sun's geocentric ecliptic
        // position; adding it to the planet's heliocentric position gives the
        // planet's geocentric ecliptic position.
        let solar = SolarPosition.elements( dayNumber: dayNumber ).heliocentricEcliptic

        return Ephemeris.equatorial( eclipticX: x + solar.x, eclipticY: y + solar.y, eclipticZ: z + solar.z, dayNumber: dayNumber )
    }

    /// A planet's perturbed heliocentric ecliptic position at a day number: the
    /// longitude and latitude, in degrees, and the distance, in AU.
    ///
    /// The Keplerian reduction gives the unperturbed position; for Jupiter, Saturn
    /// and Uranus — whose mutual gravitational perturbations reach a fraction of a
    /// degree — Schlyter's largest periodic terms are then added to the longitude
    /// (and, for Saturn, the latitude), bringing them from a fraction of a degree to
    /// a few arc-minutes. The inner planets and Neptune have no modelled terms, so
    /// their position is the bare Keplerian reduction. The distance is not perturbed.
    ///
    /// - Parameters:
    ///   - planet:    The planet to locate.
    ///   - dayNumber: The day number `d`.
    /// - Returns: The heliocentric ecliptic longitude and latitude (degrees) and the
    ///   distance (AU).
    static func heliocentricEcliptic( of planet: Planet, dayNumber d: Double ) -> ( longitude: Double, latitude: Double, distance: Double )
    {
        let ( x, y, z )  = planet.elements( dayNumber: d ).heliocentricEcliptic
        let longitude    = Ephemeris.degrees( atan2( y, x ) )
        let latitude     = Ephemeris.degrees( atan2( z, ( x * x + y * y ).squareRoot() ) )
        let distance     = ( x * x + y * y + z * z ).squareRoot()
        let perturbation = self.perturbation( for: planet, dayNumber: d )

        return (
            Ephemeris.normalizedDegrees( longitude + perturbation.longitude ),
            latitude + perturbation.latitude,
            distance
        )
    }

    /// Schlyter's largest mutual-perturbation corrections to a planet's heliocentric
    /// ecliptic longitude and latitude, in degrees.
    ///
    /// Only Jupiter, Saturn and Uranus have modelled terms; every other planet
    /// returns zero. The arguments are the mean anomalies of Jupiter (`Mj`), Saturn
    /// (`Ms`) and Uranus (`Mu`), taken directly from their orbital elements — the
    /// same values the Keplerian reduction uses, so they need no separate epoch.
    ///
    /// - Parameters:
    ///   - planet:    The planet whose perturbation to evaluate.
    ///   - dayNumber: The day number `d`.
    /// - Returns: The longitude and latitude corrections, in degrees (both zero for a
    ///   planet without modelled terms).
    private static func perturbation( for planet: Planet, dayNumber d: Double ) -> ( longitude: Double, latitude: Double )
    {
        let mj     = Planet.jupiter.elements( dayNumber: d ).meanAnomaly
        let ms     = Planet.saturn.elements(  dayNumber: d ).meanAnomaly
        let mu     = Planet.uranus.elements(  dayNumber: d ).meanAnomaly
        let sine   = Ephemeris.sineDegrees
        let cosine = Ephemeris.cosineDegrees

        switch planet
        {
            case .jupiter:
                return (
                    longitude:
                    -0.332 * sine( 2 * mj - 5 * ms - 67.6 )
                        -  0.056 * sine( 2 * mj - 2 * ms + 21 )
                        +  0.042 * sine( 3 * mj - 5 * ms + 21 )
                        -  0.036 * sine( mj - 2 * ms )
                        +  0.022 * cosine( mj - ms )
                        +  0.023 * sine( 2 * mj - 3 * ms + 52 )
                        -  0.016 * sine( mj - 5 * ms - 69 ),
                    latitude: 0
                )

            case .saturn:
                return (
                    longitude:
                    0.812 * sine( 2 * mj - 5 * ms - 67.6 )
                        -  0.229 * cosine( 2 * mj - 4 * ms - 2 )
                        +  0.119 * sine( mj - 2 * ms - 3 )
                        +  0.046 * sine( 2 * mj - 6 * ms - 69 )
                        +  0.014 * sine( mj - 3 * ms + 32 ),
                    latitude:
                    -0.020 * cosine( 2 * mj - 4 * ms - 2 )
                        +  0.018 * sine( 2 * mj - 6 * ms - 49 )
                )

            case .uranus:
                return (
                    longitude:
                    0.040 * sine( ms - 2 * mu + 6 )
                        +  0.035 * sine( ms - 3 * mu + 33 )
                        -  0.015 * sine( mj - mu + 20 ),
                    latitude: 0
                )

            case .mercury,
                 .venus,
                 .mars,
                 .neptune:
                return ( longitude: 0, latitude: 0 )
        }
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
