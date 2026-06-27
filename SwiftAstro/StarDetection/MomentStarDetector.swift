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

/// Detects stars by thresholding above a robust background, grouping connected
/// pixels into sources, and measuring each from its flux-weighted moments.
///
/// The metrics are measured over each source's thresholded pixels
/// (background-subtracted): a flux-weighted centroid, the half-flux radius, and
/// the FWHM and eccentricity from the second moments. This is the standard
/// "HFR-style" approach used for focus and tracking quality, and is robust to
/// noise and hot pixels without the cost of full PSF fitting.
public struct MomentStarDetector: StarDetecting
{
    /// Tunable detection parameters.
    public struct Configuration: Sendable
    {
        /// How many noise sigmas above the background a pixel must be to count as
        /// part of a source.
        public var thresholdSigma: Double

        /// The minimum number of pixels a source must have, rejecting hot pixels
        /// and cosmic rays.
        public var minPixelCount: Int

        /// The maximum number of pixels a source may have, rejecting oversized
        /// blobs (e.g. saturation bloom or large nebulosity).
        public var maxPixelCount: Int

        /// Sources whose bounding box comes within this many pixels of the image
        /// edge are rejected, since their profiles are clipped.
        public var edgeMargin: Int

        /// Creates a configuration with sensible defaults.
        public init( thresholdSigma: Double = 5, minPixelCount: Int = 5, maxPixelCount: Int = 5000, edgeMargin: Int = 4 )
        {
            self.thresholdSigma = thresholdSigma
            self.minPixelCount  = minPixelCount
            self.maxPixelCount  = maxPixelCount
            self.edgeMargin     = edgeMargin
        }
    }

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

    /// Detects stars by thresholding above the robust background, grouping the
    /// connected above-threshold pixels into sources, filtering them, and
    /// measuring each from its flux-weighted moments.
    ///
    /// - Parameter image: The single-channel, linear image to analyze.
    /// - Returns: The detected stars and their aggregate metrics; an empty field
    ///   for a degenerate (zero-size) image.
    /// - Throws: ``SwiftAstro/Error`` if the image is not single-channel.
    public func detectStars( in image: PixelBuffer ) throws -> StarField
    {
        guard image.channels == 1
        else
        {
            throw Error( message: "MomentStarDetector requires a single-channel image, got \( image.channels ) channels" )
        }

        guard image.width > 0, image.height > 0
        else
        {
            return StarField( stars: [] )
        }

        let background = Statistics.median( image.pixels ) ?? 0
        let noise      = ( Statistics.medianAbsoluteDeviation( image.pixels, around: background ) ?? 0 ) * 1.4826
        let threshold  = background + ( self.configuration.thresholdSigma * noise )
        let components = Self.connectedComponents( in: image, threshold: threshold )

        let stars = components.compactMap
        {
            component -> Star? in

            guard component.pixels.count >= self.configuration.minPixelCount,
                  component.pixels.count <= self.configuration.maxPixelCount,
                  self.isWithinBounds( component, image: image )
            else
            {
                return nil
            }

            return Self.measure( component, in: image, background: background )
        }

        return StarField( stars: stars )
    }

    /// Whether a source's bounding box clears the configured edge margin.
    private func isWithinBounds( _ component: Component, image: PixelBuffer ) -> Bool
    {
        let margin = self.configuration.edgeMargin

        return component.minX >= margin
            && component.minY >= margin
            && component.maxX <  image.width  - margin
            && component.maxY <  image.height - margin
    }

    // MARK: - Connected components

    /// A connected group of above-threshold pixels.
    private struct Component
    {
        /// The pixel coordinates belonging to the component.
        var pixels: [ ( x: Int, y: Int ) ] = []

        /// The smallest column among the component's pixels.
        var minX = Int.max

        /// The smallest row among the component's pixels.
        var minY = Int.max

        /// The largest column among the component's pixels.
        var maxX = Int.min

        /// The largest row among the component's pixels.
        var maxY = Int.min

        /// Adds a pixel to the component, expanding its bounding box.
        ///
        /// - Parameters:
        ///   - x: The pixel column.
        ///   - y: The pixel row.
        mutating func add( x: Int, y: Int )
        {
            self.pixels.append( ( x, y ) )

            self.minX = Swift.min( self.minX, x )
            self.minY = Swift.min( self.minY, y )
            self.maxX = Swift.max( self.maxX, x )
            self.maxY = Swift.max( self.maxY, y )
        }
    }

    /// Groups above-threshold pixels into 8-connected components via flood fill.
    ///
    /// `image` is single-channel, so its row-major `pixels` index is `y · width + x`.
    private static func connectedComponents( in image: PixelBuffer, threshold: Double ) -> [ Component ]
    {
        let width   = image.width
        let height  = image.height
        var visited = [ Bool ]( repeating: false, count: width * height )
        var result  = [ Component ]()

        ( 0 ..< ( width * height ) ).forEach
        {
            startIndex in

            guard visited[ startIndex ] == false, image.pixels[ startIndex ] > threshold
            else
            {
                return
            }

            // Flood-fill the component from this seed. A worklist (`while let`) is
            // the natural form for this graph traversal; the per-node neighbour
            // scan is expressed over the fixed offsets.
            var component = Component()
            var stack     = [ ( startIndex % width, startIndex / width ) ]
            visited[ startIndex ] = true

            while let ( x, y ) = stack.popLast()
            {
                component.add( x: x, y: y )

                Self.neighborOffsets.forEach
                {
                    let nx = x + $0.0
                    let ny = y + $0.1

                    guard nx >= 0, nx < width, ny >= 0, ny < height
                    else
                    {
                        return
                    }

                    let index = ( ny * width ) + nx

                    if visited[ index ] == false, image.pixels[ index ] > threshold
                    {
                        visited[ index ] = true

                        stack.append( ( nx, ny ) )
                    }
                }
            }

            result.append( component )
        }

        return result
    }

    // MARK: - Measurement

    /// Measures a source's centroid, flux, HFR, FWHM and eccentricity by
    /// delegating to the shared ``StarMoments`` math.
    private static func measure( _ component: Component, in image: PixelBuffer, background: Double ) -> Star?
    {
        // The component's pixels were produced from in-bounds coordinates of a
        // single-channel buffer, so the row-major index `y · width + x` is valid.
        let samples = component.pixels.map
        {
            pixel -> ( x: Double, y: Double, value: Double ) in

            ( x: Double( pixel.x ), y: Double( pixel.y ), value: image.pixels[ ( pixel.y * image.width ) + pixel.x ] )
        }

        guard let moments = StarMoments( samples: samples, background: background )
        else
        {
            return nil
        }

        return Star( x: moments.x, y: moments.y, flux: moments.flux, hfr: moments.hfr, fwhm: moments.fwhm, eccentricity: moments.eccentricity )
    }
}
