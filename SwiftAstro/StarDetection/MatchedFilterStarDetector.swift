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
import SwiftPixel

/// A DAOFIND-style star detector: a zero-sum Gaussian matched filter for
/// detection, purity cuts to reject non-stars, and a per-star elliptical Gaussian
/// fit for measurement.
///
/// The matched filter (``SwiftPixel/Convolution/zeroSumResponse(of:kernel:)``)
/// responds to point sources at the expected scale while vanishing on smooth
/// backgrounds — flat sky, gradients and extended nebulosity — so detection does
/// not latch onto nebulosity or a near-flat noise floor the way a global
/// threshold does. Candidate peaks then pass **sharpness** (rejecting single hot
/// pixels and broad blobs) and **roundness** (rejecting elongated artifacts)
/// cuts, and survivors are measured from their **connected footprint** (the patch
/// of pixels above the local noise floor that touches the peak), refined with a 2D
/// Gaussian fit (``SwiftPixel/GaussianFit``) seeded from that footprint's moments
/// (``StarMoments``). The fit is used for its sub-pixel accuracy when it converges,
/// but it is not required: on faint, low-signal-to-noise stars — common on real
/// sub-exposures — it often fails to converge, so the robust footprint-moment
/// measurement stands in for it rather than the star being dropped.
///
/// The matched-filter scale is auto-estimated from the image's brightest stars
/// unless a ``Configuration/expectedFWHM`` override is set. The detector optimizes
/// for purity — it would rather miss a faint star than report a false one — with
/// the 5σ matched-filter threshold, not the fit, as the gate against false
/// positives.
public struct MatchedFilterStarDetector: StarDetecting
{
    /// Tunable detection parameters.
    public struct Configuration: Sendable
    {
        /// The expected stellar FWHM, in pixels, setting the matched-filter scale.
        /// When `nil`, it is auto-estimated per image from the brightest stars.
        public var expectedFWHM: Double?

        /// Whether to run the augmenting bright / large-star pass after matched
        /// filtering.
        ///
        /// The zero-sum matched filter is blind to a bright star's saturated,
        /// flat-topped core (a flat region convolves to zero), and its size band
        /// (``maxFWHMFactor``) rejects stars far larger than the auto-estimated
        /// scale — so on a frame dominated by small stars, the large, bright ones
        /// a human notices first are dropped. This pass recovers them from the raw
        /// image and merges any that the matched filter did not already find,
        /// leaving the faint-star detections untouched.
        public var detectsBrightStars: Bool

        /// How many noise sigmas above the background a pixel must exceed to belong
        /// to a bright blob in the bright-star pass. Higher isolates only the very
        /// brightest sources; lower lets the pass reach dimmer, larger stars — at
        /// the cost of admitting more nebulosity and noise.
        public var brightStarThresholdSigma: Double

        /// The smallest bright-blob radius, as a multiple of the matched-filter
        /// FWHM, the bright-star pass keeps. Below it a blob is no larger than an
        /// ordinary star the matched filter already handles. Lower it to recover
        /// smaller "large" stars; raise it to admit only clearly oversized ones.
        public var brightStarMinRadiusFactor: Double

        /// The largest bright-blob radius, as a multiple of the matched-filter
        /// FWHM, the bright-star pass keeps. Above it a blob is too large to be a
        /// star and is rejected as nebulosity. Raise it to allow bigger, bloomed
        /// stars; lower it to reject extended structure more aggressively.
        public var brightStarMaxRadiusFactor: Double

        /// How many noise sigmas a bright blob's peak must rise above its *local*
        /// background (the median around it) to be kept.
        ///
        /// A real star — even a saturated one — stands sharply above its
        /// surroundings; a knot of bright nebulosity does not, because the
        /// nebulosity around it is nearly as bright as the knot.
        ///
        /// This is **disabled by default (`0`)**: in a rich cluster embedded in
        /// nebulosity — the Orion core, say — the real stars *also* sit on bright
        /// nebulosity, so requiring local contrast discards them along with any
        /// knots. Enable it (a few sigma) only when a target genuinely produces
        /// nebulosity false positives and few embedded stars; higher rejects
        /// nebulosity harder.
        public var brightStarLocalContrastSigma: Double

        /// The largest number of distinct stellar peaks a bright blob may contain and
        /// still be reported as a single star. A genuine star — however large or
        /// bright — is a *single* peak; a blob holding several peaks is a blended pair
        /// or a crowded cluster core (a globular, say), measured as one broad source
        /// with inflated metrics, so it is dropped rather than reported as one giant
        /// spurious "star". Peaks are counted above the local noise floor within the
        /// measurement aperture, so this discriminates on structure, not size — a
        /// genuinely large single star is kept regardless of how broad it is.
        public var brightStarMaxPeaks: Int

