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
@testable import SwiftAstro
import Testing

/// Tests for ``Planet`` / ``PlanetPosition``.
///
/// The heliocentric reduction is validated against Paul Schlyter's tutorial
/// worked example (1990-04-19 00:00 UT, `d = -3543`). The geocentric positions —
/// planet heliocentric plus Sun, then the same ecliptic→equatorial reduction the
/// Sun's validated position uses — are checked against a reference-free physical
/// invariant: the inner planets can never appear farther from the Sun than their
/// maximum elongation.
struct PlanetPositionTests
{
    /// The heliocentric ecliptic longitude, latitude (degrees) and distance (AU).
    private func heliocentric( _ planet: Planet, dayNumber: Double ) -> ( longitude: Double, latitude: Double, distance: Double )
    {
        let ( x, y, z ) = planet.elements( dayNumber: dayNumber ).heliocentricEcliptic
        let longitude   = Ephemeris.normalizedDegrees( Ephemeris.degrees( atan2( y, x ) ) )
        let latitude    = Ephemeris.degrees( atan2( z, ( x * x + y * y ).squareRoot() ) )
        let distance    = ( x * x + y * y + z * z ).squareRoot()

        return ( longitude, latitude, distance )
    }

    /// The angular separation between two equatorial coordinates, in degrees.
    private func separation( _ a: EquatorialCoordinate, _ b: EquatorialCoordinate ) -> Double
    {
        let dec1  = Ephemeris.radians( a.declination )
        let dec2  = Ephemeris.radians( b.declination )
        let delta = Ephemeris.radians( a.rightAscension - b.rightAscension )
        let cosine = sin( dec1 ) * sin( dec2 ) + cos( dec1 ) * cos( dec2 ) * cos( delta )

        return Ephemeris.degrees( acos( min( max( cosine, -1 ), 1 ) ) )
    }

    /// Builds a UTC date at 00:00.
    private func utcDate( _ year: Int, _ month: Int, _ day: Int ) throws -> Date
    {
        var components = DateComponents()

        components.year   = year
        components.month  = month
        components.day    = day

        var calendar      = Calendar( identifier: .gregorian )
        calendar.timeZone = .gmt

        return try #require( calendar.date( from: components ) )
    }

    /// The heliocentric positions of Mercury, Venus and Mars match Schlyter's
    /// worked example at `d = -3543`.
    @Test
    func heliocentricMatchesSchlyterExample()
    {
        let mercury = self.heliocentric( .mercury, dayNumber: -3543 )
        let venus   = self.heliocentric( .venus,   dayNumber: -3543 )
        let mars    = self.heliocentric( .mars,    dayNumber: -3543 )

        #expect( abs( mercury.longitude - 170.5709 ) < 0.02 )
        #expect( abs( mercury.latitude  -   5.9255 ) < 0.02 )
        #expect( abs( mercury.distance  -   0.374862 ) < 0.001 )

        #expect( abs( venus.longitude - 263.6570 ) < 0.02 )
        #expect( abs( venus.latitude  - ( -0.4180 ) ) < 0.02 )
        #expect( abs( venus.distance  -   0.726607 ) < 0.001 )

        #expect( abs( mars.longitude - 290.6297 ) < 0.02 )
        #expect( abs( mars.latitude  - ( -1.6203 ) ) < 0.02 )
        #expect( abs( mars.distance  -   1.417194 ) < 0.001 )
    }

    /// Venus never appears more than ~47° from the Sun and Mercury never more
    /// than ~28° — their maximum elongations. A reference-free check that the
    /// geocentric positions are physically sound across the year.
    @Test
    func innerPlanetsStayWithinTheirMaximumElongation() throws
    {
        let dates = try [ ( 2024, 1, 15 ), ( 2024, 4, 15 ), ( 2024, 7, 15 ), ( 2024, 10, 15 ) ].map { try self.utcDate( $0.0, $0.1, $0.2 ) }

        dates.forEach
        {
            date in

            let sun     = SolarPosition.position( at: date )
            let venus   = self.separation( PlanetPosition.position( of: .venus,   at: date ), sun )
            let mercury = self.separation( PlanetPosition.position( of: .mercury, at: date ), sun )

            #expect( venus   < 48.5, "Venus elongation \( venus ) exceeds its maximum" )
            #expect( mercury < 28.5, "Mercury elongation \( mercury ) exceeds its maximum" )
        }
    }

    /// Every planet observable from Earth (all but Earth itself) is covered.
    @Test
    func coversEveryObservablePlanet()
    {
        #expect( Planet.allCases.count == 7 )
        #expect( Planet.allCases.contains( .uranus ) )
        #expect( Planet.allCases.contains( .neptune ) )
    }

    /// Every planet has a non-empty name and astronomical symbol.
    @Test
    func everyPlanetHasANameAndSymbol()
    {
        Planet.allCases.forEach
        {
            #expect( $0.name.isEmpty == false )
            #expect( $0.symbol.isEmpty == false )
        }
    }

    /// The outer planets sit at their expected, near-constant heliocentric
    /// distances (Uranus ~19 AU, Neptune ~30 AU) — a reference-free check that
    /// their elements (semi-major axis and eccentricity) are wired correctly.
    @Test
    func outerPlanetsAreAtTheirExpectedDistances()
    {
        let uranus  = self.heliocentric( .uranus,  dayNumber: -3543 ).distance
        let neptune = self.heliocentric( .neptune, dayNumber: -3543 ).distance

        #expect( uranus  > 18 && uranus  < 21, "Uranus distance \( uranus ) AU is out of range" )
        #expect( neptune > 29 && neptune < 31, "Neptune distance \( neptune ) AU is out of range" )
    }

    /// The horizontal reduction is consistent: a planet is reported above the
    /// horizon exactly when its altitude is positive.
    @Test
    func aboveHorizonMatchesAltitudeSign() throws
    {
        let date     = try self.utcDate( 2024, 7, 15 )
        let location = GeographicLocation( latitude: 40, longitude: -74 )

        Planet.allCases.forEach
        {
            planet in

            let horizontal = PlanetPosition.horizontal( of: planet, at: date, location: location )

            #expect( horizontal.isAboveHorizon == ( horizontal.altitude > 0 ) )
        }
    }
}
