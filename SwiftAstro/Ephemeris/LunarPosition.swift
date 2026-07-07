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

/// The Moon's low-precision geocentric position, after Paul Schlyter's method.
///
/// The Moon orbits the Earth, so the same Keplerian reduction the planets use —
/// solving Kepler's equation, then rotating the orbital-plane position by the node,
/// inclination and argument of perihelion — yields its *geocentric* ecliptic
/// position directly (no Sun term to add). Unlike the planets, the Moon is close
/// enough that Schlyter's main periodic perturbations (evection, variation, the
/// yearly equation, …) matter, so they are applied to the longitude, latitude and
/// distance; and its horizontal position needs a topocentric parallax correction,
/// which shifts the apparent altitude by up to about a degree.
///
/// Distances follow Schlyter in Earth radii internally and are surfaced in
/// kilometres. Good to a few arc-minutes over 1900–2100, which is ample for a
/// viewer.
public enum LunarPosition
{
    /// The Earth's equatorial radius, in kilometres — the unit of the Moon's
    /// distance in Schlyter's method (Earth radii), used to surface it in
    /// kilometres.
    static let earthRadiusKilometres = 6378.137

    /// The Moon's orbital elements at a day number. The semi-major axis is in Earth
    /// radii (not AU, unlike the Sun and planets), so the reduction's distances come
    /// out in Earth radii too.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The Moon's elements.
    static func elements( dayNumber d: Double ) -> OrbitalElements
    {
        OrbitalElements(
            longitudeOfAscendingNode: 125.1228 - 0.0529538083 * d,
            inclination:              5.1454,
            argumentOfPerihelion:     318.0634 + 0.1643573223 * d,
            semiMajorAxis:            60.2666,
            eccentricity:             0.054900,
            meanAnomaly:              115.3654 + 13.0649929509 * d
        )
    }

    /// The Moon's perturbed geocentric ecliptic position at a day number: the
    /// longitude and latitude, in degrees, and the distance, in Earth radii.
    ///
    /// The unperturbed Keplerian position is corrected by Schlyter's main lunar
    /// periodic terms — without them the Moon is off by a degree or two.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The ecliptic longitude, latitude and distance (in Earth radii).
    static func geocentricEcliptic( dayNumber d: Double ) -> ( longitude: Double, latitude: Double, distance: Double )
    {
        let elements  = self.elements( dayNumber: d )
        let ( x, y, z ) = elements.heliocentricEcliptic
        let longitude = Ephemeris.degrees( atan2( y, x ) )
        let latitude  = Ephemeris.degrees( atan2( z, ( x * x + y * y ).squareRoot() ) )
        let distance  = ( x * x + y * y + z * z ).squareRoot()

        // The perturbation arguments (in degrees): the Sun's and Moon's mean
        // anomalies, the Moon's mean elongation from the Sun and its argument of
        // latitude.
        let ms = SolarPosition.elements( dayNumber: d ).meanAnomaly
        let mm = elements.meanAnomaly
        let ls = SolarPosition.meanLongitude( dayNumber: d )
        let lm = elements.meanAnomaly + elements.argumentOfPerihelion + elements.longitudeOfAscendingNode
        let el = lm - ls
        let fl = lm - elements.longitudeOfAscendingNode

        let sine   = { ( degrees: Double ) in sin( Ephemeris.radians( degrees ) ) }
        let cosine = { ( degrees: Double ) in cos( Ephemeris.radians( degrees ) ) }

        let longitudePerturbation =
            -1.274 * sine( mm - 2 * el )            // Evection
                +  0.658 * sine( 2 * el )                 // Variation
                -  0.186 * sine( ms )                     // Yearly equation
                -  0.059 * sine( 2 * mm - 2 * el )
                -  0.057 * sine( mm - 2 * el + ms )
                +  0.053 * sine( mm + 2 * el )
                +  0.046 * sine( 2 * el - ms )
                +  0.041 * sine( mm - ms )
                -  0.035 * sine( el )                     // Parallactic equation
                -  0.031 * sine( mm + ms )
                -  0.015 * sine( 2 * fl - 2 * el )
                +  0.011 * sine( mm - 4 * el )

        let latitudePerturbation =
            -0.173 * sine( fl - 2 * el )
                -  0.055 * sine( mm - fl - 2 * el )
                -  0.046 * sine( mm + fl - 2 * el )
                +  0.033 * sine( fl + 2 * el )
                +  0.017 * sine( 2 * mm + fl )

        let distancePerturbation =
            -0.58 * cosine( mm - 2 * el )
                -  0.46 * cosine( 2 * el )

        return (
            Ephemeris.normalizedDegrees( longitude + longitudePerturbation ),
            latitude + latitudePerturbation,
            distance + distancePerturbation
        )
    }

