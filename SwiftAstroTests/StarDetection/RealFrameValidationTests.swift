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

/// End-to-end validation of ``MatchedFilterStarDetector`` on real astronomical
/// frames, decoded through the library's ``FITSImageDecoder/detectionImage(from:)``
/// path exactly as a consumer would.
///
/// These lock in the matched-filter rewrite: the headline check is that the
/// committed one-shot-colour frame's median half-flux radius matches the value
/// the acquisition software reported in its filename (`…_H3.69.fits`). The M35
/// and M42 checks run over a cropped central region — each detected star is
/// Gaussian-fitted, which is too slow over the full multi-megapixel frames in an
/// unoptimized test build — and guard the purity behaviour: real stars in a rich
/// cluster (M35) and, crucially, no latching onto bright extended nebulosity
/// (M42), which is what the old global-threshold detector did.
struct RealFrameValidationTests
{
    /// The acquisition software's reported half-flux radius, in pixels, parsed
    /// from the `H3.69` token of the frame's filename.
    private static let reportedHFR = 3.69

    /// Relative tolerance on the median HFR. The detector measures HFR over a
    /// Gaussian-fitted profile, a different definition than the acquisition
    /// software's, so an exact match is not expected; at authoring time the
    /// measured median was ≈ 3.75 px (~2 % high).
    private static let hfrTolerance = 0.20

    /// On the real one-shot-colour frame the detector finds a plausible star
    /// population whose median HFR matches the reported value within tolerance.
    @Test
    func detectsStarsOnTheRealFrameNearReportedHFR() throws
    {
        let image = try FITSTestImage.realLightFrameDetection()
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        // A sane lower bound guards against "finds nothing"; a loose upper bound
        // guards against a noise/nebulosity blow-up.
        #expect( field.count >= 20 )
        #expect( field.count <= 1000 )

        let medianHFR  = try #require( field.medianHFR )
        let medianFWHM = try #require( field.medianFWHM )
        let medianEcc  = try #require( field.medianEccentricity )

        #expect( medianHFR.isFinite )
        #expect( medianHFR > 0 )
        #expect( medianFWHM.isFinite )
        #expect( medianFWHM > 0 )
        #expect( medianEcc >= 0 )
        #expect( medianEcc <= 1 )

        // The headline assertion: median HFR ≈ the reported 3.69 px.
        #expect( abs( medianHFR - Self.reportedHFR ) <= Self.hfrTolerance * Self.reportedHFR )
    }

    /// In the rich M35 star cluster the detector finds a plausible population of
    /// well-formed stars with a stellar — not sub-pixel-noise — median HFR.
    @Test
    func detectsWellFormedStarsInTheM35Cluster() throws
    {
        let full  = try FITSTestImage.esaM35BlueDetection()
        let image = try FITSTestImage.crop( full, x: ( full.width - 512 ) / 2, y: ( full.height - 512 ) / 2, width: 512, height: 512 )
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count >= 5 )

        let medianHFR = try #require( field.medianHFR )

        // Well above 1 px — the pre-rewrite detector reported ≈ 1.25 px of
        // sub-pixel noise clusters here.
        #expect( medianHFR > 1.5 )
        #expect( medianHFR < 5 )
    }

    /// Over M42's bright core the matched filter does not latch onto the
    /// nebulosity: it returns a bounded number of compact, star-like detections,
    /// not the contour of hundreds the old global-threshold detector produced.
    @Test
    func doesNotLatchOntoTheM42Nebula() throws
    {
        let full  = try FITSTestImage.m42Stack()
        let image = try FITSTestImage.crop( full, x: ( full.width - 512 ) / 2, y: ( full.height - 512 ) / 2, width: 512, height: 512 )
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        // The anti-nebula guard: a star-shaped handful, not a nebula contour of
        // hundreds (which is what the old global-threshold detector produced).
        #expect( field.count <= 150 )

        if let medianHFR = field.medianHFR
        {
            #expect( medianHFR > 1 )
            #expect( medianHFR < 5 )
        }
    }
}
