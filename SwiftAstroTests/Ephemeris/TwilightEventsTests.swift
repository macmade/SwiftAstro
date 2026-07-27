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

/// Tests for ``TwilightEvents``.
///
/// The rise/set inversion is validated by self-consistency against the
/// independently-validated ``SolarPosition``: the Sun's altitude at each returned
/// time must equal that event's threshold. The events must also be correctly
/// ordered through the day, and absent (polar day/night) at high latitudes.
struct TwilightEventsTests
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

    /// At each returned event time the Sun's altitude equals that event's
    /// threshold, confirming the rise/set inversion is correct. A mid-latitude
    /// site near the equinox, where every event occurs.
    @Test
    func sunAltitudeAtEachEventMatchesItsThreshold() throws
    {
        let location = GeographicLocation( latitude: 40, longitude: 0 )
        let events   = TwilightEvents.compute( date: try self.utcDate( 2024, 3, 20 ), location: location )

        let expected: [ ( Date?, Double ) ] =
            [
                ( events.sunrise,          -0.833 ),
                ( events.sunset,           -0.833 ),
                ( events.civilDawn,        -6     ),
                ( events.civilDusk,        -6     ),
                ( events.nauticalDawn,     -12    ),
                ( events.nauticalDusk,     -12    ),
                ( events.astronomicalDawn, -18    ),
                ( events.astronomicalDusk, -18    ),
            ]

        try expected.forEach
        {
            time, threshold in

            let date     = try #require( time, "event at threshold \( threshold ) should occur" )
            let altitude = SolarPosition.horizontal( at: date, location: location ).altitude

            #expect( Swift.abs( altitude - threshold ) < 0.3, "Sun altitude \( altitude ) at the event should be \( threshold )" )
        }
    }

    /// The events run in order through the day: astronomical → nautical → civil
    /// dawn, sunrise, then sunset, civil → nautical → astronomical dusk.
    @Test
    func eventsAreOrderedThroughTheDay() throws
    {
        let location = GeographicLocation( latitude: 40, longitude: 0 )
        let events   = TwilightEvents.compute( date: try self.utcDate( 2024, 3, 20 ), location: location )

        let ordered =
            [
                try #require( events.astronomicalDawn ),
                try #require( events.nauticalDawn ),
                try #require( events.civilDawn ),
                try #require( events.sunrise ),
                try #require( events.sunset ),
                try #require( events.civilDusk ),
                try #require( events.nauticalDusk ),
                try #require( events.astronomicalDusk ),
            ]

        zip( ordered, ordered.dropFirst() ).forEach
        {
            earlier, later in #expect( earlier < later )
        }
    }

    /// In the Arctic summer the Sun never sets, so there is no sunrise or sunset.
    @Test
    func polarDayHasNoSunriseOrSunset() throws
    {
        let location = GeographicLocation( latitude: 80, longitude: 0 )
        let events   = TwilightEvents.compute( date: try self.utcDate( 2024, 6, 21 ), location: location )

        #expect( events.sunrise == nil )
        #expect( events.sunset  == nil )
    }

    /// Deep in the Arctic winter (88° N) the Sun peaks well below −18°, so it
    /// never rises and there is no twilight of any kind — every event is absent.
    @Test
    func polarNightHasNoSunOrTwilight() throws
    {
        let location = GeographicLocation( latitude: 88, longitude: 0 )
        let events   = TwilightEvents.compute( date: try self.utcDate( 2024, 12, 21 ), location: location )

        #expect( events.sunrise          == nil )
        #expect( events.sunset           == nil )
        #expect( events.astronomicalDawn == nil )
        #expect( events.astronomicalDusk == nil )
    }
}
