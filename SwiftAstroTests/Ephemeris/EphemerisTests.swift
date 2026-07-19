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

/// Tests for the shared ``Ephemeris`` primitives directly, at the edge cases the
/// solar/planetary/lunar tests only reach indirectly: the angle wraparounds
/// (including negative and non-finite input), the obliquity, the degree/radian
/// conversions, and the ecliptic→equatorial and equatorial→horizontal reductions
/// at the poles, the zenith and across the hour-angle wrap.
struct EphemerisTests
{
    /// Builds a UTC date at 00:00.
    private func utcDate( _ year: Int, _ month: Int, _ day: Int ) throws -> Date
    {
        var components = DateComponents()

        components.year  = year
        components.month = month
        components.day   = day

        var calendar      = Calendar( identifier: .gregorian )
        calendar.timeZone = .gmt

        return try #require( calendar.date( from: components ) )
    }

    /// `normalizedDegrees` reduces any angle into `0 ..< 360`, wrapping positive and
    /// negative values alike.
    @Test
    func normalizedDegreesWrapsIntoRange()
    {
        #expect( Ephemeris.normalizedDegrees( 0 )      == 0 )
        #expect( Ephemeris.normalizedDegrees( 359.5 )  == 359.5 )
        #expect( Ephemeris.normalizedDegrees( 360 )    == 0 )
        #expect( abs( Ephemeris.normalizedDegrees( 370 )      -  10 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedDegrees( 720 )      -   0 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedDegrees( -10 )      - 350 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedDegrees( -350 )     -  10 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedDegrees( -3600.25 ) - 359.75 ) < 1e-9 )
    }

    /// `normalizedDegrees` passes non-finite input through rather than trapping — the
    /// ephemeris only ever feeds it finite, date-derived angles, so this just pins the
    /// facade's graceful (non-crashing) behaviour.
    @Test
    func normalizedDegreesPassesNonFiniteThrough()
    {
        #expect( Ephemeris.normalizedDegrees( .nan ).isNaN )
        #expect( Ephemeris.normalizedDegrees( .infinity ).isNaN )
    }

    /// `normalizedHours` reduces any value into `0 ..< 24`, wrapping positive and
    /// negative values alike.
    @Test
    func normalizedHoursWrapsIntoRange()
    {
        #expect( Ephemeris.normalizedHours( 0 )  == 0 )
        #expect( abs( Ephemeris.normalizedHours( 24 )   -  0 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedHours( 25.5 ) -  1.5 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedHours( -1 )   - 23 ) < 1e-9 )
        #expect( abs( Ephemeris.normalizedHours( 48 )   -  0 ) < 1e-9 )
    }

    /// The obliquity of the ecliptic is `23.4393°` at the epoch and drifts by
    /// `-3.563e-7°` per day.
    @Test
    func obliquityMatchesSchlyter()
    {
        #expect( abs( Ephemeris.obliquity( dayNumber: 0 )     - 23.4393 ) < 1e-9 )
        #expect( abs( Ephemeris.obliquity( dayNumber: -3543 ) - ( 23.4393 - 3.563e-7 * -3543 ) ) < 1e-9 )
    }

    /// Degrees and radians convert both ways and round-trip.
    @Test
    func radiansAndDegreesConvertBothWays()
    {
        #expect( abs( Ephemeris.radians( 180 ) - .pi ) < 1e-12 )
        #expect( abs( Ephemeris.degrees( .pi ) - 180 ) < 1e-12 )
        #expect( abs( Ephemeris.degrees( Ephemeris.radians( 47.3 ) ) - 47.3 ) < 1e-12 )
    }

    /// The ecliptic→equatorial reduction maps the vernal-equinox direction to the
    /// equator's origin and the north ecliptic pole to declination `90° − obliquity`.
    @Test
    func equatorialReducesKnownEclipticDirections()
    {
        let origin = Ephemeris.equatorial( eclipticX: 1, eclipticY: 0, eclipticZ: 0, dayNumber: 0 )

        #expect( abs( origin.rightAscension - 0 ) < 1e-9 )
        #expect( abs( origin.declination    - 0 ) < 1e-9 )

        let pole = Ephemeris.equatorial( eclipticX: 0, eclipticY: 0, eclipticZ: 1, dayNumber: 0 )

        #expect( abs( pole.declination    - ( 90 - Ephemeris.obliquity( dayNumber: 0 ) ) ) < 1e-9 )
        #expect( abs( pole.rightAscension - 270 ) < 1e-9 )
    }

    /// From the north pole every body's altitude is its declination and the azimuth
    /// stays within range — a clean edge for the horizontal reduction.
    @Test
    func horizontalFromThePoleReturnsDeclinationAsAltitude() throws
    {
        let date     = try self.utcDate( 2024, 7, 15 )
        let location = GeographicLocation( latitude: 90, longitude: 0 )

        [ 30.0, 45.0, -20.0, 0.0 ].forEach
        {
            declination in

            let horizontal = Ephemeris.horizontal( of: EquatorialCoordinate( rightAscension: 123, declination: declination ), date: date, location: location )

            #expect( abs( horizontal.altitude - declination ) < 1e-6 )
            #expect( horizontal.azimuth >= 0 && horizontal.azimuth < 360 )
        }
    }

    /// At the zenith the reduction's `asin` argument can round a hair above `1`; the
    /// clamp (COS-5) keeps the altitude finite at `90°` instead of returning NaN.
    ///
    /// The observer's latitude (`2.5°`, longitude `−180°` on 2024-07-15) with a right
    /// ascension set to the local sidereal time puts a `dec = latitude` body exactly
    /// overhead: `cos²+sin²` then overshoots `1` by one ULP on this toolchain, so the
    /// un-clamped `asin` returns NaN. (Verified with a standalone probe; the clamp is
    /// defensive on toolchains where the rounding lands the other way.)
    @Test
    func horizontalAtTheZenithIsClampedToNinetyDegrees() throws
    {
        let date     = try self.utcDate( 2024, 7, 15 )
        let location = GeographicLocation( latitude: 2.5, longitude: -180 )
        let lst      = Ephemeris.localSiderealTimeHours( date: date, longitude: location.longitude )

        // Right ascension = LST·15 makes the hour angle zero, so a body at
        // `dec = latitude` transits the zenith.
        let coordinate = EquatorialCoordinate( rightAscension: Ephemeris.normalizedDegrees( lst * 15 ), declination: location.latitude )
        let horizontal = Ephemeris.horizontal( of: coordinate, date: date, location: location )

        #expect( horizontal.altitude.isFinite )
        #expect( abs( horizontal.altitude - 90 ) < 1e-6 )
    }

    /// The horizontal reduction keeps the azimuth in `0 ..< 360` and the altitude in
    /// `-90 ... 90` across a full hour-angle sweep (the azimuth's `+180` wrap).
    @Test
    func horizontalAzimuthAndAltitudeStayInRange() throws
    {
        let date     = try self.utcDate( 2024, 7, 15 )
        let location = GeographicLocation( latitude: 40, longitude: -74 )

        stride( from: 0.0, to: 360.0, by: 15.0 ).forEach
        {
            rightAscension in

            let horizontal = Ephemeris.horizontal( of: EquatorialCoordinate( rightAscension: rightAscension, declination: 12 ), date: date, location: location )

            #expect( horizontal.azimuth >= 0 && horizontal.azimuth < 360 )
            #expect( horizontal.altitude >= -90 && horizontal.altitude <= 90 )
        }
    }
}