        /// How many noise sigmas above the background a convolved peak must reach
        /// to count as a candidate.
        public var thresholdSigma: Double

        /// The lower sharpness bound: candidates below it are too concentrated to
        /// be a star (single hot pixels, cosmic rays), with all their flux in the
        /// central pixel and none in the neighbours.
        public var sharpnessLow: Double

        /// The maximum eccentricity a candidate's fitted profile may have; more
        /// elongated ones (trails, artifacts) are rejected.
        public var roundnessLimit: Double

        /// The smallest fitted FWHM, as a fraction of the matched-filter FWHM, a
        /// candidate may have. Rejects sub-PSF spikes that survived the sharpness
        /// cut.
        public var minFWHMFactor: Double

        /// The largest fitted FWHM, as a multiple of the matched-filter FWHM, a
        /// candidate may have. Rejects broad blobs and nebulosity that are far
        /// larger than a star.
        public var maxFWHMFactor: Double

        /// The minimum separation between detections, in pixels; among closer
        /// peaks the brighter wins. When `nil`, the estimated FWHM is used.
        public var minSeparation: Double?

        /// Candidates whose centre comes within this many pixels of the image edge
        /// are rejected, since their profiles are clipped.
        public var edgeMargin: Int

        /// When set, candidates whose peak sample is at or above this level are
        /// dropped as saturated / bloomed. This applies to **both** detection
        /// paths — the matched-filter pass and the bright-star pass — so setting it
        /// reliably excludes saturated stars regardless of ``detectsBrightStars``.
        public var saturationLevel: Double?

        /// Creates a configuration with the default purity-oriented parameters.
        public init(
            expectedFWHM:                 Double? = nil,
            detectsBrightStars:           Bool    = true,
            brightStarThresholdSigma:     Double  = 6,
            brightStarMinRadiusFactor:    Double  = 1.5,
            brightStarMaxRadiusFactor:    Double  = 10.0,
            brightStarLocalContrastSigma: Double  = 0,
            brightStarMaxPeaks:           Int     = 2,
            thresholdSigma:               Double  = 5,
            sharpnessLow:                 Double  = 0.2,
            roundnessLimit:               Double  = 0.6,
            minFWHMFactor:                Double  = 0.5,
            maxFWHMFactor:                Double  = 2.0,
            minSeparation:                Double? = nil,
            edgeMargin:                   Int     = 4,
            saturationLevel:              Double? = nil
        )
        {
            self.expectedFWHM                 = expectedFWHM
            self.detectsBrightStars           = detectsBrightStars
            self.brightStarThresholdSigma     = brightStarThresholdSigma
            self.brightStarMinRadiusFactor    = brightStarMinRadiusFactor
            self.brightStarMaxRadiusFactor    = brightStarMaxRadiusFactor
            self.brightStarLocalContrastSigma = brightStarLocalContrastSigma
            self.brightStarMaxPeaks           = brightStarMaxPeaks
            self.thresholdSigma               = thresholdSigma
            self.sharpnessLow                 = sharpnessLow
            self.roundnessLimit               = roundnessLimit
            self.minFWHMFactor                = minFWHMFactor
            self.maxFWHMFactor                = maxFWHMFactor
            self.minSeparation                = minSeparation
            self.edgeMargin                   = edgeMargin
            self.saturationLevel              = saturationLevel
        }
    }

    /// For a 2D Gaussian, FWHM = 2√(2 ln 2)·σ.
    private static let fwhmPerSigma = 2 * ( 2 * Foundation.log( 2.0 ) ).squareRoot()

    /// The FWHM used when auto-estimation finds no stars to size.
    private static let defaultFWHM = 3.0

    /// How many noise sigmas above the background the FWHM bootstrap thresholds
    /// at, to isolate only the brightest, unambiguous stars.
    private static let bootstrapSigma = 10.0

    /// The half-size, in pixels, of the window the FWHM bootstrap measures each
    /// bright star over.
    private static let bootstrapWindowRadius = 10

    /// The number of noise multiples above the local background a pixel must exceed
    /// to belong to a star's connected footprint.
    private static let footprintSigma = 3.0

    /// The smallest connected footprint, in pixels, a candidate may have to be
    /// sized or measured — rejecting single hot pixels and sub-resolution spikes.
    private static let minFootprintSamples = 5

