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

/// Tests for ``EquatorialCoordinate/angularSeparation(to:)``.
struct EquatorialCoordinateTests
{
    /// A coordinate is zero degrees from itself.
    @Test
    func separationFromItselfIsZero()
    {
        let coordinate = EquatorialCoordinate( rightAscension: 123.456, declination: -12.34 )

        #expect( Swift.abs( coordinate.angularSeparation( to: coordinate ) ) < 1e-6 )
    }

    /// Two points on the equator 90° apart in right ascension are 90° apart.
    @Test
    func separationAlongTheEquatorEqualsTheRightAscensionDifference()
    {
        let a = EquatorialCoordinate( rightAscension:  10, declination: 0 )
        let b = EquatorialCoordinate( rightAscension: 100, declination: 0 )

        #expect( Swift.abs( a.angularSeparation( to: b ) - 90 ) < 1e-6 )
    }

    /// A point at the north celestial pole is its declination's complement — 90° —
    /// from any point on the equator, whatever its right ascension.
    @Test
    func separationFromThePoleEqualsTheColatitude()
    {
        let pole     = EquatorialCoordinate( rightAscension:   0, declination: 90 )
        let equator1 = EquatorialCoordinate( rightAscension:  37, declination:  0 )
        let equator2 = EquatorialCoordinate( rightAscension: 200, declination:  0 )

        #expect( Swift.abs( pole.angularSeparation( to: equator1 ) - 90 ) < 1e-6 )
        #expect( Swift.abs( pole.angularSeparation( to: equator2 ) - 90 ) < 1e-6 )
    }

    /// Antipodal points — opposite in right ascension and declination — are 180°
    /// apart.
    @Test
    func separationBetweenAntipodesIs180()
    {
        let a = EquatorialCoordinate( rightAscension:  0, declination:  45 )
        let b = EquatorialCoordinate( rightAscension: 180, declination: -45 )

        #expect( Swift.abs( a.angularSeparation( to: b ) - 180 ) < 1e-6 )
    }

    /// The separation is symmetric: measuring A→B equals B→A.
    @Test
    func separationIsSymmetric()
    {
        let a = EquatorialCoordinate( rightAscension:  83.8, declination:  -5.4 )
        let b = EquatorialCoordinate( rightAscension: 201.3, declination:  54.9 )

        #expect( Swift.abs( a.angularSeparation( to: b ) - b.angularSeparation( to: a ) ) < 1e-9 )
    }

    /// A small separation across the 0°/360° right-ascension wrap is measured the
    /// short way round, not as a near-360° gap.
    @Test
    func separationWrapsAcrossZeroRightAscension()
    {
        let a = EquatorialCoordinate( rightAscension: 359, declination: 0 )
        let b = EquatorialCoordinate( rightAscension:   1, declination: 0 )

        #expect( Swift.abs( a.angularSeparation( to: b ) - 2 ) < 1e-6 )
    }
}
