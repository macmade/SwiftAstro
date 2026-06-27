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

/// End-to-end validation on a real one-shot-colour light frame.
///
/// This locks in the fix from the debugging effort: the committed RGGB Bayer
/// frame is demosaiced to grayscale (``BayerGrayscaleConverter``) and run
/// through ``MomentStarDetector``, and the result is checked against the
/// half-flux radius the acquisition software reported in the filename
/// (`…_H3.69.fits`). Before the fix the detector latched onto Bayer/hot-pixel
/// fragments (median HFR ≈ 1.4 px); this test guards against that regression.
struct RealFrameValidationTests
{
    /// The acquisition software's reported half-flux radius, in pixels, parsed
    /// from the `H3.69` token of the frame's filename.
    private static let reportedHFR = 3.69

    /// Relative tolerance on the median HFR.
    ///
    /// The detector measures HFR over each source's background-subtracted pixels
    /// above the detection threshold, which is a different definition than
    /// whatever the acquisition software used, so an exact match is not expected.
    /// At authoring time the measured median HFR was ≈ 3.37 px (~9 % below the
    /// reported 3.69), so ±20 % comfortably accommodates the definitional
    /// difference while still rejecting the pre-fix failure (≈ 1.4 px, ~62 % low).
    private static let hfrTolerance = 0.20

    /// Detection parameters chosen for this frame: a high threshold and minimum
    /// pixel count restrict the measurement to bright, well-sampled stars (the
    /// usual practice for focus/quality metrics) and reject hot-pixel and noise
    /// clusters. See the Milestone 2/3 diagnosis for the supporting tuning data.
    private static let configuration = MomentStarDetector.Configuration( thresholdSigma: 12, minPixelCount: 25 )

    /// On the real frame the detector finds a plausible population of stars whose
    /// median HFR matches the acquisition software's reported value within
    /// tolerance, with finite, sane aggregate metrics.
    @Test
    func detectsStarsOnTheRealFrameNearReportedHFR() throws
    {
        let mosaic = try FITSTestImage.realLightFrame()
        let gray   = try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: mosaic )
        let field  = try MomentStarDetector( configuration: Self.configuration ).detectStars( in: gray )

        // A plausible star count: a sane lower bound (≈ 117 detected at authoring
        // time) guarding against "finds nothing", and a loose upper bound
        // guarding against a fragmentation regression.
        #expect( field.count >= 20 )
        #expect( field.count <= 1000 )

        let medianHFR  = try #require( field.medianHFR )
        let medianFWHM = try #require( field.medianFWHM )
        let medianEcc  = try #require( field.medianEccentricity )

        // Aggregate metrics are finite and physically sane.
        #expect( medianHFR.isFinite,  "median HFR should be finite"  )
        #expect( medianHFR > 0 )
        #expect( medianFWHM.isFinite, "median FWHM should be finite" )
        #expect( medianFWHM > 0 )
        #expect( medianEcc >= 0 )
        #expect( medianEcc <= 1 )

        // The headline assertion: median HFR ≈ the reported 3.69 px.
        #expect( abs( medianHFR - Self.reportedHFR ) <= Self.hfrTolerance * Self.reportedHFR )
    }
}
