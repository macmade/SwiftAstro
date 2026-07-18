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

/// Tests for ``MatchedFilterStarDetector``.
struct MatchedFilterStarDetectorTests
{
    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// Whether a star was detected within one pixel of an expected position.
    private func hasStar( _ field: StarField, nearX x: Double, y: Double ) -> Bool
    {
        field.stars.contains { abs( $0.x - x ) < 1 && abs( $0.y - y ) < 1 }
    }

    /// Every planted star is detected at its position, and nothing spurious is.
    @Test
    func detectsPlantedStars() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingStar( cx: 40, cy: 40, peak: 3000, sigma: 2 )
            .addingStar( cx: 120, cy: 50, peak: 2500, sigma: 2.2 )
            .addingStar( cx: 80, cy: 120, peak: 4000, sigma: 1.8 )
            .addingNoise( seed: 1, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 3 )
        #expect( self.hasStar( field, nearX: 40, y: 40 ) )
        #expect( self.hasStar( field, nearX: 120, y: 50 ) )
        #expect( self.hasStar( field, nearX: 80, y: 120 ) )
    }

    /// A smooth brightness gradient (extended-nebulosity proxy) produces no
    /// detections: the zero-sum matched filter has no response to it.
    @Test
    func findsNothingOnASmoothGradient() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingGradient( scaleX: 6, scaleY: 4 )
            .addingNoise( seed: 2, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A pure-noise field produces no detections.
    @Test
    func findsNothingInPureNoise() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingNoise( seed: 3, amplitude: 12 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// Single hot pixels are rejected — they are not point-spread-shaped.
    @Test
    func rejectsHotPixels() throws
    {
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 30, cy: 30, peak: 6000, sigma: 0.01 )
            .addingStar( cx: 80, cy: 80, peak: 8000, sigma: 0.01 )
            .addingNoise( seed: 4, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count == 0 )
    }

    /// A star's measured centroid is accurate to well under a pixel, including its
    /// sub-pixel position — so an overlay can register a marker on the star.
    @Test
    func measuresSubPixelCentroids() throws
    {
        let image = try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingStar( cx: 60.3,  cy: 90.7,  peak: 4000, sigma: 2 )
            .addingStar( cx: 110.8, cy: 40.2,  peak: 3500, sigma: 2 )
            .addingNoise( seed: 15, amplitude: 6 )
            .image()

        let field = try MatchedFilterStarDetector( configuration: .init( detectsBrightStars: false ) ).detectStars( in: image )
        let first  = try #require( field.stars.first { abs( $0.x - 60.3 ) < 1 && abs( $0.y - 90.7 ) < 1 } )
        let second = try #require( field.stars.first { abs( $0.x - 110.8 ) < 1 && abs( $0.y - 40.2 ) < 1 } )

        #expect( abs( first.x - 60.3 ) < 0.15 )
        #expect( abs( first.y - 90.7 ) < 0.15 )
        #expect( abs( second.x - 110.8 ) < 0.15 )
        #expect( abs( second.y - 40.2 ) < 0.15 )
    }

    /// The reported metrics of a detected star match the planted profile.
    @Test
    func measuresDetectedStarMetrics() throws
    {
        let sigma = 2.0
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 60, cy: 60, peak: 4000, sigma: sigma )
            .addingNoise( seed: 5, amplitude: 6 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )
        let star  = try #require( field.stars.first )

        #expect( field.count == 1 )
        #expect( abs( star.x - 60 ) < 0.3 )
        #expect( abs( star.y - 60 ) < 0.3 )
        #expect( abs( star.fwhm - Self.fwhmPerSigma * sigma ) < 0.15 * Self.fwhmPerSigma * sigma )
        #expect( star.eccentricity < 0.2 )
    }

    /// The auto-estimated FWHM is close to the planted profile's FWHM.
    @Test
    func autoEstimatesFWHMNearThePlantedValue() throws
    {
        let sigma = 2.5
        let image = try SyntheticStarField( width: 200, height: 200, background: 200 )
            .addingStar( cx: 50, cy: 50, peak: 5000, sigma: sigma )
            .addingStar( cx: 150, cy: 60, peak: 4500, sigma: sigma )
            .addingStar( cx: 100, cy: 150, peak: 6000, sigma: sigma )
            .addingNoise( seed: 6, amplitude: 8 )
            .image()

        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        #expect( abs( estimated - Self.fwhmPerSigma * sigma ) < 0.25 * Self.fwhmPerSigma * sigma )
    }

    /// On a dense field of small stars, the estimate tracks the true small scale
    /// rather than blowing up: sizing a bright star's footprint that has merged its
    /// crowded neighbours would read several times too large, which is what made a
    /// dense, drizzled master under-detect (the size-band cut then rejected the
    /// whole real population). The merge-aware estimate sizes the isolated stars.
    @Test
    func autoEstimatesFWHMOnADenseSmallStarField() throws
    {
        let sigma  = 1.2
        let places: [ ( x: Double, y: Double, peak: Double ) ] = ( 0 ..< 30 ).flatMap
        {
            row -> [ ( x: Double, y: Double, peak: Double ) ] in

            ( 0 ..< 30 ).map
            {
                column -> ( x: Double, y: Double, peak: Double ) in

                let x = 12.0 + ( Double( column ) * 6.0 )
                let y = 12.0 + ( Double( row ) * 6.0 )

                return ( x: x, y: y, peak: ( ( row + column ) % 5 == 0 ) ? 9000 : 2600 )
            }
        }

        let base  = SyntheticStarField( width: 200, height: 200, background: 200 )
        let image = try places.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: sigma ) }
            .addingNoise( seed: 9, amplitude: 8 )
            .image()

        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        // Near the true small FWHM, not the several-fold blow-up a merged footprint
        // would produce on this crowding.
        #expect( estimated < 2.0 * Self.fwhmPerSigma * sigma )
    }

    /// The FWHM bootstrap reads its background from the window's outer annulus, not
    /// the whole window (IMP-12). A bright star's core fills the fixed radius-10
    /// bootstrap window, so a whole-window median reads the star itself as
    /// "background", lands the footprint level inside the core, and sizes the star
    /// well below its true scale. The annulus reads true sky beyond the core, so
    /// these bright, window-filling stars size to a larger, more stellar FWHM.
    @Test
    func bootstrapSizesBrightWindowFillingStarsFromTheSkyAnnulus() throws
    {
        // Bright stars whose above-noise skirt reaches past the fixed radius-10
        // bootstrap window, so a whole-window background read is inflated by the
        // star's own flux.
        let places: [ ( x: Double, y: Double ) ] =
            [
                ( 60, 60 ), ( 150, 60 ), ( 240, 60 ),
                ( 60, 150 ), ( 150, 150 ), ( 240, 150 ),
                ( 60, 240 ), ( 150, 240 ), ( 240, 240 ),
            ]

        let base  = SyntheticStarField( width: 300, height: 300, background: 200 )
        let image = try places.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 30000, sigma: 6 ) }
            .addingNoise( seed: 8, amplitude: 8 )
            .image()

        let estimated = try #require( MatchedFilterStarDetector.estimateFWHM( in: image ) )

        // The annulus read sizes these ~8.6 px; a whole-window read reads the cores
        // as background and shrinks the footprint, sizing them ~7.6 px. The bound
        // sits between the two, guarding the annulus-sky robustness. Both under-size
        // the planted 14.1 px because the fixed bootstrap window clips the footprint
        // — the refinement corrects that downstream; the bootstrap only needs a
        // sound seed, which the whole-window read under-delivers here.
        #expect( estimated > 8.0 )
        #expect( estimated < 12 )
    }

    /// A manual FWHM override bypasses auto-estimation and still detects stars.
    @Test
    func honorsAManualFWHMOverride() throws
    {
        let image = try SyntheticStarField( width: 120, height: 120, background: 200 )
            .addingStar( cx: 60, cy: 60, peak: 4000, sigma: 2 )
            .addingNoise( seed: 7, amplitude: 6 )
            .image()

        let detector = MatchedFilterStarDetector( configuration: .init( expectedFWHM: 4.7 ) )
        let field    = try detector.detectStars( in: image )

        #expect( field.count == 1 )
    }

    /// A recall / metric check over the ``SyntheticStarGrid`` ground-truth fixture
    /// (COS-8), which was otherwise exercised only by its own generator self-test. On
    /// a small grid grading from small round stars to large saturated ones, the
    /// detector recovers most planted stars near their true centres, and the detected
    /// sizes track the planted size gradient (bottom rows broader than top rows).
    @Test
    func recoversSyntheticStarGridGroundTruth() throws
    {
        let grid  = SyntheticStarGrid( columns: 4, rows: 4, spacing: 70, minSigma: 1.4, maxSigma: 4.0, minPeak: 2600, maxPeak: 80000, maxEccentricity: 0.5 )
        let image = try grid.image()
        let field = try MatchedFilterStarDetector().detectStars( in: image )
        let truth = grid.stars

        func detected( near star: SyntheticStarGrid.Star ) -> Star?
        {
            field.stars.first { abs( $0.x - star.x ) < 3 && abs( $0.y - star.y ) < 3 }
        }

        let recalled = truth.filter { detected( near: $0 ) != nil }

        // Recall: essentially every planted star is recovered near its true centre,
        // with no spurious blow-up.
        #expect( recalled.count >= truth.count - 2 )
        #expect( field.count <= truth.count + 4 )

        let topRow    = truth.filter { $0.row == 0 }.compactMap { detected( near: $0 )?.fwhm }
        let bottomRow = truth.filter { $0.row == grid.rows - 1 }.compactMap { detected( near: $0 )?.fwhm }

        let topMean    = topRow.reduce( 0, + ) / Double( Swift.max( topRow.count, 1 ) )
        let bottomMean = bottomRow.reduce( 0, + ) / Double( Swift.max( bottomRow.count, 1 ) )

        // The detected sizes track the planted top-to-bottom size gradient.
        #expect( topRow.isEmpty == false )
        #expect( bottomRow.isEmpty == false )
        #expect( bottomMean > 1.5 * topMean )
    }

    // MARK: - Configuration knob toggles (IMP-6)

    /// Three well-separated planted stars, the shared fixture for the knob-toggle
    /// tests: at the default configuration all three are detected, so each test can
    /// show a single knob, set to an extreme, changing that outcome.
    private func plantedField() throws -> PixelBuffer
    {
        try SyntheticStarField( width: 160, height: 160, background: 200 )
            .addingStar( cx: 40, cy: 40, peak: 3000, sigma: 2 )
            .addingStar( cx: 120, cy: 50, peak: 2500, sigma: 2.2 )
            .addingStar( cx: 80, cy: 120, peak: 4000, sigma: 1.8 )
            .addingNoise( seed: 1, amplitude: 8 )
            .image()
    }

    /// The detection threshold is honoured: raised beyond any convolved peak, no
    /// candidate survives.
    @Test
    func honorsThresholdSigma() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector().detectStars( in: image ).count == 3 )
        #expect( try MatchedFilterStarDetector( configuration: .init( thresholdSigma: 100000 ) ).detectStars( in: image ).count == 0 )
    }

    /// `saturationLevel` is honoured on the matched-filter path: set below every
    /// star's peak, all are dropped as saturated.
    @Test
    func honorsSaturationLevel() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( saturationLevel: 1000 ) ).detectStars( in: image ).count == 0 )
    }

    /// `minSeparation` is honoured: a separation spanning the whole frame keeps only
    /// the single brightest peak.
    @Test
    func honorsMinSeparation() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( minSeparation: 1000 ) ).detectStars( in: image ).count == 1 )
    }

    /// `edgeMargin` is honoured: a margin that reaches every planted star's band
    /// rejects them all as edge-clipped.
    @Test
    func honorsEdgeMargin() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( edgeMargin: 55 ) ).detectStars( in: image ).count == 0 )
    }

    /// `sharpnessLow` is honoured: a floor of `1` rejects every real (point-spread)
    /// star, whose neighbours always sit below its centre.
    @Test
    func honorsSharpnessLow() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( sharpnessLow: 1 ) ).detectStars( in: image ).count == 0 )
    }

    /// `roundnessLimit` is honoured: a limit of `0` admits only a perfectly circular
    /// profile, so the noisy real stars are rejected.
    @Test
    func honorsRoundnessLimit() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( roundnessLimit: 0 ) ).detectStars( in: image ).count < 3 )
    }

    /// `minFWHMFactor` is honoured: a floor far above the matched-filter scale
    /// rejects every star as too small.
    @Test
    func honorsMinFWHMFactor() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( minFWHMFactor: 5 ) ).detectStars( in: image ).count == 0 )
    }

    /// `maxFWHMFactor` is honoured: a ceiling far below the matched-filter scale
    /// rejects every star as too large.
    @Test
    func honorsMaxFWHMFactor() throws
    {
        let image = try self.plantedField()

        #expect( try MatchedFilterStarDetector( configuration: .init( maxFWHMFactor: 0.1 ) ).detectStars( in: image ).count == 0 )
    }

    /// A multi-channel image is rejected.
    @Test
    func rejectsMultiChannelInput() throws
    {
        let image = try PixelBuffer( width: 4, height: 4, channels: 3, pixels: [ Double ]( repeating: 0, count: 48 ), isNormalized: false )

        #expect( throws: SwiftAstro.Error.self )
        {
            try MatchedFilterStarDetector().detectStars( in: image )
        }
    }
}
