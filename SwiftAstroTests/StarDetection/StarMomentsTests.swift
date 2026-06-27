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

/// Tests for ``StarMoments``.
struct StarMomentsTests
{
    /// For a 2D Gaussian, the half-flux radius is σ·√(2 ln 2).
    private static let hfrPerSigma  = ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// Builds a dense grid of samples of an elliptical Gaussian centred in the
    /// window, so the moment math sees the full profile.
    ///
    /// - Parameters:
    ///   - sigmaX:     The Gaussian standard deviation along x.
    ///   - sigmaY:     The Gaussian standard deviation along y.
    ///   - peak:       The peak value above the background.
    ///   - background: The flat background level.
    ///   - radius:     The half-size of the square window, in pixels.
    /// - Returns: The samples and the window centre, which is the expected
    ///   centroid.
    private func gaussianSamples( sigmaX: Double, sigmaY: Double, peak: Double, background: Double, radius: Int ) -> ( samples: [ ( x: Double, y: Double, value: Double ) ], center: Double )
    {
        let size   = ( 2 * radius ) + 1
        let center = Double( radius )

        let samples = ( 0 ..< ( size * size ) ).map
        {
            index -> ( x: Double, y: Double, value: Double ) in

            let x        = Double( index % size )
            let y        = Double( index / size )
            let dx       = x - center
            let dy       = y - center
            let exponent = ( ( dx * dx ) / ( 2 * sigmaX * sigmaX ) ) + ( ( dy * dy ) / ( 2 * sigmaY * sigmaY ) )

            return ( x: x, y: y, value: background + ( peak * exp( -exponent ) ) )
        }

        return ( samples: samples, center: center )
    }

    /// A round Gaussian yields the expected centroid, FWHM, HFR and near-zero
    /// eccentricity.
    @Test
    func measuresARoundGaussian() throws
    {
        let sigma     = 3.0
        let fixture   = self.gaussianSamples( sigmaX: sigma, sigmaY: sigma, peak: 3000, background: 200, radius: 15 )
        let moments   = try #require( StarMoments( samples: fixture.samples, background: 200 ) )

        #expect( abs( moments.x - fixture.center ) < 0.05 )
        #expect( abs( moments.y - fixture.center ) < 0.05 )
        #expect( abs( moments.fwhm - Self.fwhmPerSigma * sigma ) < 0.05 * Self.fwhmPerSigma * sigma )
        #expect( abs( moments.hfr  - Self.hfrPerSigma  * sigma ) < 0.10 * Self.hfrPerSigma  * sigma )
        #expect( moments.eccentricity < 0.05 )
    }

    /// An elongated Gaussian yields the expected eccentricity.
    @Test
    func measuresEccentricityOfAnElongatedGaussian() throws
    {
        // σx = 2, σy = 4 → e = √(1 − σx²/σy²) = √0.75 ≈ 0.866.
        let fixture = self.gaussianSamples( sigmaX: 2, sigmaY: 4, peak: 3000, background: 200, radius: 20 )
        let moments = try #require( StarMoments( samples: fixture.samples, background: 200 ) )

        #expect( abs( moments.eccentricity - 0.866 ) < 0.05 )
    }

    /// The flux-weighted centroid follows the star's position.
    @Test
    func centroidTracksAnOffsetStar() throws
    {
        let size   = 31
        let cx     = 12.0
        let cy     = 18.0
        let sigma  = 3.0

        let samples = ( 0 ..< ( size * size ) ).map
        {
            index -> ( x: Double, y: Double, value: Double ) in

            let x        = Double( index % size )
            let y        = Double( index / size )
            let dx       = x - cx
            let dy       = y - cy
            let exponent = ( ( dx * dx ) + ( dy * dy ) ) / ( 2 * sigma * sigma )

            return ( x: x, y: y, value: 200 + ( 3000 * exp( -exponent ) ) )
        }

        let moments = try #require( StarMoments( samples: samples, background: 200 ) )

        #expect( abs( moments.x - cx ) < 0.05 )
        #expect( abs( moments.y - cy ) < 0.05 )
    }

    /// A sample set with no flux above the background yields no measurement.
    @Test
    func returnsNilWhenThereIsNoFlux() throws
    {
        let samples = ( 0 ..< 25 ).map
        {
            index -> ( x: Double, y: Double, value: Double ) in

            ( x: Double( index % 5 ), y: Double( index / 5 ), value: 200 )
        }

        let moments = StarMoments( samples: samples, background: 200 )

        #expect( moments == nil )
    }
}
