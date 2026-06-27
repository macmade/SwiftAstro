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
/// cuts, and survivors are measured with a 2D Gaussian fit
/// (``SwiftPixel/GaussianFit``) seeded from their moments (``StarMoments``).
///
/// The matched-filter scale is auto-estimated from the image's brightest stars
/// unless a ``Configuration/expectedFWHM`` override is set. The detector optimizes
/// for purity: it would rather miss a faint star than report a false one.
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

        /// The lower sharpness bound: candidates below it are too concentrated
        /// (single hot pixels).
        public var sharpnessLow: Double

        /// The upper sharpness bound: candidates above it are too broad / flat.
        public var sharpnessHigh: Double

        /// The maximum eccentricity a candidate may have; more elongated ones
        /// (trails, artifacts) are rejected.
        public var roundnessLimit: Double

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
            sharpnessHigh:   Double  = 1.0,
            roundnessLimit:  Double  = 0.5,
            minSeparation:   Double? = nil,
            edgeMargin:      Int     = 4,
            saturationLevel: Double? = nil
        )
        {
            self.expectedFWHM    = expectedFWHM
            self.thresholdSigma  = thresholdSigma
            self.sharpnessLow    = sharpnessLow
            self.sharpnessHigh   = sharpnessHigh
            self.roundnessLimit  = roundnessLimit
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

        let background = Statistics.median( image.pixels ) ?? 0
        let fwhm       = Swift.max( self.configuration.expectedFWHM ?? Self.estimateFWHM( in: image ) ?? Self.defaultFWHM, 1 )
        let sigma      = fwhm / Self.fwhmPerSigma
        let kernel     = GaussianKernel( sigma: sigma )
        let response   = Convolution.zeroSumResponse( of: image, kernel: kernel )

        let center = Statistics.median( response ) ?? 0
        let sigmaC = ( Statistics.medianAbsoluteDeviation( response, around: center ) ?? 0 ) * 1.4826

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
            self.measure( peak: $0.index, in: image, background: background, fwhm: fwhm )
        }

        return StarField( stars: stars )
    }

    // MARK: - FWHM auto-estimation

    /// Estimates the stellar FWHM from an image's brightest stars: it finds the
    /// brightest local maxima, sizes each one's body via its moments, and takes
    /// the median — robust to the occasional non-stellar peak.
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

        let background = Statistics.median( image.pixels ) ?? 0
        let noise      = ( Statistics.medianAbsoluteDeviation( image.pixels, around: background ) ?? 0 ) * 1.4826

        guard noise > 0
        else
        {
            return nil
        }

        let highThreshold = background + ( Self.bootstrapSigma * noise )
        let bodyThreshold = background + ( 3 * noise )
        let maxima        = Self.localMaxima( in: image.pixels, width: image.width, height: image.height, threshold: highThreshold )

        let widths = maxima.compactMap
        {
            peak -> Double? in

            let body = Self.window( around: peak.index, radius: Self.bootstrapWindowRadius, in: image ).filter { $0.value > bodyThreshold }

            guard body.count >= 5, let moments = StarMoments( samples: body, background: background ), moments.fwhm.isFinite, moments.fwhm > 0
            else
            {
                return nil
            }

            return moments.fwhm
        }

        return Statistics.median( widths )
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

    /// Measures a candidate peak, applying the purity cuts and the Gaussian fit.
    ///
    /// - Returns: The measured star, or `nil` if the candidate is clipped by the
    ///   edge, saturated, fails the sharpness or roundness cut, or its fit does
    ///   not converge to a physical Gaussian.
    private func measure( peak index: Int, in image: PixelBuffer, background: Double, fwhm: Double ) -> Star?
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

        let sharpness = Self.sharpness( at: index, in: image, background: background )

        guard sharpness >= self.configuration.sharpnessLow, sharpness <= self.configuration.sharpnessHigh
        else
        {
            return nil
        }

        let radius  = Swift.max( 3, Int( ( 1.5 * fwhm ).rounded() ) )
        let samples = Self.window( around: index, radius: radius, in: image )

        guard let moments = StarMoments( samples: samples, background: background ), moments.eccentricity <= self.configuration.roundnessLimit
        else
        {
            return nil
        }

        let seed = GaussianFit.Parameters( moments: moments, amplitude: image.pixels[ index ] - background, background: background )

        guard let fit = GaussianFit.fit( samples: samples, initialGuess: seed )
        else
        {
            return nil
        }

        let sigmaMajor = Swift.max( abs( fit.sigmaX ), abs( fit.sigmaY ) )
        let sigmaMinor = Swift.min( abs( fit.sigmaX ), abs( fit.sigmaY ) )

        guard sigmaMajor > 0
        else
        {
            return nil
        }

        let fwhmStar     = Self.fwhmPerSigma * ( sigmaMajor * sigmaMinor ).squareRoot()
        let eccentricity = Swift.max( 0, 1 - ( ( sigmaMinor * sigmaMinor ) / ( sigmaMajor * sigmaMajor ) ) ).squareRoot()
        let hfr          = StarMoments.halfFluxRadius( samples: samples, background: background, aroundX: fit.x, y: fit.y )
        let flux         = 2 * Double.pi * fit.amplitude * abs( fit.sigmaX ) * abs( fit.sigmaY )

        return Star( x: fit.x, y: fit.y, flux: flux, hfr: hfr, fwhm: fwhmStar, eccentricity: eccentricity )
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
