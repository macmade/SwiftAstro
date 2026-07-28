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
        field.stars.contains { Swift.abs( $0.x - x ) < 1 && Swift.abs( $0.y - y ) < 1 }
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
        let first  = try #require( field.stars.first { Swift.abs( $0.x - 60.3 ) < 1 && Swift.abs( $0.y - 90.7 ) < 1 } )
        let second = try #require( field.stars.first { Swift.abs( $0.x - 110.8 ) < 1 && Swift.abs( $0.y - 40.2 ) < 1 } )

        #expect( Swift.abs( first.x - 60.3   ) < 0.15 )
        #expect( Swift.abs( first.y - 90.7   ) < 0.15 )
        #expect( Swift.abs( second.x - 110.8 ) < 0.15 )
        #expect( Swift.abs( second.y - 40.2  ) < 0.15 )
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
        #expect( Swift.abs( star.x - 60                           ) < 0.3 )
        #expect( Swift.abs( star.y - 60                           ) < 0.3 )
        #expect( Swift.abs( star.fwhm - Self.fwhmPerSigma * sigma ) < 0.15 * Self.fwhmPerSigma * sigma )
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

        #expect( Swift.abs( estimated - Self.fwhmPerSigma * sigma ) < 0.25 * Self.fwhmPerSigma * sigma )
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

    /// A dense field of small stars carrying a few bright, bloomed ones is detected
    /// at the small population's scale, not at the bloomed stars' scale.
    ///
    /// This is the shape of a real cluster frame: a long exposure grows the handful
    /// of brightest stars into broad, saturated blooms several times the size of the
    /// field's typical star. A scale that reads the bloom width instead of the
    /// population's makes the matched filter and its size-band purity cut reject the
    /// whole real population.
    ///
    /// This is **characterization, not a regression guard** for the dense-field
    /// collapse: it passes against the previous scale estimate too, which took the
    /// median of a bounded sample of the brightest peaks and so needed a majority of
    /// that sample to be bloomed before it ran away. Sizing a fixture to that bound
    /// would be encoding a removed implementation detail. The real-frame guard is
    /// `RealFrameValidationTests.detectsWellFormedStarsInTheM35Cluster`.
    @Test
    func detectsThePopulationOfADenseFieldWithBloomedBrightStars() throws
    {
        let sigma   = 1.2
        let planted: [ ( x: Double, y: Double, peak: Double ) ] = ( 0 ..< 34 ).flatMap
        {
            row -> [ ( x: Double, y: Double, peak: Double ) ] in

            ( 0 ..< 34 ).map
            {
                column -> ( x: Double, y: Double, peak: Double ) in

                let x = 10.0 + ( Double( column ) * 8.0 )
                let y = 10.0 + ( Double( row ) * 8.0 )

                return ( x: x, y: y, peak: ( ( row + column ) % 4 == 0 ) ? 9000 : 3000 )
            }
        }

        // The bloomed giants: far brighter than the field, and saturating, so they
        // dominate any "measure the brightest peaks" estimate.
        let bloomed: [ ( x: Double, y: Double ) ] =
            [
                ( 60, 60 ), ( 150, 60 ), ( 240, 60 ),
                ( 60, 150 ), ( 240, 150 ),
                ( 60, 240 ), ( 150, 240 ), ( 240, 240 ),
            ]

        let small = planted.reduce( SyntheticStarField( width: 300, height: 300, background: 200 ) )
        {
            $0.addingStar( cx: $1.x, cy: $1.y, peak: $1.peak, sigma: sigma )
        }

        let image = try bloomed.reduce( small ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 150_000, sigma: 6 ) }
            .saturating( at: 60000 )
            .addingNoise( seed: 22, amplitude: 8 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        // The great majority of the planted field, not the few dozen an inflated
        // scale leaves behind.
        #expect( field.count >= ( planted.count * 8 ) / 10 )

        let measured = try #require( field.medianFWHM )

        #expect( Swift.abs( measured - ( Self.fwhmPerSigma * sigma ) ) < 0.3 * Self.fwhmPerSigma * sigma )
    }

    /// Builds a field of identical broad, defocused stars on a 5×5 lattice.
    ///
    /// - Parameter sigma: The stars' Gaussian sigma, in pixels.
    /// - Returns: The planted centres and the rendered image.
    private func defocusedField( sigma: Double ) throws -> ( planted: [ ( x: Double, y: Double ) ], image: PixelBuffer )
    {
        let planted: [ ( x: Double, y: Double ) ] = ( 0 ..< 5 ).flatMap
        {
            row -> [ ( x: Double, y: Double ) ] in

            ( 0 ..< 5 ).map
            {
                column -> ( x: Double, y: Double ) in

                let x = 80.0 + ( Double( column ) * 110.0 )
                let y = 80.0 + ( Double( row ) * 110.0 )

                return ( x: x, y: y )
            }
        }

        let base  = SyntheticStarField( width: 640, height: 640, background: 300 )
        let image = try planted.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 20000, sigma: sigma ) }
            .addingNoise( seed: 31, amplitude: 13 )
            .image()

        return ( planted: planted, image: image )
    }

    /// How many of a planted field's stars a detection recovered.
    ///
    /// - Parameters:
    ///   - planted: The planted centres.
    ///   - field:   The detected field.
    ///   - within:  How far, in pixels, a detection may sit from a planted centre.
    /// - Returns: The number of planted stars matched.
    private func recovered( _ planted: [ ( x: Double, y: Double ) ], in field: StarField, within: Double ) -> Int
    {
        planted.filter
        {
            planted in

            field.stars.contains { Foundation.hypot( $0.x - planted.x, $0.y - planted.y ) <= within }
        }
        .count
    }

    /// A crowded field of moderately-sized stars is detected at its own scale — the
    /// widening that rescues a broad star must not fire here.
    ///
    /// The scale bootstrap sizes each bright star over a window. When a star is
    /// broader than that window its footprint is cut off and sizes small, so the
    /// window has to widen. But widening on a *crowded* field does the opposite of a
    /// correction: the wider window reaches into the neighbours, merges them, and
    /// drives the scale up, at which point the size-band purity cut rejects the whole
    /// real population. These stars are ~5.9 px on a ~13 px lattice — comfortably
    /// inside the window, so nothing is clipped and nothing needs widening.
    @Test
    func detectsACrowdedFieldOfModerateStars() throws
    {
        let sigma   = 2.5
        let planted: [ ( x: Double, y: Double ) ] = ( 0 ..< 20 ).flatMap
        {
            row -> [ ( x: Double, y: Double ) ] in

            ( 0 ..< 20 ).map
            {
                column -> ( x: Double, y: Double ) in

                let x = 176.0 + ( Double( column ) * 13.0 )
                let y = 176.0 + ( Double( row ) * 13.0 )

                return ( x: x, y: y )
            }
        }

        let base  = SyntheticStarField( width: 600, height: 600, background: 1000 )
        let image = try planted.reduce( base ) { $0.addingStar( cx: $1.x, cy: $1.y, peak: 30000, sigma: sigma ) }
            .addingNoise( seed: 41, amplitude: 10 )
            .image()

        let field = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( field.count >= ( planted.count * 9 ) / 10 )

        let measured = try #require( field.medianFWHM )

        #expect( Swift.abs( measured - ( Self.fwhmPerSigma * sigma ) ) < 0.3 * Self.fwhmPerSigma * sigma )
    }

    /// Broad, defocused stars are detected — the case where a source is comparable
    /// to the background map's own tile.
    ///
    /// The map's per-tile median and MAD only describe *sky* while the sources
    /// occupy a minority of a tile. A defocused frame — exactly what an autofocus
    /// run produces, and this library reports HFR for focusing — breaks that: a star
    /// tens of pixels across can fill a whole tile, so the tile's statistics measure
    /// the star instead. The inflated tile noise then drives every threshold above
    /// the star itself, no peak can be sized, the scale estimate collapses to its
    /// default, and the size band throws the whole frame away. Worse, whether a
    /// given star survives depends on where it happens to fall on the fixed mesh, so
    /// results would not even be repeatable across dithered subs.
    @Test
    func detectsBroadDefocusedStars() throws
    {
        let ( planted, image ) = try self.defocusedField( sigma: 14 )
        let field              = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( self.recovered( planted, in: field, within: 4 ) == planted.count )
    }

    /// Stars far broader still — deep enough into defocus to swamp the *default*
    /// background tile — are detected, and measured at something like their true
    /// size rather than as a scatter of fragments.
    ///
    /// The mesh's rescue of a source that fills its own tile has a ceiling, and past
    /// it the failure is silent rather than loud: the detector reports stars, but
    /// each defocused disc breaks into small pieces whose half-flux radius is a
    /// fraction of the truth. A focus routine reading that HFR would be steered by a
    /// number with no relation to the focus position, which is worse than no reading
    /// at all. The tile therefore has to grow with the stars it finds.
    @Test
    func detectsAndSizesDeeplyDefocusedStars() throws
    {
        let sigma              = 20.0
        let ( planted, image ) = try self.defocusedField( sigma: sigma )
        let field              = try MatchedFilterStarDetector().detectStars( in: image )

        #expect( self.recovered( planted, in: field, within: 6 ) >= planted.count - 1 )

        // A Gaussian's half-flux radius is σ√(π/2); fragments read a small fraction
        // of it, so this bound separates a real measurement from a shattered one.
        let expectedHFR = sigma * ( Double.pi / 2 ).squareRoot()
        let medianHFR   = try #require( field.medianHFR )

        #expect( medianHFR > 0.6 * expectedHFR )
        #expect( medianHFR < 1.6 * expectedHFR )
    }

    /// The FWHM bootstrap sizes bright, window-filling stars correctly, from a sky
    /// annulus that clears the star.
    ///
    /// Two things have to hold. The background must be read from the window's outer
    /// annulus rather than the whole window (IMP-12): a bright star's core fills the
    /// window, so a whole-window median reads the star itself as "background", lands
    /// the footprint level inside the core, and sizes the star well below its true
    /// scale. And the window must be wide enough for that annulus to sit *outside*
    /// the star: a star broader than the first-pass window has its footprint clipped
    /// by that window, and the second pass re-measures it over a window scaled to
    /// the first estimate.
    @Test
    func bootstrapSizesBrightWindowFillingStarsFromTheSkyAnnulus() throws
    {
        // Bright stars whose above-noise skirt reaches well past the first-pass
        // radius-10 bootstrap window, so a whole-window background read is inflated
        // by the star's own flux and a single fixed-window pass clips the footprint.
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

        // The bootstrap recovers the planted 14.1 px scale (measured: 13.6, −3.5 %).
        // The band is set at 15 % to leave room for the crowding in this fixture,
        // but the two failure modes it has to catch land far outside it anyway: a
        // whole-window background read sizes these ~7.6 px, and a single fixed
        // radius-10 pass — whose annulus falls inside a star this broad — sizes them
        // ~8.6 px. There is no downstream correction left to lean on, so the
        // bootstrap must be right here, not merely a sound seed.
        #expect( Swift.abs( estimated - ( Self.fwhmPerSigma * 6 ) ) < 0.15 * Self.fwhmPerSigma * 6 )
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
            field.stars.first { Swift.abs( $0.x - star.x ) < 3 && Swift.abs( $0.y - star.y ) < 3 }
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
