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

/// Tests for ``HorizontalCoordinate`` — the ideal-horizon and refraction-aware
/// "above the horizon" predicates, checked against fixed altitudes (not the sign of
/// the value they compute from).
struct HorizontalCoordinateTests
{
    /// `isAboveHorizon` is the strict geometric `0°` horizon: a body exactly on the
    /// horizon is not above it.
    @Test
    func isAboveHorizonUsesAStrictGeometricZeroBoundary()
    {
        #expect( HorizontalCoordinate( azimuth: 0, altitude:  0 ).isAboveHorizon == false )
        #expect( HorizontalCoordinate( azimuth: 0, altitude:  0.001 ).isAboveHorizon == true )
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -0.001 ).isAboveHorizon == false )
        #expect( HorizontalCoordinate( azimuth: 0, altitude: 45 ).isAboveHorizon == true )
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -30 ).isAboveHorizon == false )
    }

    /// The refraction-aware predicate uses the apparent horizon at `−refraction`: a
    /// body just below the ideal horizon is up once refraction is allowed for, and the
    /// threshold itself is strict.
    @Test
    func isAboveHorizonWithRefractionUsesTheApparentHorizon()
    {
        // Default refraction (~34′): a body at −0.5° is up, one at −0.7° is not.
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -0.5 ).isAboveHorizon( refraction: HorizontalCoordinate.horizonRefraction ) == true )
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -0.7 ).isAboveHorizon() == false )
        #expect( HorizontalCoordinate( azimuth: 0, altitude:  0 ).isAboveHorizon() == true )

        // The apparent horizon is strict: a body exactly at −refraction is not above it.
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -HorizontalCoordinate.horizonRefraction ).isAboveHorizon() == false )

        // The Sun-centre sunrise/sunset convention (semidiameter included): −0.833°.
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -0.8 ).isAboveHorizon( refraction: 0.833 ) == true )
        #expect( HorizontalCoordinate( azimuth: 0, altitude: -0.9 ).isAboveHorizon( refraction: 0.833 ) == false )
    }

    /// The default refraction is the standard horizon value (~34′).
    @Test
    func horizonRefractionIsTheStandardValue()
    {
        #expect( HorizontalCoordinate.horizonRefraction == 0.583 )
    }
}
