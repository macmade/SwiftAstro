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

/// The Sun's rise, set and twilight event times for a location on a given day.
///
/// Each event is the instant the Sun's centre passes a threshold altitude —
/// −0.833° for sunrise/sunset (allowing for refraction and the solar radius),
/// and −6° / −12° / −18° for the end of civil / nautical / astronomical
/// twilight. An event is `nil` when it does not occur that day: at high latitudes
/// the Sun can stay above or below a threshold for the whole day (polar day or
/// night).
///
/// Times are computed from the Sun's low-precision position and are good to about
/// a minute at mid-latitudes. The Sun's declination is taken at the day's solar
/// transit, so the rise and set of a given threshold are symmetric about it.
///
/// - Note: Sunrise/sunset here use the −0.833° convention (refraction + the solar
///   semidiameter), which differs from `HorizontalCoordinate.isAboveHorizon`'s ideal
///   0° geometric horizon. To decide "is the Sun up?" so it agrees with `sunrise` /
///   `sunset`, use `HorizontalCoordinate.isAboveHorizon(refraction:)` with a
///   refraction of `0.833`, not the plain `isAboveHorizon` property.
public struct TwilightEvents: Sendable, Equatable
{
    /// The time the Sun rises (centre at −0.833°), or `nil` if it does not rise.
    public let sunrise: Date?

    /// The time the Sun sets (centre at −0.833°), or `nil` if it does not set.
    public let sunset: Date?

    /// The morning end of civil twilight (Sun reaching −6°), or `nil`.
    public let civilDawn: Date?

    /// The evening start of civil twilight (Sun dropping to −6°), or `nil`.
    public let civilDusk: Date?

    /// The morning end of nautical twilight (Sun reaching −12°), or `nil`.
    public let nauticalDawn: Date?

    /// The evening start of nautical twilight (Sun dropping to −12°), or `nil`.
    public let nauticalDusk: Date?

    /// The morning end of astronomical twilight (Sun reaching −18°), or `nil`.
    public let astronomicalDawn: Date?

    /// The evening start of astronomical twilight (Sun dropping to −18°), or `nil`.
    public let astronomicalDusk: Date?

    /// The Sun-centre altitude of sunrise / sunset, accounting for atmospheric
    /// refraction and the solar semidiameter.
    private static let sunriseAltitude = -0.833

    /// The Sun-altitude threshold ending civil twilight.
    private static let civilAltitude = -6.0

    /// The Sun-altitude threshold ending nautical twilight.
    private static let nauticalAltitude = -12.0

    /// The Sun-altitude threshold ending astronomical twilight.
    private static let astronomicalAltitude = -18.0

    /// Creates a set of twilight events.
    public init( sunrise: Date?, sunset: Date?, civilDawn: Date?, civilDusk: Date?, nauticalDawn: Date?, nauticalDusk: Date?, astronomicalDawn: Date?, astronomicalDusk: Date? )
    {
        self.sunrise          = sunrise
        self.sunset           = sunset
        self.civilDawn        = civilDawn
        self.civilDusk        = civilDusk
        self.nauticalDawn     = nauticalDawn
        self.nauticalDusk     = nauticalDusk
        self.astronomicalDawn = astronomicalDawn
        self.astronomicalDusk = astronomicalDusk
    }

    /// Computes the Sun's rise, set and twilight events for the UTC day
    /// containing `date`, at `location`.
    ///
    /// - Parameters:
    ///   - date:     Any instant in the day to evaluate (interpreted in UTC).
    ///   - location: The observer's location.
    /// - Returns: The day's twilight events, with `nil` for any that do not occur.
    public static func compute( date: Date, location: GeographicLocation ) -> TwilightEvents
    {
        let startOfDay     = Date( timeIntervalSince1970: ( date.timeIntervalSince1970 / 86400 ).rounded( .down ) * 86400 )
        let transitHours   = self.solarTransitHours( startOfDay: startOfDay, location: location )
        let transitInstant = startOfDay.addingTimeInterval( transitHours * 3600 )
        let declination    = SolarPosition.position( at: transitInstant ).declination

        let sun          = self.events( altitude: self.sunriseAltitude,      declination: declination, location: location, startOfDay: startOfDay, transitHours: transitHours )
        let civil        = self.events( altitude: self.civilAltitude,        declination: declination, location: location, startOfDay: startOfDay, transitHours: transitHours )
        let nautical     = self.events( altitude: self.nauticalAltitude,     declination: declination, location: location, startOfDay: startOfDay, transitHours: transitHours )
        let astronomical = self.events( altitude: self.astronomicalAltitude, declination: declination, location: location, startOfDay: startOfDay, transitHours: transitHours )

        return TwilightEvents(
            sunrise:          sun.dawn,
            sunset:           sun.dusk,
            civilDawn:        civil.dawn,
            civilDusk:        civil.dusk,
            nauticalDawn:     nautical.dawn,
            nauticalDusk:     nautical.dusk,
            astronomicalDawn: astronomical.dawn,
            astronomicalDusk: astronomical.dusk
        )
    }

    /// The morning (dawn) and evening (dusk) times the Sun crosses `altitude`,
    /// symmetric about the solar transit, or `nil` when it never does that day.
    private static func events( altitude: Double, declination: Double, location: GeographicLocation, startOfDay: Date, transitHours: Double ) -> ( dawn: Date?, dusk: Date? )
    {
        guard let hourAngle = self.hourAngle( altitude: altitude, declination: declination, latitude: location.latitude )
        else
        {
            return ( nil, nil )
        }

        let dawn = startOfDay.addingTimeInterval( ( transitHours - hourAngle / 15 ) * 3600 )
        let dusk = startOfDay.addingTimeInterval( ( transitHours + hourAngle / 15 ) * 3600 )

        return ( dawn, dusk )
    }

    /// The hour angle, in degrees, at which the Sun's altitude equals `altitude`,
    /// or `nil` when the Sun never reaches it that day (polar day or night).
    private static func hourAngle( altitude: Double, declination: Double, latitude: Double ) -> Double?
    {
        let latitudeRadians    = Ephemeris.radians( latitude )
        let declinationRadians = Ephemeris.radians( declination )
        let cosine             = ( sin( Ephemeris.radians( altitude ) ) - sin( latitudeRadians ) * sin( declinationRadians ) ) / ( cos( latitudeRadians ) * cos( declinationRadians ) )

        guard cosine >= -1, cosine <= 1
        else
        {
            return nil
        }

        return Ephemeris.degrees( acos( cosine ) )
    }

    /// The Universal Time of solar transit (upper culmination), in hours from the
    /// start of the day, found where the local sidereal time equals the Sun's
    /// right ascension.
    private static func solarTransitHours( startOfDay: Date, location: GeographicLocation ) -> Double
    {
        var ut = 12.0

        for _ in 0 ..< 10
        {
            let instant       = startOfDay.addingTimeInterval( ut * 3600 )
            let rightAscension = SolarPosition.position( at: instant ).rightAscension
            let siderealTime   = Ephemeris.localSiderealTimeHours( date: instant, longitude: location.longitude )

            var error = rightAscension / 15 - siderealTime
            error    -= 24 * ( error / 24 ).rounded()

            ut += error / 1.0027

            if abs( error ) < 1e-4
            {
                break
            }
        }

        return ut
    }
}
