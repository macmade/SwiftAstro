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
import SwiftXISF

/// The XISF implementation of ``ImageDecoding``: sample-format and byte-order
/// interpretation, plane extraction and the detection image.
///
/// XISF states its layout explicitly — sample format, byte order, planar or
/// interleaved storage, colour space — so there is little to infer and the whole
/// container parse is one call. That makes it the clearest test of whether the
/// shared shape holds: every operation still has something real to answer, and an
/// operation that looks unnecessary here is one a caller would have to
/// special-case.
///
/// - Note: The operations below are declared, documented and reachable, but their
///   bodies have not landed yet. Each throws or answers `nil` until the XISF
///   migration fills it in.
public enum XISFImageDecoder: ImageDecoding
{
    /// A parsed XISF file. Parsing it is the consumer's job.
    public typealias Container = XISFFile

    /// One image within the file.
    public typealias Frame = XISFImageFrame

    /// The image's pixel layout.
    public typealias Properties = XISFImageProperties

    /// Enumerates the file's images, in file order.
    ///
    /// - Parameter container: The parsed XISF file.
    /// - Returns: One frame per image.
    /// - Throws: ``Error`` when the file holds no image.
    public static func frames( in container: XISFFile ) throws -> [ XISFImageFrame ]
    {
        throw self.unimplemented( "frames( in: )" )
    }

    /// The image's pixel bytes, decompressed if the data block was compressed,
    /// paired with the layout describing them.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The bytes and their layout.
    /// - Throws: ``Error`` when the data block cannot be read.
    public static func contents( of frame: XISFImageFrame ) throws -> ( bytes: Data, properties: XISFImageProperties )
    {
        throw self.unimplemented( "contents( of: )" )
    }

    /// Decodes the bytes into linear samples, reading them in the layout's sample
    /// format and byte order.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: The geometry and linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: XISFImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// Decodes the bytes into one plane per channel, honouring the layout's planar
    /// or interleaved pixel storage.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: One plane per channel.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    public static func planeSamples( bytes: Data, properties: XISFImageProperties ) throws -> [ [ Double ] ]
    {
        throw self.unimplemented( "planeSamples( bytes:properties: )" )
    }

    /// Combines decoded planes into one linear luminance channel, as their
    /// per-pixel mean.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The image's layout.
    /// - Returns: The geometry and luminance samples, or `nil`.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: XISFImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// The identity transform: XISF stores its samples at their physical values,
    /// with no format-level affine scaling to undo.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: XISFImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 0, offset: 0 )
    }

    /// The span of the layout's sample format — `2ⁿ − 1` for the unsigned integer
    /// formats — deliberately matching the FITS convention so the two paths agree.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The full-scale value, or `nil` for a floating-point or complex
    ///   sample format.
    public static func fullScale( from properties: XISFImageProperties ) -> Double?
    {
        nil
    }

    /// The closest ``BitsPerPixel`` label for the layout's sample format.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The sample format label, or `nil` when it has no representable
    ///   equivalent.
    public static func bitsPerPixel( from properties: XISFImageProperties ) -> BitsPerPixel?
    {
        nil
    }

    /// The layout's colour-filter-array pattern, through the shared
    /// ``ColorFilterArray`` mapping.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The pattern, or `nil` when the image carries no colour-filter
    ///   array.
    /// - Throws: ``Error`` when the layout names an unsupported pattern.
    public static func cfaPattern( from properties: XISFImageProperties ) throws -> Processors.Debayer.Pattern?
    {
        throw self.unimplemented( "cfaPattern( from: )" )
    }

    /// The layout's spatial dimensions.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: XISFImageProperties ) -> ( width: Int, height: Int )?
    {
        nil
    }

    /// The layout's channel count: `3` for RGB, `1` for grayscale or a
    /// colour-filter-array mosaic.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: XISFImageProperties ) -> Int
    {
        0
    }

    /// Decodes the single sample stored at a byte index, in the layout's sample
    /// format and byte order.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - index:      The sample's index into `bytes`.
    ///   - properties: The image's layout.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: XISFImageProperties ) -> Double?
    {
        nil
    }

    /// The byte indices covering an image coordinate, one per channel, following
    /// the layout's planar or interleaved storage.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column.
    ///   - y:          The zero-based row.
    ///   - properties: The image's layout.
    /// - Returns: One index per channel, or `nil`.
    public static func sampleByteOffsets( x: Int, y: Int, properties: XISFImageProperties ) -> [ Data.Index ]?
    {
        nil
    }

    /// The detection image: the frame's linear luminance, demosaiced to luminance
    /// when the layout names a colour-filter-array pattern.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: XISFImageProperties ) -> PixelBuffer?
    {
        nil
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: XISFImageFrame ) throws -> PixelBuffer
    {
        throw self.unimplemented( "detectionImage( of: )" )
    }
}
