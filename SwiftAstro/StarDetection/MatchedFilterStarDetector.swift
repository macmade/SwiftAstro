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
        /// dropped as saturated / bloomed.
        public var saturationLevel: Double?

        /// Creates a configuration with the default purity-oriented parameters.
        public init(
            expectedFWHM:    Double? = nil,
            thresholdSigma:  Double  = 5,
            sharpnessLow:    Double  = 0.2,
            roundnessLimit:  Double  = 0.6,
            minFWHMFactor:   Double  = 0.5,
            maxFWHMFactor:   Double  = 2.0,
            minSeparation:   Double? = nil,
            edgeMargin:      Int     = 4,
            saturationLevel: Double? = nil
        )
        {
            self.expectedFWHM    = expectedFWHM
            self.thresholdSigma  = thresholdSigma
            self.sharpnessLow    = sharpnessLow
            self.roundnessLimit  = roundnessLimit
            self.minFWHMFactor   = minFWHMFactor
            self.maxFWHMFactor   = maxFWHMFactor
            self.minSeparation   = minSeparation
            self.edgeMargin      = edgeMargin
            self.saturationLevel = saturationLevel
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
    private static let neighborOffsets = [ ( -1, -1 ), ( 0, -1 ), ( 1, -1 ), ( -1, 0 ), ( 1, 0 ), ( -1, 1 ), ( 0, 1 ), ( 1, 1 ) ]

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

        let fwhm     = Swift.max( self.configuration.expectedFWHM ?? Self.estimateFWHM( in: image ) ?? Self.defaultFWHM, 1 )
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

        return StarField( stars: stars )
    }

    // MARK: - FWHM auto-estimation

    /// Estimates the stellar FWHM from an image's brightest stars: it finds the
    /// brightest local maxima, sizes each one by its empirical half-flux radius
    /// against its own local background, and takes the median.
    ///
    /// The half-flux radius is used rather than the second moments because it is
    /// dominated by the star's core and so is far less sensitive to the broad
    /// wings of bright, near-saturated stars — which otherwise bias the estimate
    /// high. For a Gaussian, FWHM = 2·HFR.
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

        let widths = maxima.compactMap
        {
            peak -> Double? in

            // Size each bright star against its own local background, over only its
            // connected footprint — the 8-connected patch of pixels above that
            // background containing the peak. On crowded or nebulous frames, taking
            // every above-threshold pixel in a fixed window instead merges the star
            // with its neighbours or with bright nebulosity and inflates the
            // half-flux radius (which is what made the estimate blow up on real
            // one-shot-colour subs).
            let window          = Self.window( around: peak.index, radius: Self.bootstrapWindowRadius, in: image )
            let localBackground = PixelUtilities.median( window.map { $0.value } ) ?? background
            let level           = localBackground + ( Self.footprintSigma * noise )
            let body            = Self.connectedFootprint( around: peak.index, radius: Self.bootstrapWindowRadius, level: level, in: image )

            guard body.count >= Self.minFootprintSamples, let moments = StarMoments( samples: body, background: localBackground ), moments.hfr.isFinite, moments.hfr > 0.3
            else
            {
                return nil
            }

            return moments.hfr * 2
        }

        return PixelUtilities.median( widths )
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

        let hfr = StarMoments.halfFluxRadius( samples: samples, background: hfrBackground, aroundX: centerX, y: centerY )

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
    private static func window( around index: Int, radius: Int, in image: PixelBuffer ) -> [ ( x: Double, y: Double, value: Double ) ]
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