    /// The eight neighbour offsets defining 8-connectivity.
    static let neighborOffsets = [ ( -1, -1 ), ( 0, -1 ), ( 1, -1 ), ( -1, 0 ), ( 1, 0 ), ( -1, 1 ), ( 0, 1 ), ( 1, 1 ) ]

    /// The detection parameters.
    public let configuration: Configuration

    /// Creates a detector.
    ///
    /// - Parameter configuration: The detection parameters.
    public init( configuration: Configuration = Configuration() )
    {
        self.configuration = configuration
    }

    /// Detects stars by matched filtering, purity cuts and per-star Gaussian
    /// fitting.
    ///
    /// - Parameter image: The single-channel, linear image to analyze.
    /// - Returns: The detected stars and their aggregate metrics; an empty field
    ///   for a degenerate image or one with no measurable noise.
    /// - Throws: ``SwiftAstro/Error`` if the image is not single-channel.
    public func detectStars( in image: PixelBuffer ) throws -> StarField
    {
        guard image.channels == 1
        else
        {
            throw Error( message: "MatchedFilterStarDetector requires a single-channel image, got \( image.channels ) channels" )
        }

        guard image.width > 0, image.height > 0
        else
        {
            return StarField( stars: [] )
        }

        let fwhm     = self.configuration.expectedFWHM.map { Swift.max( $0, 1 ) } ?? Self.refinedFWHM( in: image, configuration: self.configuration )
        let sigma    = fwhm / Self.fwhmPerSigma
        let kernel   = GaussianKernel( sigma: sigma )
        let response = Convolution.zeroSumResponse( of: image, kernel: kernel )

        let center = PixelUtilities.median( response ) ?? 0
        let sigmaC = ( PixelUtilities.medianAbsoluteDeviation( response, around: center ) ?? 0 ) * 1.4826

        guard sigmaC > 0
        else
        {
            return StarField( stars: [] )
        }

        let threshold     = center + ( self.configuration.thresholdSigma * sigmaC )
        let minSeparation = self.configuration.minSeparation ?? fwhm
        let peaks         = Self.localMaxima( in: response, width: image.width, height: image.height, threshold: threshold )
        let separated     = self.separate( peaks, minSeparation: minSeparation, width: image.width )

        let stars = separated.compactMap
        {
            self.measure( peak: $0.index, in: image, fwhm: fwhm )
        }

        guard self.configuration.detectsBrightStars
        else
        {
            return StarField( stars: stars )
        }

        let bright = self.brightStars( in: image, fwhm: fwhm, minSeparation: minSeparation, excluding: stars )

        return StarField( stars: stars + bright )
    }

    // MARK: - FWHM auto-estimation

    /// The largest number of candidate peaks the FWHM refinement measures — a bound
    /// so a rich, many-megapixel frame costs the same as a modest one.
    private static let refinementSampleSize = 120

    /// The smallest ``sampleWidth`` window radius, in pixels, independent of the
    /// current FWHM estimate. It keeps the sky annulus clear of a large or
    /// saturated star's core even when the bootstrap scale is badly underestimated,
    /// so the refinement can climb out of a too-small starting point instead of
    /// stalling because every sample's window falls inside its own star.
    private static let sampleWidthMinRadius = 8

    /// Refines the matched-filter scale by grounding it in the widths of the stars
    /// the frame actually contains, rather than the brightest-peak bootstrap alone.
    ///
    /// The bootstrap (``estimateFWHM(in:)``) sizes a handful of bright peaks, and on
    /// awkward frames — a dense, drizzled master of tiny stars; a nebula sub whose
    /// bright peaks are bloated — it can miss the true scale several-fold, which then
    /// makes the size-band purity cut reject the whole real star population.
    ///
    /// This finds candidate star peaks once (a single matched-filter pass at the
    /// bootstrap scale, which is sensitive enough to surface them), then takes a
    /// bounded sample and re-measures their median width over a window that grows
    /// with the estimate, iterating until it settles. The window converging on the
    /// true scale is what lets a badly-off bootstrap recover, and sampling keeps the
    /// cost flat — no repeated full detections.
    ///
    /// - Parameters:
    ///   - image:         The single-channel image.
    ///   - configuration: The detector's configuration (for the detection threshold).
    /// - Returns: The refined FWHM, in pixels, at least `1`.
    private static func refinedFWHM( in image: PixelBuffer, configuration: Configuration ) -> Double
    {
        var fwhm = Swift.max( Self.estimateFWHM( in: image ) ?? Self.defaultFWHM, 1 )

        let background = PixelUtilities.median( image.pixels ) ?? 0
        let noise      = ( PixelUtilities.medianAbsoluteDeviation( image.pixels, around: background ) ?? 0 ) * 1.4826

        guard noise > 0
        else
        {
            return fwhm
        }

        // Surface candidate star peaks directly from the raw image — the brightest
        // local maxima — rather than a second matched-filter convolution, so the
        // refinement costs a peak scan, not another full pass. The brightest peaks
        // are unambiguous stars, exactly the sample the width measurement wants.
        let threshold = background + ( Self.bootstrapSigma * noise )
        let peaks     = Self.localMaxima( in: image.pixels, width: image.width, height: image.height, threshold: threshold )
        let sample    = peaks.sorted { $0.value > $1.value }.prefix( Self.refinementSampleSize ).map { $0.index }

        guard sample.isEmpty == false
        else
        {
            return fwhm
        }

        // Re-measure the sample's median width, letting the measurement window grow
        // with the estimate until it settles on the true scale.
        for _ in 0 ..< 3
        {
            let widths = sample.compactMap { Self.sampleWidth( around: $0, in: image, fwhm: fwhm, background: background, noise: noise ) }

            guard let median = PixelUtilities.median( widths ), median.isFinite, median > 0
            else
            {
                break
            }

            let next      = Swift.min( Swift.max( median, 1 ), 40 )
            let converged = abs( next - fwhm ) <= ( 0.1 * fwhm )

            fwhm = next

            if converged
            {
                break
            }
        }

        return fwhm
    }

