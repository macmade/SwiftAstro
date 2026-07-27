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

/// Tests for ``LunarPosition``.
///
/// The geocentric ecliptic position, the equatorial position and the distance are
/// validated against Paul Schlyter's worked lunar example (1990-04-19 00:00 UT,
/// `d = -3543`): after perturbations the Moon is at ecliptic longitude 306.9484°,
/// latitude -0.5856°, distance 60.6779 Earth radii, and equatorial RA 309.5011°,
/// declination -19.1032°. The distance range and the topocentric parallax
/// correction are checked against reference-free physical invariants.
struct LunarPositionTests
{
    /// Schlyter's day number for his worked lunar example (1990-04-19 00:00 UT).
    private static let exampleDayNumber = -3543.0

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

    /// The perturbed geocentric ecliptic position matches Schlyter's worked example.
    @Test
    func geocentricEclipticMatchesSchlyterExample()
    {
        let ecliptic = LunarPosition.geocentricEcliptic( dayNumber: Self.exampleDayNumber )

        #expect( Swift.abs( ecliptic.longitude - 306.9484    ) < 0.01 )
        #expect( Swift.abs( ecliptic.latitude  - ( -0.5856 ) ) < 0.01 )
        #expect( Swift.abs( ecliptic.distance  -  60.6779    ) < 0.01 )
    }

    /// The geocentric equatorial position matches Schlyter's worked example.
    @Test
    func geocentricEquatorialMatchesSchlyterExample()
    {
        let equatorial = LunarPosition.position( dayNumber: Self.exampleDayNumber )

        #expect( Swift.abs( equatorial.rightAscension - 309.5011     ) < 0.02 )
        #expect( Swift.abs( equatorial.declination    - ( -19.1032 ) ) < 0.02 )
    }

    /// The `Date`-based public entry point resolves to the same position as the
    /// day-number computation: 1990-04-19 00:00 UT is day number -3543.
    @Test
    func positionFromDateMatchesTheWorkedExample() throws
    {
        let date       = try self.utcDate( 1990, 4, 19 )
        let equatorial = LunarPosition.position( at: date )

        #expect( Swift.abs( equatorial.rightAscension - 309.5011     ) < 0.02 )
        #expect( Swift.abs( equatorial.declination    - ( -19.1032 ) ) < 0.02 )
    }

    /// The distance in kilometres is the Earth-radii distance scaled by the Earth's
    /// radius, matching Schlyter's worked example (60.6779 Earth radii).
    @Test
    func distanceMatchesSchlyterExample() throws
    {
        let date     = try self.utcDate( 1990, 4, 19 )
        let expected = 60.6779 * LunarPosition.earthRadiusKilometres

        #expect( Swift.abs( LunarPosition.distance( at: date ) - expected ) < 100 )
    }

    /// Across a year the Moon's distance stays within its real perigee/apogee
    /// envelope — never nearer than ~356,500 km nor farther than ~406,700 km.
    @Test
    func distanceStaysWithinTheLunarRange() throws
    {
        let dates = try ( 1 ... 12 ).map { try self.utcDate( 2024, $0, 1 ) }

        dates.forEach
        {
            let distance = LunarPosition.distance( at: $0 )

            #expect( distance > 356_000, "Moon distance \( distance ) km is nearer than perigee" )
            #expect( distance < 407_000, "Moon distance \( distance ) km is farther than apogee" )
        }
    }

    /// The topocentric altitude is the geocentric altitude lowered by the lunar
    /// parallax (about a degree at the horizon), while the azimuth is unchanged.
    @Test
    func topocentricAltitudeIsLoweredByParallax() throws
    {
        let date     = try self.utcDate( 1990, 4, 19, 12 )
        let location = GeographicLocation( latitude: 60, longitude: 15 )

        let dayNumber  = Ephemeris.dayNumber( from: date )
        let geocentric = Ephemeris.horizontal( of: LunarPosition.position( dayNumber: dayNumber ), date: date, location: location )
        let radii      = LunarPosition.geocentricEcliptic( dayNumber: dayNumber ).distance
        let parallax   = Ephemeris.degrees( asin( 1 / radii ) )
        let expected   = geocentric.altitude - parallax * cos( Ephemeris.radians( geocentric.altitude ) )

        let topocentric = LunarPosition.horizontal( at: date, location: location )

        #expect( parallax > 0.85 && parallax < 1.05, "Lunar parallax \( parallax )° is outside its physical range" )
        #expect( Swift.abs( topocentric.altitude - expected ) < 1e-6 )
        #expect( topocentric.altitude <= geocentric.altitude )
        #expect( Swift.abs( topocentric.azimuth - geocentric.azimuth ) < 1e-9 )
    }

    /// The Moon rises and sets over a day at mid-latitude — a non-tautological check
    /// that the topocentric reduction feeds ``HorizontalCoordinate/isAboveHorizon`` a
    /// position that tracks the sky (its declination stays within ±~28°, so at 40° N
    /// it is neither circumpolar nor perpetually below the horizon). The fixed-value
    /// boundary and refraction cases are in `HorizontalCoordinateTests`.
    @Test
    func moonRisesAndSetsOverADay() throws
    {
        let location = GeographicLocation( latitude: 40, longitude: -74 )

        let states = try ( 0 ..< 24 ).map
        {
            LunarPosition.horizontal( at: try self.utcDate( 2024, 7, 15, $0 ), location: location ).isAboveHorizon
        }

        #expect( states.contains( true ),  "the Moon is never above the horizon over the day" )
        #expect( states.contains( false ), "the Moon never sets over the day" )
    }
}
