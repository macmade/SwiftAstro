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
/// frames, decoded through ``FITSTestImage`` — the shared ``FITSImageDecoder``'s
/// readRawPixels + BZERO / BSCALE + demosaic recipe.
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

    /// Relative tolerance on the median HFR. The detector now measures the same
    /// half-flux radius the acquisition software does (the NINA flux-weighted mean,
    /// HFD/2), so this is a genuine like-for-like comparison; the tolerance absorbs
    /// the measurement differences that remain between two independent
    /// implementations (aperture size, local-background estimate, the per-star fit
    /// centre).
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
        #expect( Swift.abs( medianHFR - Self.reportedHFR ) <= Self.hfrTolerance * Self.reportedHFR )

        // No detection is grossly wider than the population it sits in. This frame
        // covers the Orion nebula, and its core is the hard case for the bright-star
        // pass: a saturated cluster of stars on gas so bright that the sky annulus
        // used for photometry lies *inside* the nebulosity. Counting the blob's
        // stellar peaks against that annulus puts the counting level within a few
        // hundred ADU of the saturation ceiling, so no peak is visible, the
        // multiplicity cut cannot fire, and the whole core is reported as one giant
        // "star" — it measured HFR 13.8 against this frame's 4.0 median. Counting
        // against the mapped sky instead sees its eight peaks and drops it.
        let widest = try #require( field.stars.map { $0.hfr }.max() )

        #expect( widest < 2 * Self.reportedHFR )
    }

    /// In the rich M35 star cluster the detector finds the cluster's *population* of
    /// well-formed stars, with a stellar — not sub-pixel-noise — median HFR.
    ///
    /// This crop is the dense-field regression fixture. The detection scale decides
    /// how many stars survive here: sized from the frame's bloomed brightest stars
    /// it reads ~15 px against a true ~3 px, and the matched filter's kernel and
    /// size-band cut then reject essentially the entire cluster — this crop returned
    /// **29** stars where it holds several hundred. Grounding the scale in the local
    /// background instead recovers them, so the count bound below is deliberately
    /// far above what the collapsed behaviour could reach.
    @Test
    func detectsWellFormedStarsInTheM35Cluster() throws
    {
        let full  = try FITSTestImage.esaM35BlueDetection()
        let image = try FITSTestImage.crop( full, x: ( full.width - 512 ) / 2, y: ( full.height - 512 ) / 2, width: 512, height: 512 )
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count >= 200 )

        let medianFWHM = try #require( field.medianFWHM )
        let medianHFR  = try #require( field.medianHFR )

        // The population's own scale — a few pixels — not the bloomed bright stars'.
        #expect( medianFWHM > 2 )
        #expect( medianFWHM < 5 )

        // A stellar, not sub-pixel-noise, median. The upper bound is a "not blown
        // up" sanity guard, loosened from the pre-rewrite value: the NINA half-flux
        // radius is a flux-weighted mean (definitionally larger than the former
        // enclosed-50% radius) and, unlike it, is crowding-sensitive, so this dense
        // cluster core reads a few px higher. (Crowding robustness is M5.14.)
        #expect( medianHFR > 1.5 )
        #expect( medianHFR < 7 )
    }

    /// On a single, short, light-polluted Seestar S30 M42 sub — a real
    /// one-shot-colour frame whose faint stars sit over bright nebulosity — the
    /// detector finds a healthy population of well-formed stars, not zero.
    ///
    /// This is the regression fixture for the "zero stars on a real sub" bug: the
    /// original bootstrap over-estimated the FWHM from the frame's bloomed bright
    /// stars, and the per-star Gaussian fit failed on the faint majority, so the
    /// detector returned no stars at all. It runs over the full frame (not a crop),
    /// because both failures are whole-frame properties (the bloomed bright stars
    /// that biased the bootstrap are spread across it).
    @Test
    func detectsStarsOnAShortLightPollutedSeestarSub() throws
    {
        let image = try FITSTestImage.seestarM42Detection()
        let field = try MatchedFilterStarDetector().detectStars( in: image )

        // The headline regression guard: a real sub must not detect zero stars.
        #expect( field.count > 0 )

        // A healthy field of the frame's faint stars — well above a handful, and
        // bounded so a noise/nebulosity blow-up would still fail.
        #expect( field.count >= 40 )
        #expect( field.count <= 5000 )

        let medianHFR  = try #require( field.medianHFR )
        let medianFWHM = try #require( field.medianFWHM )
        let medianEcc  = try #require( field.medianEccentricity )

        // Stellar, physically-meaningful metrics measured on the linear data.
        #expect( medianHFR.isFinite )
        #expect( medianHFR > 0.5 )
        #expect( medianHFR < 8 )
        #expect( medianFWHM.isFinite )
        #expect( medianFWHM > 1 )
        #expect( medianFWHM < 12 )
        #expect( medianEcc >= 0 )
        #expect( medianEcc <= 1 )
    }

    /// On a real frame dominated by bright nebulosity the auto-estimated detection
    /// scale still describes the frame's stars.
    ///
    /// This is the failure a global background produces at its starkest. Over this
    /// C6 / ASI585 M42 sub, 4.8% of the pixels sit above the whole-image
    /// `median + 10σ`, so the scale bootstrap's "brightest stars" scan returns
    /// **24 137** peaks — noise ripples riding on the gas — on a frame holding a few
    /// dozen stars. Their slivers of footprint sized the frame at **1.99 px** against
    /// a true ~7.8 px, which both starves the matched filter's size band and, at that
    /// scale, lets the bright pass fragment the gas into scores of spurious "stars".
    /// Measured against the local background the gas is background, and the scale
    /// comes back to the stars.
    @Test
    func estimatesAStellarScaleOnABrightNebulosityFrame() throws
    {
        let image     = try FITSTestImage.c6ASI585M42Detection()
        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        // The frame's own star population reads ~7.8 px; the bound brackets it well
        // clear of the ~2 px a nebulosity-poisoned estimate returns.
        #expect( estimated > 5 )
        #expect( estimated < 11 )
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