    /// Measures one candidate peak's FWHM the same way ``measure(peak:in:fwhm:)``
    /// does — a local-background connected footprint, a Gaussian fit for its width
    /// with the footprint moments as fallback — but without the purity cuts, so a
    /// sample can be sized to refine the scale.
    ///
    /// - Returns: The peak's FWHM, or `nil` when it cannot be sized.
    private static func sampleWidth( around index: Int, in image: PixelBuffer, fwhm: Double, background: Double, noise: Double ) -> Double?
    {
        // Size the window generously — with a floor independent of the possibly
        // underestimated `fwhm` — and read the sky from its outer annulus rather
        // than its full extent. The brightest sample peaks are often the large,
        // saturated stars whose flat core fills a tight window, so a whole-window
        // median would read the star itself as "background": the footprint level
        // would land at the core, the footprint would collapse below the minimum,
        // and every sample would fail to size — stalling the refinement at the
        // bootstrap scale. The annulus sits beyond the core, on true sky.
        let radius     = Swift.max( Self.sampleWidthMinRadius, Int( ( 2.0 * fwhm ).rounded() ) )
        let samples    = Self.window( around: index, radius: radius, in: image )
        let peakX      = Double( index % image.width )
        let peakY      = Double( index / image.width )
        let skyInner   = Double( radius ) * 0.65
        let annulus    = samples.filter { Foundation.hypot( $0.x - peakX, $0.y - peakY ) >= skyInner }.map { $0.value }
        let localBg    = PixelUtilities.median( annulus ) ?? ( PixelUtilities.median( samples.map { $0.value } ) ?? background )
        let localNoise = ( PixelUtilities.medianAbsoluteDeviation( annulus, around: localBg ) ?? 0 ) * 1.4826
        let level      = localBg + ( Self.footprintSigma * Swift.max( localNoise, noise ) )
        let footprint  = Self.connectedFootprint( around: index, radius: radius, level: level, in: image )

        guard footprint.count >= Self.minFootprintSamples, let moments = StarMoments( samples: footprint, background: localBg )
        else
        {
            return nil
        }

        let seed = GaussianFit.Parameters( moments: moments, amplitude: image.pixels[ index ] - localBg, background: localBg )

        // Bound the Gaussian fit to the star's actual extent (IMP-5). The window is
        // sized generously from `fwhm` for the annulus and footprint search, but when
        // the bootstrap over-shoots — the very case this refinement exists to correct
        // — that window can reach ~160×160, and the per-sample fit, run for every
        // sampled peak on every iteration, then dominates the cost. The connected
        // footprint is the star's true extent, so fitting over it plus a background
        // margin fully encloses the star: the measured width is unchanged to within
        // noise while the wasted work on distant sky is cut. The bound only ever
        // shrinks the fit set (a `filter` of the window), never grows it; for a small
        // or normally-sized star it already exceeds the window, so the fit set is the
        // full window as before, and it engages for an inflated bootstrap or a
        // genuinely large star, where the enclosed core still pins the width. Only the
        // internal scale refinement reads this width; the reported `measure` is
        // untouched.
        let footprintReach = footprint.reduce( 0.0 ) { Swift.max( $0, Foundation.hypot( $1.x - peakX, $1.y - peakY ) ) }
        let fitRadius      = footprintReach + Double( Self.sampleWidthMinRadius )
        let fitSamples     = fitRadius < Double( radius ) ? samples.filter { Foundation.hypot( $0.x - peakX, $0.y - peakY ) <= fitRadius } : samples

        let width: Double

        if let fit = GaussianFit.fit( samples: fitSamples, initialGuess: seed )
        {
            let sigmaMajor = Swift.max( abs( fit.sigmaX ), abs( fit.sigmaY ) )
            let sigmaMinor = Swift.min( abs( fit.sigmaX ), abs( fit.sigmaY ) )

            width = Self.fwhmPerSigma * ( sigmaMajor * sigmaMinor ).squareRoot()
        }
        else
        {
            width = moments.fwhm
        }

        return ( width.isFinite && width > 0 ) ? width : nil
    }

