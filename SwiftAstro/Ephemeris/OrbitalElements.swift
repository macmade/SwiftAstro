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

/// A body's Keplerian orbital elements at an instant, with the reductions (after
/// Schlyter) to heliocentric ecliptic rectangular coordinates.
///
/// Angles are in degrees; the semi-major axis and the resulting coordinates are
/// in astronomical units.
///
/// - Important: This is an internal helper for the library's own bound, elliptical
///   orbits (`eccentricity < 1`), not a general-purpose two-body solver. The
///   `trueAnomalyAndDistance` reduction takes `√(1 − e²)`, so an eccentricity of `1`
///   or more yields NaN. Every element set this library builds is a fixed
///   low-eccentricity body (the largest is Mercury at `e ≈ 0.206`), so the parabolic
///   and hyperbolic cases never arise.
struct OrbitalElements
{
    /// The longitude of the ascending node, `N`, in degrees.
    let longitudeOfAscendingNode: Double

    /// The inclination, `i`, in degrees.
    let inclination: Double

    /// The argument of perihelion, `w`, in degrees.
    let argumentOfPerihelion: Double

    /// The semi-major axis, `a`, in astronomical units.
    let semiMajorAxis: Double

    /// The eccentricity, `e`.
    let eccentricity: Double

    /// The mean anomaly, `M`, in degrees.
    let meanAnomaly: Double

    /// The convergence tolerance for the eccentric-anomaly iteration, in radians.
    private static let keplerTolerance = 1e-9

    /// The maximum number of eccentric-anomaly iterations.
    private static let keplerMaxIterations = 100

    /// The eccentric anomaly, in radians, solving Kepler's equation
    /// `M = E - e·sin E` by Newton's method from Schlyter's first approximation.
    private var eccentricAnomaly: Double
    {
        let e = self.eccentricity
        let m = Ephemeris.radians( Ephemeris.normalizedDegrees( self.meanAnomaly ) )

        var eccentric = m + e * sin( m ) * ( 1 + e * cos( m ) )
        var iteration = 0

        while iteration < Self.keplerMaxIterations
        {
            let delta = ( eccentric - e * sin( eccentric ) - m ) / ( 1 - e * cos( eccentric ) )

            eccentric -= delta
            iteration += 1

            if abs( delta ) < Self.keplerTolerance
            {
                break
            }
        }

        return eccentric
    }

    /// The true anomaly, in radians, and the heliocentric distance, in AU.
    var trueAnomalyAndDistance: ( trueAnomaly: Double, distance: Double )
    {
        let e         = self.eccentricity
        let a         = self.semiMajorAxis
        let eccentric = self.eccentricAnomaly

        let xv = a * ( cos( eccentric ) - e )
        let yv = a * ( ( 1 - e * e ).squareRoot() * sin( eccentric ) )

        return ( atan2( yv, xv ), ( xv * xv + yv * yv ).squareRoot() )
    }

    /// The heliocentric ecliptic rectangular coordinates, in AU.
    ///
    /// For the Sun's elements (`N = i = 0`) this is the Sun's geocentric ecliptic
    /// position, so the same reduction serves both the Sun and the planets.
    var heliocentricEcliptic: ( x: Double, y: Double, z: Double )
    {
        let ( trueAnomaly, distance ) = self.trueAnomalyAndDistance

        let node        = Ephemeris.radians( self.longitudeOfAscendingNode )
        let inclination = Ephemeris.radians( self.inclination )
        let perihelion  = trueAnomaly + Ephemeris.radians( self.argumentOfPerihelion )

        let x = distance * ( cos( node ) * cos( perihelion ) - sin( node ) * sin( perihelion ) * cos( inclination ) )
        let y = distance * ( sin( node ) * cos( perihelion ) + cos( node ) * sin( perihelion ) * cos( inclination ) )
        let z = distance * ( sin( perihelion ) * sin( inclination ) )

        return ( x, y, z )
    }
}