    /// The Moon's geocentric equatorial coordinates and distance (in Earth radii) at
    /// a day number, from a single ecliptic reduction.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The equatorial coordinate and the distance in Earth radii.
    private static func equatorialAndDistance( dayNumber d: Double ) -> ( equatorial: EquatorialCoordinate, earthRadii: Double )
    {
        let ecliptic  = self.geocentricEcliptic( dayNumber: d )
        let longitude = Ephemeris.radians( ecliptic.longitude )
        let latitude  = Ephemeris.radians( ecliptic.latitude )

        let x = ecliptic.distance * cos( latitude ) * cos( longitude )
        let y = ecliptic.distance * cos( latitude ) * sin( longitude )
        let z = ecliptic.distance * sin( latitude )

        return ( Ephemeris.equatorial( eclipticX: x, eclipticY: y, eclipticZ: z, dayNumber: d ), ecliptic.distance )
    }

    /// The Moon's geocentric equatorial coordinates at a day number.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The Moon's right ascension and declination.
    static func position( dayNumber d: Double ) -> EquatorialCoordinate
    {
        self.equatorialAndDistance( dayNumber: d ).equatorial
    }

    /// The Moon's geocentric equatorial coordinates at an instant.
    ///
    /// - Parameter date: The instant to evaluate.
    /// - Returns: The Moon's right ascension and declination.
    public static func position( at date: Date ) -> EquatorialCoordinate
    {
        self.position( dayNumber: Ephemeris.dayNumber( from: date ) )
    }

    /// The Moon's distance from the Earth at an instant, in kilometres.
    ///
    /// - Parameter date: The instant to evaluate.
    /// - Returns: The centre-to-centre distance, in kilometres.
    public static func distance( at date: Date ) -> Double
    {
        self.geocentricEcliptic( dayNumber: Ephemeris.dayNumber( from: date ) ).distance * self.earthRadiusKilometres
    }

    /// The Moon's local topocentric horizontal coordinates for an observer at an
    /// instant.
    ///
    /// The geocentric altitude is lowered by the lunar parallax, `asin(1/r)` (with
    /// `r` in Earth radii), scaled by the cosine of the altitude — zero at the
    /// zenith, about a degree at the horizon. The azimuth is unchanged, the parallax
    /// shift being along the vertical.
    ///
    /// - Parameters:
    ///   - date:     The instant to evaluate.
    ///   - location: The observer's location.
    /// - Returns: The Moon's topocentric azimuth and altitude.
    public static func horizontal( at date: Date, location: GeographicLocation ) -> HorizontalCoordinate
    {
        let d          = Ephemeris.dayNumber( from: date )
        let position   = self.equatorialAndDistance( dayNumber: d )
        let geocentric = Ephemeris.horizontal( of: position.equatorial, date: date, location: location )
        let parallax   = Ephemeris.degrees( asin( 1 / position.earthRadii ) )
        let altitude   = geocentric.altitude - parallax * cos( Ephemeris.radians( geocentric.altitude ) )

        return HorizontalCoordinate( azimuth: geocentric.azimuth, altitude: altitude )
    }
}
