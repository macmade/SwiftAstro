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
import SwiftPixel
import Testing

/// Tests for the ``GaussianFit/Parameters`` initial guess seeded from
/// ``StarMoments``.
struct GaussianFitStarMomentsTests
{
    /// A rotated elliptical Gaussian under noise is recovered when the fit's
    /// initial guess is seeded from a moment measurement, as the detector does.
    @Test
    func recoversARotatedEllipticalGaussianSeededFromMoments() throws
    {
        let truth     = GaussianFit.Parameters( amplitude: 3000, x: 20.4, y: 19.6, sigmaX: 2, sigmaY: 4, theta: 30 * .pi / 180, background: 200 )
        let radius    = 18
        let size      = ( 2 * radius ) + 1
        var generator = DeterministicNoise( seed: 42 )

        let samples = ( 0 ..< ( size * size ) ).map
        {
            index -> ( x: Double, y: Double, value: Double ) in

            let x = truth.x - Double( radius ) + Double( index % size )
            let y = truth.y - Double( radius ) + Double( index / size )

            return ( x: x, y: y, value: truth.value( atX: x, y: y ) + ( generator.next() * 8 ) )
        }

        // Seed the fit from the moment measurement, as the detector will.
        let moments = try #require( StarMoments( samples: samples, background: 200 ) )
        let guess   = GaussianFit.Parameters( moments: moments, amplitude: 2800, background: 200 )

        let fit = try #require( GaussianFit.fit( samples: samples, initialGuess: guess ) )

        // The two axis lengths are recovered regardless of which is labelled x/y.
        let sigmas = [ abs( fit.sigmaX ), abs( fit.sigmaY ) ].sorted()

        #expect( abs( sigmas[ 0 ] - 2 ) < 0.2 )
        #expect( abs( sigmas[ 1 ] - 4 ) < 0.2 )
        #expect( abs( fit.x - truth.x ) < 0.1 )
        #expect( abs( fit.y - truth.y ) < 0.1 )
        #expect( abs( fit.amplitude - truth.amplitude ) < 0.05 * truth.amplitude )

        // The fitted surface reproduces the data (validates orientation too).
        let rms = ( samples.reduce( 0.0 ) { $0 + pow( fit.value( atX: $1.x, y: $1.y ) - $1.value, 2 ) } / Double( samples.count ) ).squareRoot()

        #expect( rms < 20 )
    }
}
