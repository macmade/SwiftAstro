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

/// Converts a raw one-shot-colour (Bayer CFA) mosaic into a single-channel
/// grayscale image suitable for star detection.
///
/// Star detection expects a linear, single-channel image. A one-shot-colour
/// sensor instead stores a colour-filter-array mosaic, where adjacent pixels
/// sample different colours; feeding that mosaic directly to a detector injects
/// a high-frequency checkerboard that inflates the noise estimate and fragments
/// stars. This converter demosaics the mosaic to RGB (via `SwiftPixel`) at full
/// resolution — preserving the native pixel scale, so half-flux-radius metrics
/// stay in the original frame's pixels — then combines the channels into one
/// luminance-neutral grayscale channel.
///
/// The channels are combined with an **equal-weight mean** rather than a
/// perceptual (Rec. 709) luminance, so red- and blue-dominant stars are not
/// suppressed relative to green ones.
///
/// - Note: Bilinear demosaicing is a low-pass filter — each reconstructed red /
///   blue sample averages neighbouring photosites — so the per-pixel noise of the
///   grayscale output is suppressed relative to a true monochrome frame. Absolute
///   noise measured downstream (``SkyBackground`` / ``SignalToNoise``) on a
///   CFA-derived frame is therefore biased **low** and is not directly comparable
///   to a mono frame's; it stays self-consistent for CFA-vs-CFA weighting. If an
///   absolute, mono-comparable noise is ever needed, estimate it on the raw
///   mosaic per CFA phase instead.
public struct BayerGrayscaleConverter: Sendable
{
    /// The mosaic's colour-filter-array pattern.
    public let pattern: Processors.Debayer.Pattern

    /// The demosaicing algorithm.
    public let mode: Processors.Debayer.Mode

    /// Creates a converter for a given Bayer pattern and demosaicing mode.
    ///
    /// - Parameters:
    ///   - pattern: The mosaic's colour-filter-array pattern (e.g. `.rggb`).
    ///   - mode:    The demosaicing algorithm. Defaults to `.bilinear`.
    public init( pattern: Processors.Debayer.Pattern, mode: Processors.Debayer.Mode = .bilinear )
    {
        self.pattern = pattern
        self.mode    = mode
    }

    /// Converts a raw Bayer mosaic into a single-channel grayscale image.
    ///
    /// - Parameter mosaic: A single-channel, non-normalized Bayer mosaic.
    /// - Returns: A single-channel grayscale image of the same geometry, with the
    ///   demosaiced colour channels averaged. Not normalized.
    /// - Throws: ``SwiftAstro/Error`` if `mosaic` is not single-channel or the
    ///   demosaic does not yield three RGB channels, or any error raised while
    ///   demosaicing.
    public func grayscale( from mosaic: PixelBuffer ) throws -> PixelBuffer
    {
        guard mosaic.channels == 1
        else
        {
            throw Error( message: "BayerGrayscaleConverter requires a single-channel mosaic, got \( mosaic.channels ) channels" )
        }

        let pipeline = PixelPipeline( config: .init( inputFormat: .cfa( pattern: self.pattern, mode: self.mode ) ) )

        // run(pixels:) treats the samples as an already-decoded mosaic; the
        // bitsPerPixel argument is informational only and does not re-decode.
        let rgb = try pipeline.run( pixels: mosaic.pixels, width: mosaic.width, height: mosaic.height, bitsPerPixel: .int16 )

        // The CFA pipeline always demosaics to three interleaved RGB channels;
        // combine them with an equal-weight mean. Guarding the channel count makes
        // that contract explicit and keeps the stride, the read offsets and the
        // divisor on one consistent convention, rather than mixing a dynamic
        // `channels` stride with a hardcoded `/ 3`.
        guard rgb.channels == 3
        else
        {
            throw Error( message: "BayerGrayscaleConverter expected a 3-channel RGB demosaic, got \( rgb.channels ) channels" )
        }

        let gray = ( 0 ..< ( mosaic.width * mosaic.height ) ).map
        {
            index -> Double in

            let base = index * 3

            return ( rgb.pixels[ base ] + rgb.pixels[ base + 1 ] + rgb.pixels[ base + 2 ] ) / 3
        }

        return try PixelBuffer( width: mosaic.width, height: mosaic.height, channels: 1, pixels: gray, isNormalized: false )
    }
}
