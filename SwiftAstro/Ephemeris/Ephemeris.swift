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

/// Shared low-precision astronomical math, after Paul Schlyter's
/// "Computing planetary positions" (https://stjarnhimlen.se/comp/ppcomp.html).
///
/// These are the primitives the solar, planetary and twilight computations build
/// on: the day number, angle helpers, the obliquity of the ecliptic, and the
/// reductions from geocentric ecliptic rectangular coordinates to equatorial and
/// then to the observer's local horizontal system. Angles are in degrees at the
/// boundaries; trigonometry is done in radians internally.
enum Ephemeris
{
    /// Schlyter's day number: days (including the UT fraction) since the epoch
    /// 2000 Jan 0.0 UT — that is, 1999-12-31 00:00 UT, Julian Date 2451543.5.
    ///
    /// Derived from the Unix time: `JD = unixDays + 2440587.5`, and
    /// `d = JD - 2451543.5`, so `d = unixDays - 10956.0`.
    ///
    /// - Parameter date: The instant to evaluate.
    /// - Returns: The day number `d`.
    static func dayNumber( from date: Date ) -> Double
    {
        ( date.timeIntervalSince1970 / 86400 ) - 10956.0
    }

    /// The Universal Time of day, in hours (`0 ..< 24`), for an instant.
    ///
    /// - Parameter date: The instant to evaluate.
    /// - Returns: The UT hour of day.
    static func universalTimeHours( from date: Date ) -> Double
    {
        let days = date.timeIntervalSince1970 / 86400

        return ( days - days.rounded( .down ) ) * 24
    }

    /// Converts degrees to radians.
    static func radians( _ degrees: Double ) -> Double
    {
        degrees * .pi / 180
    }

    /// Converts radians to degrees.
    static func degrees( _ radians: Double ) -> Double
    {
        radians * 180 / .pi
    }

    /// The sine of an angle given in degrees.
    ///
    /// A convenience for the ecliptic perturbation series, whose terms are written
    /// with degree arguments.
    ///
    /// - Parameter degrees: The angle, in degrees.
    /// - Returns: Its sine.
    static func sineDegrees( _ degrees: Double ) -> Double
    {
        sin( self.radians( degrees ) )
    }

    /// The cosine of an angle given in degrees.
    ///
    /// A convenience for the ecliptic perturbation series, whose terms are written
    /// with degree arguments.
    ///
    /// - Parameter degrees: The angle, in degrees.
    /// - Returns: Its cosine.
    static func cosineDegrees( _ degrees: Double ) -> Double
    {
        cos( self.radians( degrees ) )
    }

    /// Reduces an angle in degrees to the `0 ..< 360` range.
    static func normalizedDegrees( _ value: Double ) -> Double
    {
        let remainder = value.truncatingRemainder( dividingBy: 360 )

        return remainder < 0 ? remainder + 360 : remainder
    }

    /// Reduces a value in hours to the `0 ..< 24` range.
    static func normalizedHours( _ value: Double ) -> Double
    {
        let remainder = value.truncatingRemainder( dividingBy: 24 )

        return remainder < 0 ? remainder + 24 : remainder
    }

    /// The obliquity of the ecliptic, in degrees: `23.4393 - 3.563e-7 · d`.
    ///
    /// - Parameter dayNumber: The day number `d`.
    /// - Returns: The obliquity, in degrees.
    static func obliquity( dayNumber: Double ) -> Double
    {
        23.4393 - 3.563e-7 * dayNumber
    }

    /// The local sidereal time, in hours, for a longitude at an instant.
    ///
    /// Uses the Sun's mean longitude at the instant, so the term already carries
    /// the sidereal-versus-solar rate: `LST = Ls/15 + 12 + UT + longitude/15`.
    ///
    /// - Parameters:
    ///   - date:      The instant to evaluate.
    ///   - longitude: The observer's longitude, in degrees (positive east).
    /// - Returns: The local sidereal time, in hours (`0 ..< 24`).
    static func localSiderealTimeHours( date: Date, longitude: Double ) -> Double
    {
        let d     = self.dayNumber( from: date )
        let ls    = SolarPosition.meanLongitude( dayNumber: d )
        let gmst0 = ls / 15 + 12
        let ut    = self.universalTimeHours( from: date )

        return self.normalizedHours( gmst0 + ut + longitude / 15 )
    }

    /// Reduces geocentric ecliptic rectangular coordinates to equatorial
    /// coordinates (right ascension and declination).
    ///
    /// - Parameters:
    ///   - x:         The ecliptic X component.
    ///   - y:         The ecliptic Y component.
    ///   - z:         The ecliptic Z component.
    ///   - dayNumber: The day number `d`, for the obliquity.
    /// - Returns: The equatorial coordinate.
    static func equatorial( eclipticX x: Double, eclipticY y: Double, eclipticZ z: Double, dayNumber: Double ) -> EquatorialCoordinate
    {
        let ecl = self.radians( self.obliquity( dayNumber: dayNumber ) )
        let xe  = x
        let ye  = y * cos( ecl ) - z * sin( ecl )
        let ze  = y * sin( ecl ) + z * cos( ecl )

        let rightAscension = self.normalizedDegrees( self.degrees( atan2( ye, xe ) ) )
        let declination    = self.degrees( atan2( ze, ( xe * xe + ye * ye ).squareRoot() ) )

        return EquatorialCoordinate( rightAscension: rightAscension, declination: declination )
    }

    /// Reduces an equatorial coordinate to the observer's local horizontal
    /// system at an instant.
    ///
    /// - Parameters:
    ///   - equatorial: The geocentric equatorial coordinate.
    ///   - date:       The instant to evaluate.
    ///   - location:   The observer's location.
    /// - Returns: The horizontal coordinate (azimuth and altitude).
    static func horizontal( of equatorial: EquatorialCoordinate, date: Date, location: GeographicLocation ) -> HorizontalCoordinate
    {
        let lst          = self.localSiderealTimeHours( date: date, longitude: location.longitude )
        let hourAngle    = self.radians( self.normalizedDegrees( ( lst - equatorial.rightAscension / 15 ) * 15 ) )
        let declination  = self.radians( equatorial.declination )
        let latitude     = self.radians( location.latitude )

        let x = cos( hourAngle ) * cos( declination )
        let y = sin( hourAngle ) * cos( declination )
        let z = sin( declination )

        let horizontalX = x * sin( latitude ) - z * cos( latitude )
        let horizontalY = y
        let horizontalZ = x * cos( latitude ) + z * sin( latitude )

        let azimuth  = self.normalizedDegrees( self.degrees( atan2( horizontalY, horizontalX ) ) + 180 )

        // `horizontalZ` is mathematically in `[-1, 1]`, but floating-point rounding at
        // the zenith or nadir can push it a hair past either bound and make `asin`
        // return NaN; clamp it — two-sided here, since the altitude reaches the nadir,
        // unlike the one-sided guard in `EquatorialCoordinate.angularSeparation`.
        let altitude = self.degrees( asin( Swift.min( 1, Swift.max( -1, horizontalZ ) ) ) )

        return HorizontalCoordinate( azimuth: azimuth, altitude: altitude )
    }
}