    /// Estimates the stellar FWHM from an image's brightest stars: it finds the
    /// brightest local maxima, sizes each one by the geometric-mean width of its
    /// connected footprint against its own local background, and takes the median.
    ///
    /// The size is read from the footprint's second moments, not from the reported
    /// half-flux radius: that HFR is now a flux-weighted mean, which is
    /// crowding-sensitive, whereas the footprint (the 8-connected patch above the
    /// local noise floor) is compact and yields a stable, self-contained FWHM for
    /// the detection scale.
    ///
    /// - Parameter image: The single-channel image to size.
    /// - Returns: The median FWHM, in pixels, or `nil` when no bright star can be
    ///   sized.
    static func estimateFWHM( in image: PixelBuffer ) -> Double?
    {
        guard image.channels == 1, image.width > 0, image.height > 0
        else
        {
            return nil
        }

        let background = PixelUtilities.median( image.pixels ) ?? 0
        let noise      = ( PixelUtilities.medianAbsoluteDeviation( image.pixels, around: background ) ?? 0 ) * 1.4826

        guard noise > 0
        else
        {
            return nil
        }

        let highThreshold = background + ( Self.bootstrapSigma * noise )
        let maxima        = Self.localMaxima( in: image.pixels, width: image.width, height: image.height, threshold: highThreshold )

        // Size each bright star over its connected footprint, but prefer footprints
        // that have *not* merged a neighbouring bright star. A blob of several merged
        // stars sizes several times too large; on a dense field of small stars (a
        // drizzled master) that inflated scale then makes the size-band cut reject
        // the whole real population. A footprint containing only its own peak is a
        // single, isolated star that sizes the point spread correctly.
        let peaks    = Set( maxima.map { $0.index } )
        let isolated = maxima.compactMap { Self.footprintWidth( around: $0.index, in: image, background: background, noise: noise, isolatedAmong: peaks ) }

        guard isolated.isEmpty
        else
        {
            return PixelUtilities.median( isolated )
        }

        // Every bright star is crowded (no isolated footprint): size over the merged
        // footprints anyway, rather than reporting no scale at all.
        let merged = maxima.compactMap { Self.footprintWidth( around: $0.index, in: image, background: background, noise: noise, isolatedAmong: nil ) }

        return PixelUtilities.median( merged )
    }

