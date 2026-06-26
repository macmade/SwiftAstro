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

/// Tests for ``MomentStarDetector``.
struct MomentStarDetectorTests
{
    /// For a 2D Gaussian, the half-flux radius is σ·√(2 ln 2).
    private static let hfrPerSigma  = ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// A single round Gaussian star is detected with the expected centroid, HFR, FWHM and near-zero eccentricity.
    @Test
    func detectsSingleRoundStarWithExpectedMetrics() throws
    {
        let sigma = 3.0
        let image = try SyntheticStarField( width: 100, height: 100, background: 200 )
            .addingStar( cx: 50, cy: 50, peak: 3000, sigma: sigma )
            .addingNoise( seed: 1, amplitude: 5 )
            .image()

        let field = try MomentStarDetector().detectStars( in: image )

        #expect( field.count == 1 )

        let star = try #require( field.stars.first )

        #expect( abs( star.x - 50 ) < 0.6 )
        #expect( abs( star.y - 50 ) < 0.6 )
        #expect( abs( star.fwhm - Self.fwhmPerSigma * sigma ) < 0.15 * Self.fwhmPerSigma * sigma )
        #expect( abs( star.hfr  - Self.hfrPerSigma  * sigma ) < 0.15 * Self.hfrPerSigma  * sigma )
        #expect( star.eccentricity < 0.2 )
    }

    /// An elongated Gaussian star yields the expected eccentricity.
    @Test
    func measuresEccentricityOfAnElongatedStar() throws
    {
        // σx = 2, σy = 4 → e = √(1 − σx²/σy²) = √0.75 ≈ 0.866.
        let image = try SyntheticStarField( width: 100, height: 100, background: 200 )
            .addingStar( cx: 50, cy: 50, peak: 3000, sigmaX: 2, sigmaY: 4 )
            .addingNoise( seed: 2, amplitude: 5 )
            .image()

        let field = try MomentStarDetector().detectStars( in: image )
        let star  = try #require( field.stars.first )

        #expect( field.count == 1 )
        #expect( abs( star.eccentricity - 0.866 ) < 0.12 )
    }

    /// Every star in a multi-star field is detected.
    @Test
    func countsMultipleStars() throws
    {
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 30, cy: 30, peak: 3000, sigma: 3 )
            .addingStar( cx: 90, cy: 30, peak: 2500, sigma: 2.5 )
            .addingStar( cx: 60, cy: 90, peak: 4000, sigma: 3.5 )
            .addingNoise( seed: 3, amplitude: 5 )
            .image()

        let field = try MomentStarDetector().detectStars( in: image )

        #expect( field.count == 3 )
        #expect( field.medianFWHM != nil )
        #expect( field.medianHFR  != nil )
    }

    /// A single hot pixel is rejected by the minimum pixel count.
    @Test
    func rejectsAHotPixel() throws
    {
        var field = SyntheticStarField( width: 64, height: 64, background: 200 )
            .addingNoise( seed: 4, amplitude: 5 )

        // A single very bright pixel: above threshold but only one pixel, so it
        // must be rejected by the minimum pixel count.
        field = field.addingStar( cx: 32, cy: 32, peak: 5000, sigma: 0.01 )

        let result = try MomentStarDetector().detectStars( in: field.image() )

        #expect( result.count == 0 )
    }

    /// A star within the edge margin is rejected.
    @Test
    func rejectsStarsTooCloseToTheEdge() throws
    {
        let image = try SyntheticStarField( width: 100, height: 100, background: 200 )
            .addingStar( cx: 2, cy: 50, peak: 3000, sigma: 3 )
            .addingNoise( seed: 5, amplitude: 5 )
            .image()

        let field = try MomentStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A blank, noise-only field yields no stars.
    @Test
    func findsNoStarsInABlankField() throws
    {
        let image = try SyntheticStarField( width: 64, height: 64, background: 200 )
            .addingNoise( seed: 6, amplitude: 5 )
            .image()

        let field = try MomentStarDetector().detectStars( in: image )

        #expect( field.count              == 0 )
        #expect( field.medianFWHM         == nil )
        #expect( field.medianEccentricity == nil )
    }
}
