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

/// Tests for ``SolarPosition`` and the shared ``Ephemeris`` reductions, validated
/// against the fully worked numeric example in Paul Schlyter's tutorial
/// (https://stjarnhimlen.se/comp/tutorial.html): 1990-04-19 00:00 UT, observed
/// from 60° N, 15° E.
struct SolarPositionTests
{
    /// Builds a UTC date from calendar components.
    private func utcDate( _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0 ) throws -> Date
    {
        var components = DateComponents()

        components.year   = year
        components.month  = month
        components.day    = day
        components.hour   = hour
        components.minute = minute
        components.second = second

        var calendar      = Calendar( identifier: .gregorian )
        calendar.timeZone = .gmt

        return try #require( calendar.date( from: components ) )
    }

    /// Schlyter's day number is days since 2000 Jan 0.0 UT; 1990-04-19 00:00 UT
    /// is his worked example's `d = -3543.0`.
    @Test
    func dayNumberMatchesSchlyterExample() throws
    {
        let date = try self.utcDate( 1990, 4, 19 )

        #expect( Swift.abs( Ephemeris.dayNumber( from: date ) - ( -3543.0 ) ) < 1e-6 )
    }

    /// The local sidereal time at the example instant is 13.78925 h at Greenwich
    /// (GMST0, UT = 0) and 14.78925 h at 15° E, per the tutorial.
    @Test
    func localSiderealTimeMatchesSchlyterExample() throws
    {
        let date = try self.utcDate( 1990, 4, 19 )

        #expect( Swift.abs( Ephemeris.localSiderealTimeHours( date: date, longitude: 0  ) - 13.78925 ) < 0.001 )
        #expect( Swift.abs( Ephemeris.localSiderealTimeHours( date: date, longitude: 15 ) - 14.78925 ) < 0.001 )
    }

    /// The Sun's geocentric equatorial coordinates match the tutorial:
    /// RA 26.6580°, Dec +11.0084°.
    @Test
    func sunEquatorialMatchesSchlyterExample() throws
    {
        let date     = try self.utcDate( 1990, 4, 19 )
        let position = SolarPosition.position( at: date )

        #expect( Swift.abs( position.rightAscension - 26.6580 ) < 0.02 )
        #expect( Swift.abs( position.declination    - 11.0084 ) < 0.02 )
    }

    /// The Sun's horizontal coordinates for the tutorial's observer (60° N,
    /// 15° E) are azimuth 15.68°, altitude −17.96° (below the horizon).
    @Test
    func sunHorizontalMatchesSchlyterExample() throws
    {
        let date       = try self.utcDate( 1990, 4, 19 )
        let location   = GeographicLocation( latitude: 60, longitude: 15 )
        let horizontal = SolarPosition.horizontal( at: date, location: location )

        #expect( Swift.abs( horizontal.azimuth  - 15.68      ) < 0.1 )
        #expect( Swift.abs( horizontal.altitude - ( -17.96 ) ) < 0.1 )
        #expect( horizontal.isAboveHorizon == false )
    }

    /// Near the June solstice the Sun's declination approaches the obliquity of
    /// the ecliptic (about +23.4°); near an equinox it crosses zero. A coarse
    /// sanity check that the seasonal declination behaves correctly.
    @Test
    func sunDeclinationTracksTheSeasons() throws
    {
        let solstice = try self.utcDate( 2024, 6, 20, 12 )
        let equinox  = try self.utcDate( 2024, 9, 22, 12 )

        #expect( Swift.abs( SolarPosition.position( at: solstice ).declination - 23.4 ) < 0.3 )
        #expect( Swift.abs( SolarPosition.position( at: equinox ).declination         ) < 0.5 )
    }
}