    /// Sizes a bright star by the geometric-mean width (FWHM) of its connected
    /// footprint — the 8-connected patch above the local noise floor containing the
    /// peak.
    ///
    /// When `isolatedAmong` is given, the star is skipped (returns `nil`) if its
    /// footprint also contains another of those bright peaks: the footprint has
    /// merged neighbouring stars and its radius no longer describes a single star.
    ///
    /// - Parameters:
    ///   - index:         The star's peak pixel index.
    ///   - image:         The single-channel image.
    ///   - background:    The global background, the final fallback when neither the
    ///                    sky annulus nor the whole window yields a median.
    ///   - noise:         The robust background noise.
    ///   - isolatedAmong: The set of bright-peak indices to test the footprint
    ///                    against, or `nil` to skip the merge test.
    /// - Returns: The star's FWHM (the footprint's geometric-mean width), or `nil`
    ///   when it cannot be sized or its footprint merged a neighbour.
    private static func footprintWidth( around index: Int, in image: PixelBuffer, background: Double, noise: Double, isolatedAmong: Set< Int >? ) -> Double?
    {
        // Read the sky from the window's outer annulus, not its whole extent
        // (IMP-12), giving the bootstrap seed the annulus-sky robustness the
        // refinement's `sampleWidth` already has. A bright star's core fills much of
        // this fixed-radius window, so a whole-window median reads the star itself as
        // "background" — landing the footprint level inside the core, so the
        // footprint shrinks toward the core and the star sizes small. The annulus
        // sits beyond the core, on true sky. Only the *background* is read from the
        // annulus; the level keeps the global `noise` (unlike `sampleWidth`, whose
        // window grows with the estimate, this fixed radius-10 annulus straddles a
        // moderate star's skirt, so its local MAD would be skirt-driven, not sky).
        let radius          = Self.bootstrapWindowRadius
        let window          = Self.window( around: index, radius: radius, in: image )
        let peakX           = Double( index % image.width )
        let peakY           = Double( index / image.width )
        let skyInner        = Double( radius ) * 0.65
        let annulus         = window.filter { Foundation.hypot( $0.x - peakX, $0.y - peakY ) >= skyInner }.map { $0.value }
        let localBackground = PixelUtilities.median( annulus ) ?? ( PixelUtilities.median( window.map { $0.value } ) ?? background )
        let level           = localBackground + ( Self.footprintSigma * noise )
        let body            = Self.connectedFootprint( around: index, radius: radius, level: level, in: image )

        guard body.count >= Self.minFootprintSamples
        else
        {
            return nil
        }

        if let isolatedAmong
        {
            // Skip only genuinely blended footprints — three or more merged bright
            // peaks. A footprint with its own peak plus at most one neighbour is a
            // single star or a close pair whose radius still describes the scale;
            // skipping those too would under-size a merely crowded cluster.
            let footprint = Set( body.map { ( Int( $0.y ) * image.width ) + Int( $0.x ) } )

            guard isolatedAmong.intersection( footprint ).count <= 2
            else
            {
                return nil
            }
        }

        guard let moments = StarMoments( samples: body, background: localBackground ), moments.fwhm.isFinite, moments.fwhm > 0.6
        else
        {
            return nil
        }

        return moments.fwhm
    }

    // MARK: - Peak detection

    /// Finds the strict 8-neighbourhood local maxima of a sample grid that exceed
    /// a threshold.
    private static func localMaxima( in values: [ Double ], width: Int, height: Int, threshold: Double ) -> [ ( index: Int, value: Double ) ]
    {
        values.indices.compactMap
        {
            index -> ( index: Int, value: Double )? in

            let value = values[ index ]

            guard value > threshold
            else
            {
                return nil
            }

            let x = index % width
            let y = index / width

            let isPeak = Self.neighborOffsets.allSatisfy
            {
                let nx = x + $0.0
                let ny = y + $0.1

                guard nx >= 0, nx < width, ny >= 0, ny < height
                else
                {
                    return true
                }

                return value > values[ ( ny * width ) + nx ]
            }

            return isPeak ? ( index: index, value: value ) : nil
        }
    }

    /// A spatial-hash cell, used to deduplicate peaks by minimum separation.
    private struct Cell: Hashable
    {
        /// The cell column.
        let x: Int

        /// The cell row.
        let y: Int
    }

    /// Enforces the minimum separation between peaks, keeping the brighter of any
    /// two that fall within it. A spatial hash keeps the check near-linear.
    private func separate( _ peaks: [ ( index: Int, value: Double ) ], minSeparation: Double, width: Int ) -> [ ( index: Int, value: Double ) ]
    {
        let cellSize        = Swift.max( minSeparation, 1 )
        let minSepSquared   = minSeparation * minSeparation
        var grid            = [ Cell: [ ( x: Double, y: Double ) ] ]()
        var kept            = [ ( index: Int, value: Double ) ]()

        peaks.sorted { $0.value > $1.value }.forEach
        {
            peak in

            let x  = Double( peak.index % width )
            let y  = Double( peak.index / width )
            let cx = Int( x / cellSize )
            let cy = Int( y / cellSize )

            let neighborhood = ( -1 ... 1 ).flatMap { gx in ( -1 ... 1 ).map { gy in Cell( x: cx + gx, y: cy + gy ) } }

            let tooClose = neighborhood.contains
            {
                ( grid[ $0 ] ?? [] ).contains { ( ( $0.x - x ) * ( $0.x - x ) ) + ( ( $0.y - y ) * ( $0.y - y ) ) < minSepSquared }
            }

            guard tooClose == false
            else
            {
                return
            }

            kept.append( peak )
            grid[ Cell( x: cx, y: cy ), default: [] ].append( ( x: x, y: y ) )
        }

        return kept
    }

    // MARK: - Measurement

