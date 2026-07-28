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
/// The two decisions taken over the **whole frame at once** — the scale estimate
/// and the bright pass's blob threshold — are measured against a
/// **spatially-varying** ``LocalBackground`` rather than one whole-image level and
/// noise. On a frame carrying large-area structure (nebulosity, light pollution,
/// vignetting) a global pair puts a wide swathe of the frame many sigmas above the
/// median, which both poisons the scale estimate and turns a bright patch of gas
/// into a scatter of spurious detections.
///
/// The two decisions that are *already* local need no map: the matched filter's own
/// gate is a threshold on the convolved response, and a zero-sum filter has removed
/// the smooth background before that threshold is applied; and a candidate's
/// footprint level comes from its own measurement window. Measurement stays on the
/// raw samples throughout — the one place a mapped value is reported is the bright
/// pass, where the mapped level stands in as the photometric zero for a blob whose
/// sky annulus yields no measurable flux.
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

        /// How many noise sigmas above the **local** background a pixel must exceed
        /// to belong to a bright blob in the bright-star pass. Higher isolates only
        /// the very brightest sources; lower lets the pass reach dimmer, larger
        /// stars — at the cost of admitting more nebulosity and noise.
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

    /// The factor converting a median absolute deviation to a robust standard
    /// deviation, sourced from the shared
    /// ``SwiftPixel/PixelUtilities/madStandardDeviationScale`` so the detector,
    /// ``SignalToNoise``, ``SkyBackground`` and ``LocalBackground`` all use one
    /// value and cannot drift.
    private static let madToSigma = PixelUtilities.madStandardDeviationScale

    /// The FWHM used when auto-estimation finds no stars to size.
    private static let defaultFWHM = 3.0

    /// How many noise sigmas above the local background the FWHM bootstrap
    /// thresholds at, to isolate only the brightest, unambiguous stars.
    private static let bootstrapSigma = 10.0

    /// The half-size, in pixels, of the window the FWHM bootstrap first measures
    /// each bright star over.
    private static let bootstrapWindowRadius = 10

    /// The bootstrap's second-pass window half-size, as a multiple of the first
    /// pass's measured FWHM.
    ///
    /// A bright star's footprint — the patch standing `footprintSigma` above the
    /// sky — reaches `σ·√(2 ln(A / 3σ_noise))`, about `1.6 × FWHM` for a peak a
    /// thousand times the noise. The sky annulus starts at `0.65 ×` the window, so
    /// the window must be at least `1.6 / 0.65 ≈ 2.5 × FWHM` for that annulus to
    /// clear the star. Any less and the "sky" is read on the star's own skirt,
    /// which raises the footprint level, clips the footprint, and sizes the star
    /// small — the very error this second pass exists to correct.
    private static let bootstrapWindowScale = 2.5

    /// The largest half-size, in pixels, the bootstrap's second-pass window may
    /// reach, bounding the per-star cost on a frame of very broad sources.
    ///
    /// This caps accuracy as well as cost. By ``bootstrapWindowScale``'s derivation
    /// the sky annulus only clears the star while the window is at least `2.5 ×` the
    /// FWHM, so past a FWHM of about `16` px the annulus re-enters the skirt and the
    /// second pass under-sizes again — measured, a `33` px star reads `18.8`.
    ///
    /// The *scale* being short does not stop detection, because the size band is
    /// generous relative to that error, but it does bound how far into defocus the
    /// detector remains useful. Measured on synthetic discs: at a true FWHM of `33`
    /// px every star is found and reported at `33.0`; at `47` px they are all found
    /// and reported at `32`, with a half-flux radius `29 %` short; at `59` px the
    /// count starts to fall; beyond about `70` px detection collapses. A focus
    /// routine sweeping through defocus should treat readings past ~`50` px FWHM as
    /// a lower bound rather than a measurement.
    private static let bootstrapWindowMaxRadius = 40

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

        // Measure the background *map*, and let every detection decision below read
        // it locally. A single global median / MAD pair describes a frame with
        // large-area structure — nebulosity, light pollution, vignetting — so badly
        // that the scale estimate itself is wrong by several fold on such frames
        // (see ``LocalBackground``); everything downstream then inherits that error.
        guard let ( background, fwhm ) = Self.scale( of: image, configuration: self.configuration )
        else
        {
            return StarField( stars: [] )
        }

        let sigma    = fwhm / Self.fwhmPerSigma
        let kernel   = GaussianKernel( sigma: sigma )
        let response = Convolution.zeroSumResponse( of: image, kernel: kernel )

        let center = PixelUtilities.median( response ) ?? 0
        let sigmaC = ( PixelUtilities.medianAbsoluteDeviation( response, around: center ) ?? 0 ) * Self.madToSigma

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

        let bright = self.brightStars( in: image, background: background, fwhm: fwhm, minSeparation: minSeparation, excluding: stars )

        return StarField( stars: stars + bright )
    }

    // MARK: - FWHM auto-estimation

    /// The smallest background tile, as a multiple of the stellar FWHM, at which the
    /// mesh still describes sky rather than the stars sitting on it.
    ///
    /// A tile is measured by its own median and MAD, so it reports sky only while
    /// stars are a minority of it. Measured against a synthetic defocused field, a
    /// tile holds up to roughly `0.7 ×` its edge in FWHM at the mesh interior and
    /// `0.5 ×` at a mesh corner (where the median filter's edge clamp weakens it);
    /// `3` sits beyond the corner case with margin.
    private static let backgroundTileScale = 3.0

    /// The largest background tile, in pixels, the widening search will try. At this
    /// point the mesh is coarse enough that it no longer follows sky structure
    /// usefully, so widening further trades the map's whole purpose for a scale
    /// estimate.
    private static let backgroundMaxTileSize = 512

    /// The background map to detect against, and the matched-filter scale to detect
    /// at — resolved together, because each constrains the other.
    ///
    /// The mesh only describes sky while the sources are a minority of a tile, and
    /// how large the sources are is exactly what the scale estimate is for. A
    /// heavily defocused frame — which an autofocus run produces by design, and this
    /// library reports HFR for — breaks that circle: its stars can fill a whole
    /// default tile, the mesh then measures the stars, every threshold rises above
    /// them, and the scale estimate collapses to its default while the detector goes
    /// on to report confidently wrong widths for the fragments it finds.
    ///
    /// So the tile widens until it is comfortably larger than the stars it has
    /// measured. A frame of ordinary stars settles on the first tile and pays for
    /// exactly one map, as before; only a frame that cannot be resolved at the
    /// default tile pays for another.
    ///
    /// - Parameters:
    ///   - image:         The single-channel image.
    ///   - configuration: The detection parameters, for the ``Configuration/expectedFWHM``
    ///                    override.
    /// - Returns: The map and the scale, or `nil` when the image yields no
    ///   measurable background at all.
    private static func scale( of image: PixelBuffer, configuration: Configuration ) -> ( background: LocalBackground, fwhm: Double )?
    {
        // A caller-supplied scale needs no search — it sizes the mesh directly. It is
        // also sanitized here: `expectedFWHM` is public, and a non-finite value would
        // otherwise survive every clamp below and trap on conversion to `Int`.
        if let expected = configuration.expectedFWHM
        {
            let fwhm = expected.isFinite ? Swift.max( expected, 1 ) : Self.defaultFWHM

            guard let background = LocalBackground.estimate( in: image, tileSize: Self.tileSize( for: fwhm ) )
            else
            {
                return nil
            }

            return ( background: background, fwhm: fwhm )
        }

        var tile     = LocalBackground.defaultTileSize
        var fallback = LocalBackground?.none

        while tile <= Self.backgroundMaxTileSize
        {
            guard let background = LocalBackground.estimate( in: image, tileSize: tile )
            else
            {
                return nil
            }

            fallback = fallback ?? background

            let estimate = Self.estimateScale( in: image, background: background )

            if let fwhm = estimate.fwhm, tile >= Self.tileSize( for: fwhm )
            {
                return ( background: background, fwhm: Swift.max( fwhm, 1 ) )
            }

            // Nothing anywhere on the frame rises above its own local background —
            // a dark, a bias, a flat, a starless sub. Widening cannot conjure a
            // source to size, so stop instead of rebuilding the map three more
            // times. A frame that *has* peaks but cannot size them is the opposite
            // case: there, the tile is what is standing in the way, so it widens.
            guard estimate.foundPeaks
            else
            {
                break
            }

            tile *= 2
        }

        // No tile resolved a scale: detect at the default scale against the
        // default-tile map, rather than reporting nothing.
        guard let fallback
        else
        {
            return nil
        }

        return ( background: fallback, fwhm: Self.defaultFWHM )
    }

    /// The background tile a frame of the given stellar width needs.
    ///
    /// - Parameter fwhm: The stellar FWHM, in pixels.
    /// - Returns: The tile edge, in pixels, never below ``LocalBackground/defaultTileSize``.
    private static func tileSize( for fwhm: Double ) -> Int
    {
        let needed = Self.backgroundTileScale * fwhm

        guard needed.isFinite, needed > Double( LocalBackground.defaultTileSize )
        else
        {
            return LocalBackground.defaultTileSize
        }

        // Bound in `Double` before converting: a huge but finite `fwhm` would
        // otherwise overflow the conversion and trap before the `min` could apply.
        return Int( Swift.min( needed.rounded( .up ), Double( Self.backgroundMaxTileSize ) ) )
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
    /// This is the detector's own scale bootstrap, offered on its own for a caller
    /// that wants a frame's stellar width without paying for a full detection — a
    /// focus or frame-grading routine, say, which needs the number but not the star
    /// list, and would otherwise fit a Gaussian to every star to get it. It measures
    /// the background map itself; ``detectStars(in:)`` builds that map once and uses
    /// an overload that takes it.
    ///
    /// **Accuracy bounds.** The measurement is made over a window that grows with the
    /// first estimate but stops at ``bootstrapWindowMaxRadius``, so it is reliable for
    /// ordinary stellar widths and progressively short for broad ones: a frame of
    /// 33 px stars reads 33, one of 47 px stars reads about 32, and past roughly
    /// 70 px nothing can be sized at all. Treat a reading above ~50 px as a lower
    /// bound rather than a measurement.
    ///
    /// - Parameter image: The single-channel image to size.
    /// - Returns: The median FWHM, in pixels, or `nil` when no bright star can be
    ///   sized — a frame with no sources above its local background, or one whose
    ///   samples are all non-finite.
    public static func estimateFWHM( in image: PixelBuffer ) -> Double?
    {
        guard let background = LocalBackground.estimate( in: image )
        else
        {
            return nil
        }

        return Self.estimateScale( in: image, background: background ).fwhm
    }

    /// Estimates the stellar FWHM against an already-measured background map, in two
    /// passes: a fixed-window measurement of the frame's bright stars, then — when
    /// that seed implies stars broader than the window could hold — one re-measure
    /// over a window scaled to it.
    ///
    /// - Parameters:
    ///   - image:      The single-channel image to size.
    ///   - background: The frame's background map, supplying the local level and
    ///                 noise every threshold below is measured against.
    /// - Returns: The median FWHM in pixels — `nil` when no bright star could be
    ///   sized — and whether the frame offered any bright peak to size at all. The
    ///   two differ: a frame with no peaks has nothing to measure, while a frame
    ///   with peaks it cannot size is one whose background map is standing in the
    ///   way.
    private static func estimateScale( in image: PixelBuffer, background: LocalBackground ) -> ( fwhm: Double?, foundPeaks: Bool )
    {
        guard image.channels == 1, image.width > 0, image.height > 0, background.noises.contains( where: { $0 > 0 } )
        else
        {
            return ( fwhm: nil, foundPeaks: false )
        }

        // Threshold against the *local* level and noise. Globally, a frame carrying
        // bright nebulosity puts a large share of its area many sigmas above the
        // whole-image median, so this scan returns tens of thousands of noise
        // ripples riding on the gas instead of the frame's handful of bright stars —
        // and their slivers of footprint then size the detection scale several-fold
        // too small.
        let maxima = Self.localMaxima( in: image.pixels, width: image.width, height: image.height )
        {
            background.threshold( atX: Double( $0 % image.width ), y: Double( $0 / image.width ), sigmas: Self.bootstrapSigma )
        }

        guard let seed = Self.medianFootprintWidth( of: maxima, in: image, background: background, radius: Self.bootstrapWindowRadius )
        else
        {
            return ( fwhm: nil, foundPeaks: maxima.isEmpty == false )
        }

        // A star broader than the fixed window is measured against a sky annulus that
        // falls inside the star itself, which reads the star as its own background,
        // collapses the footprint toward the core, and sizes the star far below the
        // truth. Re-measure over a window scaled to the seed, where the annulus
        // clears the star.
        //
        // The wider window is only trustworthy if it still sees *single* stars. On a
        // crowded field it reaches into the neighbours instead, and the footprints
        // that merge them are dropped by the isolation test — so the wide pass falls
        // back to sizing merged blobs, which reads several times too large. That is
        // the runaway that collapses a rich cluster to a handful of detections, so
        // the wide pass is accepted only while it still rests on about as many
        // unmerged stars as the seed did; otherwise the seed stands.
        let wide = Swift.min( Int( ( Self.bootstrapWindowScale * seed.fwhm ).rounded() ), Self.bootstrapWindowMaxRadius )

        guard wide > Self.bootstrapWindowRadius,
              let widened = Self.medianFootprintWidth( of: maxima, in: image, background: background, radius: wide ),
              ( widened.isolated * 2 ) >= seed.isolated
        else
        {
            return ( fwhm: seed.fwhm, foundPeaks: true )
        }

        return ( fwhm: widened.fwhm, foundPeaks: true )
    }

    /// The median width of a frame's bright stars, sized over a given window.
    ///
    /// Footprints that have *not* merged a neighbouring bright star are preferred: a
    /// blob of several merged stars sizes several times too large, and on a dense
    /// field of small stars (a drizzled master) that inflated scale then makes the
    /// size-band cut reject the whole real population. A footprint containing only
    /// its own peak is a single, isolated star that sizes the point spread
    /// correctly. When every bright star is crowded, the merged footprints are used
    /// anyway rather than reporting no scale at all.
    ///
    /// - Parameters:
    ///   - maxima:     The bright peaks to size.
    ///   - image:      The single-channel image.
    ///   - background: The frame's background map.
    ///   - radius:     The half-size, in pixels, of the window each star is sized
    ///                 over.
    /// - Returns: The median FWHM in pixels, and how many stars it rests on that were
    ///   sized *without* merging a neighbour — `0` when every star was crowded and
    ///   the merged footprints had to be used; `nil` when no peak can be sized.
    private static func medianFootprintWidth( of maxima: [ ( index: Int, value: Double ) ], in image: PixelBuffer, background: LocalBackground, radius: Int ) -> ( fwhm: Double, isolated: Int )?
    {
        let peaks    = Set( maxima.map { $0.index } )
        let isolated = maxima.compactMap { Self.footprintWidth( around: $0.index, in: image, background: background, radius: radius, isolatedAmong: peaks ) }
        let measured = isolated.isEmpty ? maxima.compactMap { Self.footprintWidth( around: $0.index, in: image, background: background, radius: radius, isolatedAmong: nil ) } : isolated

        guard let median = PixelUtilities.median( measured )
        else
        {
            return nil
        }

        return ( fwhm: median, isolated: isolated.count )
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
    ///   - background:    The frame's background map, supplying both the fallback
    ///                    level when the sky annulus yields no median and the local
    ///                    noise the footprint level stands on.
    ///   - radius:        The half-size, in pixels, of the window the star is sized
    ///                    over.
    ///   - isolatedAmong: The set of bright-peak indices to test the footprint
    ///                    against, or `nil` to skip the merge test.
    /// - Returns: The star's FWHM (the footprint's geometric-mean width), or `nil`
    ///   when it cannot be sized or its footprint merged a neighbour.
    private static func footprintWidth( around index: Int, in image: PixelBuffer, background: LocalBackground, radius: Int, isolatedAmong: Set< Int >? ) -> Double?
    {
        // Read the sky from the window's outer annulus, not its whole extent
        // (IMP-12). A bright star's core fills much of this window, so a whole-window
        // median reads the star itself as "background" — landing the footprint level
        // inside the core, so the footprint shrinks toward the core and the star
        // sizes small. The annulus sits beyond the core, on true sky. Only the
        // *background* is read from the annulus; the level's noise term comes from
        // the background map, because this annulus straddles a moderate star's skirt,
        // so its own MAD would be skirt-driven rather than sky-driven.
        let window          = Self.window( around: index, radius: radius, in: image )
        let peakX           = Double( index % image.width )
        let peakY           = Double( index / image.width )
        let skyInner        = Double( radius ) * 0.65
        let annulus         = window.filter { Foundation.hypot( $0.x - peakX, $0.y - peakY ) >= skyInner }.map { $0.value }
        let localBackground = PixelUtilities.median( annulus ) ?? ( PixelUtilities.median( window.map { $0.value } ) ?? background.level( atX: peakX, y: peakY ) )
        let level           = localBackground + ( Self.footprintSigma * background.noise( atX: peakX, y: peakY ) )
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

    /// Finds the strict 8-neighbourhood local maxima of a sample grid that exceed a
    /// uniform threshold.
    ///
    /// - Parameters:
    ///   - values:    The sample grid.
    ///   - width:     The grid width, in samples.
    ///   - height:    The grid height, in samples.
    ///   - threshold: The value a sample must exceed to be a candidate peak.
    /// - Returns: The qualifying peaks and their values.
    private static func localMaxima( in values: [ Double ], width: Int, height: Int, threshold: Double ) -> [ ( index: Int, value: Double ) ]
    {
        Self.localMaxima( in: values, width: width, height: height ) { _ in threshold }
    }

    /// Finds the strict 8-neighbourhood local maxima of a sample grid that exceed a
    /// **position-dependent** threshold — the form a spatially-varying background
    /// needs, where "above the background" means a different value in every part of
    /// the frame.
    ///
    /// - Parameters:
    ///   - values:    The sample grid.
    ///   - width:     The grid width, in samples.
    ///   - height:    The grid height, in samples.
    ///   - threshold: The value a sample at a given index must exceed to be a
    ///                candidate peak.
    /// - Returns: The qualifying peaks and their values.
    private static func localMaxima( in values: [ Double ], width: Int, height: Int, threshold: ( Int ) -> Double ) -> [ ( index: Int, value: Double ) ]
    {
        values.indices.compactMap
        {
            index -> ( index: Int, value: Double )? in

            let value = values[ index ]

            guard value > threshold( index )
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
        let noise     = ( PixelUtilities.medianAbsoluteDeviation( samples.map { $0.value }, around: background ) ?? 0 ) * Self.madToSigma
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
            let sigmaMajor = Swift.max( Swift.abs( fit.sigmaX ), Swift.abs( fit.sigmaY ) )
            let sigmaMinor = Swift.min( Swift.abs( fit.sigmaX ), Swift.abs( fit.sigmaY ) )

            centerX       = fit.x
            centerY       = fit.y
            fwhmStar      = Self.fwhmPerSigma * ( sigmaMajor * sigmaMinor ).squareRoot()
            eccentricity  = Swift.max( 0, 1 - ( ( sigmaMinor * sigmaMinor ) / ( sigmaMajor * sigmaMajor ) ) ).squareRoot()
            flux          = 2 * Double.pi * fit.amplitude * Swift.abs( fit.sigmaX ) * Swift.abs( fit.sigmaY )
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
