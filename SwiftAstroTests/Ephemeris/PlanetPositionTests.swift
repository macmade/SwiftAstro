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
    /// The planet's perturbed heliocentric ecliptic longitude, latitude (degrees)
    /// and distance (AU) — the position `PlanetPosition` actually uses, including the
    /// Schlyter perturbation terms for Jupiter, Saturn and Uranus.
    private func heliocentric( _ planet: Planet, dayNumber: Double ) -> ( longitude: Double, latitude: Double, distance: Double )
    {
        PlanetPosition.heliocentricEcliptic( of: planet, dayNumber: dayNumber )
    }

    /// The planet's *unperturbed* heliocentric ecliptic longitude and latitude, in
    /// degrees, straight from the Keplerian reduction (no perturbation terms).
    private func unperturbed( _ planet: Planet, dayNumber: Double ) -> ( longitude: Double, latitude: Double )
    {
        let ( x, y, z ) = planet.elements( dayNumber: dayNumber ).heliocentricEcliptic

        return ( Ephemeris.normalizedDegrees( Ephemeris.degrees( atan2( y, x ) ) ), Ephemeris.degrees( atan2( z, ( x * x + y * y ).squareRoot() ) ) )
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

    /// Builds a UTC date at a whole hour.
    private func utcDate( _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0 ) throws -> Date
    {
        var components = DateComponents()

        components.year   = year
        components.month  = month
        components.day    = day
        components.hour   = hour

        var calendar      = Calendar( identifier: .gregorian )
        calendar.timeZone = .gmt

        return try #require( calendar.date( from: components ) )
    }

    /// The heliocentric positions of Mercury, Venus, Mars, Jupiter and Saturn match
    /// Schlyter's worked example at `d = -3543`. The Jupiter and Saturn values are the
    /// perturbation-corrected ones from the tutorial (Jupiter longitude 105.2423°,
    /// Saturn longitude 289.3824° / latitude +0.1845°), so a future typo in an
    /// outer-planet element polynomial would fail here. A small error confined to a
    /// perturbation term is caught by ``outerPlanetPerturbationsMatchSchlyterCorrections``
    /// instead: Jupiter's own perturbation (0.012°) is within this test's 0.02°
    /// tolerance, so this test does not by itself exercise the Jupiter term.
    @Test
    func heliocentricMatchesSchlyterExample()
    {
        let mercury = self.heliocentric( .mercury, dayNumber: -3543 )
        let venus   = self.heliocentric( .venus,   dayNumber: -3543 )
        let mars    = self.heliocentric( .mars,    dayNumber: -3543 )
        let jupiter = self.heliocentric( .jupiter, dayNumber: -3543 )
        let saturn  = self.heliocentric( .saturn,  dayNumber: -3543 )

        #expect( Swift.abs( mercury.longitude - 170.5709   ) < 0.02 )
        #expect( Swift.abs( mercury.latitude  -   5.9255   ) < 0.02 )
        #expect( Swift.abs( mercury.distance  -   0.374862 ) < 0.001 )

        #expect( Swift.abs( venus.longitude - 263.6570    ) < 0.02 )
        #expect( Swift.abs( venus.latitude  - ( -0.4180 ) ) < 0.02 )
        #expect( Swift.abs( venus.distance  -   0.726607  ) < 0.001 )

        #expect( Swift.abs( mars.longitude - 290.6297    ) < 0.02 )
        #expect( Swift.abs( mars.latitude  - ( -1.6203 ) ) < 0.02 )
        #expect( Swift.abs( mars.distance  -   1.417194  ) < 0.001 )

        #expect( Swift.abs( jupiter.longitude - 105.2423  ) < 0.02 )
        #expect( Swift.abs( jupiter.latitude  -   0.1113  ) < 0.02 )
        #expect( Swift.abs( jupiter.distance  -   5.19508 ) < 0.001 )

        #expect( Swift.abs( saturn.longitude - 289.3824  ) < 0.02 )
        #expect( Swift.abs( saturn.latitude  -   0.1845  ) < 0.02 )
        #expect( Swift.abs( saturn.distance  -  10.06118 ) < 0.001 )
    }

    /// The Schlyter perturbation terms shift Jupiter's, Saturn's and Uranus's
    /// heliocentric longitude (and Saturn's latitude) by the exact corrections given
    /// in the tutorial's worked example at `d = -3543` — a direct check that the
    /// perturbations are applied (without them every correction below would be zero).
    @Test
    func outerPlanetPerturbationsMatchSchlyterCorrections()
    {
        let jupiter = self.heliocentric( .jupiter, dayNumber: -3543 )
        let saturn  = self.heliocentric( .saturn,  dayNumber: -3543 )
        let uranus  = self.heliocentric( .uranus,  dayNumber: -3543 )

        let jupiterRaw = self.unperturbed( .jupiter, dayNumber: -3543 )
        let saturnRaw  = self.unperturbed( .saturn,  dayNumber: -3543 )
        let uranusRaw  = self.unperturbed( .uranus,  dayNumber: -3543 )

        #expect( Swift.abs( ( jupiter.longitude - jupiterRaw.longitude ) - ( -0.0120 ) ) < 0.001 )
        #expect( Swift.abs( ( saturn.longitude  - saturnRaw.longitude  ) - ( -0.0699 ) ) < 0.001 )
        #expect( Swift.abs( ( saturn.latitude   - saturnRaw.latitude   ) -    0.0053   ) < 0.001 )
        #expect( Swift.abs( ( uranus.longitude  - uranusRaw.longitude  ) - ( -0.0327 ) ) < 0.001 )

        // Mercury, Venus, Mars and Neptune have no modelled terms — perturbed equals
        // unperturbed.
        [ Planet.mercury, .venus, .mars, .neptune ].forEach
        {
            let perturbed = self.heliocentric( $0, dayNumber: -3543 )
            let raw       = self.unperturbed( $0, dayNumber: -3543 )

            #expect( Swift.abs( perturbed.longitude - raw.longitude ) < 1e-9 )
            #expect( Swift.abs( perturbed.latitude  - raw.latitude  ) < 1e-9 )
        }
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

    /// Each planet rises and sets over a day at mid-latitude — a non-tautological
    /// check that the horizontal reduction feeds ``HorizontalCoordinate/isAboveHorizon``
    /// a position that tracks the sky (every planet stays near the ecliptic, so at
    /// 40° N none is circumpolar or perpetually below the horizon). The fixed-value
    /// boundary and refraction cases are in `HorizontalCoordinateTests`.
    @Test
    func everyPlanetRisesAndSetsOverADay() throws
    {
        let location = GeographicLocation( latitude: 40, longitude: -74 )

        try Planet.allCases.forEach
        {
            planet in

            let states = try ( 0 ..< 24 ).map
            {
                PlanetPosition.horizontal( of: planet, at: try self.utcDate( 2024, 7, 15, $0 ), location: location ).isAboveHorizon
            }

            #expect( states.contains( true ),  "\( planet.name ) is never above the horizon over the day" )
            #expect( states.contains( false ), "\( planet.name ) never sets over the day" )
        }
    }
}