    /// Measures a candidate peak, applying the purity cuts.
    ///
    /// The background is estimated **locally**, as the median of the measurement
    /// window: on real frames the sky varies across the image (gradients,
    /// vignetting), and a global background would let the window's pedestal
    /// inflate the moments, fit and half-flux radius.
    ///
    /// The shape is measured from the star's **connected footprint** (the pixels
    /// above the local noise floor that touch the peak), and refined with a
    /// Gaussian fit seeded from it. The fit is used when it converges to a physical
    /// Gaussian — for its sub-pixel accuracy — but it is *not* required: on faint,
    /// low-signal-to-noise stars, common on real sub-exposures, the fit frequently
    /// fails to converge, and dropping every such star (as gating on the fit did)
    /// collapses the detected count to almost nothing. When the fit fails, the
    /// robust footprint-moment measurement stands on its own.
    ///
    /// - Returns: The measured star, or `nil` if the candidate is clipped by the
    ///   edge, saturated, has no usable footprint, or fails the sharpness,
    ///   roundness or size cut.
    private func measure( peak index: Int, in image: PixelBuffer, fwhm: Double ) -> Star?
    {
        let width  = image.width
        let height = image.height
        let px     = index % width
        let py     = index / width
        let margin = self.configuration.edgeMargin

        guard px >= margin, py >= margin, px < width - margin, py < height - margin
        else
        {
            return nil
        }

        if let saturation = self.configuration.saturationLevel, image.pixels[ index ] >= saturation
        {
            return nil
        }

        let radius     = Swift.max( 3, Int( ( 1.5 * fwhm ).rounded() ) )
        let samples    = Self.window( around: index, radius: radius, in: image )
        let background = PixelUtilities.median( samples.map { $0.value } ) ?? 0
        let sharpness  = Self.sharpness( at: index, in: image, background: background )

        // Cheap pre-fit cut: reject single hot pixels / cosmic rays whose flux is
        // not spread into the neighbours at all.
        guard sharpness >= self.configuration.sharpnessLow
        else
        {
            return nil
        }

        // Measure the star's shape from its connected footprint. Unlike the second
        // moments of the whole window — which the surrounding background noise
        // inflates until they no longer describe the star — the footprint moments
        // are compact and physical, so they both seed the fit well and provide a
        // reliable measurement when the fit does not converge.
        let noise     = ( PixelUtilities.medianAbsoluteDeviation( samples.map { $0.value }, around: background ) ?? 0 ) * 1.4826
        let level     = background + ( Self.footprintSigma * noise )
        let footprint = Self.connectedFootprint( around: index, radius: radius, level: level, in: image )

        guard footprint.count >= Self.minFootprintSamples, let moments = StarMoments( samples: footprint, background: background )
        else
        {
            return nil
        }

        let seed          = GaussianFit.Parameters( moments: moments, amplitude: image.pixels[ index ] - background, background: background )
        let fit           = GaussianFit.fit( samples: samples, initialGuess: seed )
        let centerX:       Double
        let centerY:       Double
        let fwhmStar:      Double
        let eccentricity:  Double
        let flux:          Double
        let hfrBackground: Double

        if let fit
        {
            // The fit converged to a physical Gaussian: use its sub-pixel centre
            // and shape (`GaussianFit.fit` already guarantees positive axis widths).
            let sigmaMajor = Swift.max( abs( fit.sigmaX ), abs( fit.sigmaY ) )
            let sigmaMinor = Swift.min( abs( fit.sigmaX ), abs( fit.sigmaY ) )

            centerX       = fit.x
            centerY       = fit.y
            fwhmStar      = Self.fwhmPerSigma * ( sigmaMajor * sigmaMinor ).squareRoot()
            eccentricity  = Swift.max( 0, 1 - ( ( sigmaMinor * sigmaMinor ) / ( sigmaMajor * sigmaMajor ) ) ).squareRoot()
            flux          = 2 * Double.pi * fit.amplitude * abs( fit.sigmaX ) * abs( fit.sigmaY )
            hfrBackground = fit.background
        }
        else
        {
            // The fit did not converge: fall back to the footprint moments. Note
            // the flux here is the footprint's background-subtracted sum (its core,
            // above the noise floor), whereas the fit branch reports the analytic
            // integral of the whole fitted Gaussian — so a fallback star's `flux`
            // is a lower bound, not directly comparable to a fitted star's. The
            // geometric metrics (centre, FWHM, HFR, eccentricity) are comparable;
            // only absolute flux differs. No consumer ranks by flux today; revisit
            // if one does.
            centerX       = moments.x
            centerY       = moments.y
            fwhmStar      = moments.fwhm
            eccentricity  = moments.eccentricity
            flux          = moments.flux
            hfrBackground = background
        }

        // Post-measurement purity: the profile must be close to the matched-filter
        // scale (rejecting sub-PSF spikes and over-large blobs / nebulosity) and
        // round enough (rejecting trails and elongated artifacts).
        guard fwhmStar >= self.configuration.minFWHMFactor * fwhm,
              fwhmStar <= self.configuration.maxFWHMFactor * fwhm,
              eccentricity <= self.configuration.roundnessLimit
        else
        {
            return nil
        }

        let hfr = StarMoments.halfFluxRadius( samples: samples, background: hfrBackground, aroundX: centerX, y: centerY, withinRadius: StarMoments.hfrApertureRadiusFactor * fwhmStar )

        return Star( x: centerX, y: centerY, flux: flux, hfr: hfr, fwhm: fwhmStar, eccentricity: eccentricity )
    }

