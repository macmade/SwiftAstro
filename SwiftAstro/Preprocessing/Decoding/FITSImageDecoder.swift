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
import SwiftFITS
import SwiftPixel

/// The FITS implementation of ``ImageDecoding``: header interpretation, sample
/// decoding and the detection image, for every FITS geometry the library
/// supports.
///
/// The image HDU is selected by one rule, stated once here — the first section of
/// kind `.data` at an index greater than zero, paired with the properties of the
/// section immediately preceding it. Geometry is resolved into frames: a plain
/// `NAXIS = 2` image and an `NAXIS = 3` RGB colour cube each yield one frame; a
/// multi-image cube yields one frame per plane.
///
/// - Note: The operations below are declared, documented and reachable, but their
///   bodies have not landed yet. Each throws or answers `nil` until the FITS
///   migration fills it in.
public enum FITSImageDecoder: ImageDecoding
{
    /// A parsed FITS file. Parsing it is the consumer's job.
    public typealias Container = FITSFile

    /// One image HDU, or one plane of a multi-image cube.
    public typealias Frame = FITSImageFrame

    /// The owning header's property snapshots.
    public typealias Properties = [ FITSPropertySnapshot ]

    /// Enumerates the file's images: the selected image HDU, or one frame per
    /// plane when that HDU is a multi-image cube.
    ///
    /// - Parameter container: The parsed FITS file.
    /// - Returns: One frame per image, in file order.
    /// - Throws: ``Error`` when the file holds no image data section.
    public static func frames( in container: FITSFile ) throws -> [ FITSImageFrame ]
    {
        throw self.unimplemented( "frames( in: )" )
    }

    /// The frame's bytes with the FITS 2880-byte block padding trimmed to the byte
    /// count its geometry implies, paired with its header.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The trimmed bytes and the frame's header.
    /// - Throws: ``Error`` when the geometry is missing or the bytes are short of
    ///   it.
    public static func contents( of frame: FITSImageFrame ) throws -> ( bytes: Data, properties: [ FITSPropertySnapshot ] )
    {
        throw self.unimplemented( "contents( of: )" )
    }

    /// Decodes the bytes into scaled-linear samples: `BITPIX` selects the sample
    /// format, `BLANK` maps undefined integer samples to NaN, then `BSCALE` and
    /// `BZERO` are applied.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - properties: The frame's header.
    /// - Returns: The geometry and scaled-linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: [ FITSPropertySnapshot ] ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// Decodes the bytes into one raw, unscaled plane per channel — three
    /// band-sequential planes for an RGB colour cube, one otherwise.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - properties: The frame's header.
    /// - Returns: One plane per channel.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    public static func planeSamples( bytes: Data, properties: [ FITSPropertySnapshot ] ) throws -> [ [ Double ] ]
    {
        throw self.unimplemented( "planeSamples( bytes:properties: )" )
    }

    /// Combines decoded planes into one scaled-linear luminance channel, as the
    /// per-pixel mean of the planes with `BSCALE` / `BZERO` applied.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The frame's header.
    /// - Returns: The geometry and luminance samples, or `nil`.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: [ FITSPropertySnapshot ] ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// Reads the linear pixel-scaling keywords `BSCALE` (the multiplicative
    /// scale, default `1`) and `BZERO` (the additive offset, default `0`).
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: [ FITSPropertySnapshot ] ) -> ( scale: Double, offset: Double )
    {
        ( scale: 0, offset: 0 )
    }

    /// The span of the `BITPIX` sample format: `255`, `65535` or `4294967295` for
    /// the integer formats, applied after ``scaling(from:)``.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The full-scale value, or `nil` for a floating-point `BITPIX`.
    public static func fullScale( from properties: [ FITSPropertySnapshot ] ) -> Double?
    {
        nil
    }

    /// The sample format the header's `BITPIX` names.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The sample format, or `nil` when `BITPIX` is missing or names an
    ///   unsupported format.
    public static func bitsPerPixel( from properties: [ FITSPropertySnapshot ] ) -> BitsPerPixel?
    {
        nil
    }

    /// The pattern named by the header's `BAYERPAT` keyword, through the shared
    /// ``ColorFilterArray`` mapping.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The pattern, or `nil` when the header carries no `BAYERPAT`
    ///   (the frame is monochrome).
    /// - Throws: ``Error`` when `BAYERPAT` names an unsupported pattern.
    public static func cfaPattern( from properties: [ FITSPropertySnapshot ] ) throws -> Processors.Debayer.Pattern?
    {
        throw self.unimplemented( "cfaPattern( from: )" )
    }

    /// The dimensions the header's `NAXIS1` and `NAXIS2` keywords give.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The width and height, or `nil` when either keyword is missing or
    ///   not positive.
    public static func dimensions( from properties: [ FITSPropertySnapshot ] ) -> ( width: Int, height: Int )?
    {
        nil
    }

    /// `3` for an RGB colour cube — `NAXIS = 3` with `NAXIS3 = 3` and no physical
    /// third axis (`CTYPE3`) — and `1` for every other geometry, a
    /// colour-filter-array mosaic included: a mosaic is one channel until it is
    /// demosaiced.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The channel count.
    public static func channelCount( from properties: [ FITSPropertySnapshot ] ) -> Int
    {
        0
    }

    /// Decodes the single big-endian sample stored at a byte index, before
    /// ``scaling(from:)`` is applied.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - index:      The sample's index into `bytes`.
    ///   - properties: The frame's header.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: [ FITSPropertySnapshot ] ) -> Double?
    {
        nil
    }

    /// The byte indices covering an image coordinate: three band-sequential
    /// indices for an RGB colour cube, one otherwise.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column.
    ///   - y:          The zero-based row.
    ///   - properties: The frame's header.
    /// - Returns: One index per channel, or `nil`.
    public static func sampleByteOffsets( x: Int, y: Int, properties: [ FITSPropertySnapshot ] ) -> [ Data.Index ]?
    {
        nil
    }

    /// The detection image: an RGB colour cube combined to luminance, any other
    /// frame decoded to its linear channel and — when `BAYERPAT` names a pattern —
    /// demosaiced to luminance.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - properties: The frame's header.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: [ FITSPropertySnapshot ] ) -> PixelBuffer?
    {
        nil
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: FITSImageFrame ) throws -> PixelBuffer
    {
        throw self.unimplemented( "detectionImage( of: )" )
    }
}