    /// The sharpness of a peak: the mean background-subtracted value of its eight
    /// neighbours relative to its own. A single hot pixel approaches `0` (its
    /// neighbours sit at the background); a broad, flat blob approaches `1`.
    private static func sharpness( at index: Int, in image: PixelBuffer, background: Double ) -> Double
    {
        let width  = image.width
        let height = image.height
        let x      = index % width
        let y      = index / width
        let center = image.pixels[ index ] - background

        guard center > 0
        else
        {
            return 0
        }

        let neighbors = Self.neighborOffsets.compactMap
        {
            offset -> Double? in

            let nx = x + offset.0
            let ny = y + offset.1

            guard nx >= 0, nx < width, ny >= 0, ny < height
            else
            {
                return nil
            }

            return image.pixels[ ( ny * width ) + nx ] - background
        }

        guard neighbors.isEmpty == false
        else
        {
            return 0
        }

        return ( neighbors.reduce( 0, + ) / Double( neighbors.count ) ) / center
    }

    /// The star's connected footprint: the 8-connected patch of pixels above
    /// `level` that contains the peak, found by a flood fill bounded to a square
    /// window around it.
    ///
    /// Growing only from the peak isolates the star from any nearby structure —
    /// neighbouring stars, or bright nebulosity — that a plain "every pixel above
    /// the level in the window" footprint would wrongly absorb, so the moments
    /// measured over it describe this star alone.
    ///
    /// - Parameters:
    ///   - index:  The peak's pixel index.
    ///   - radius: The half-size, in pixels, of the bounding window.
    ///   - level:  The value a pixel must exceed to belong to the footprint.
    ///   - image:  The single-channel image.
    /// - Returns: The footprint's samples, or an empty array when the peak itself
    ///   does not exceed `level`.
    private static func connectedFootprint( around index: Int, radius: Int, level: Double, in image: PixelBuffer ) -> [ ( x: Double, y: Double, value: Double ) ]
    {
        let width  = image.width
        let height = image.height
        let px     = index % width
        let py     = index / width
        let minX   = Swift.max( 0, px - radius )
        let maxX   = Swift.min( width - 1, px + radius )
        let minY   = Swift.max( 0, py - radius )
        let maxY   = Swift.min( height - 1, py + radius )

        var visited = Set< Int >()
        var stack   = [ index ]
        var body    = [ ( x: Double, y: Double, value: Double ) ]()

        while let current = stack.popLast()
        {
            guard visited.insert( current ).inserted, image.pixels[ current ] > level
            else
            {
                continue
            }

            let x = current % width
            let y = current / width

            body.append( ( x: Double( x ), y: Double( y ), value: image.pixels[ current ] ) )

            Self.neighborOffsets.forEach
            {
                let nx = x + $0.0
                let ny = y + $0.1

                guard nx >= minX, nx <= maxX, ny >= minY, ny <= maxY
                else
                {
                    return
                }

                stack.append( ( ny * width ) + nx )
            }
        }

        return body
    }

    /// Collects the in-bounds samples of a square window centred on a pixel.
    static func window( around index: Int, radius: Int, in image: PixelBuffer ) -> [ ( x: Double, y: Double, value: Double ) ]
    {
        let width = image.width
        let px    = index % width
        let py    = index / width

        return ( -radius ... radius ).flatMap
        {
            dy in

            ( -radius ... radius ).compactMap
            {
                dx -> ( x: Double, y: Double, value: Double )? in

                let nx = px + dx
                let ny = py + dy

                guard nx >= 0, nx < width, ny >= 0, ny < image.height
                else
                {
                    return nil
                }

                return ( x: Double( nx ), y: Double( ny ), value: image.pixels[ ( ny * width ) + nx ] )
            }
        }
    }
}
