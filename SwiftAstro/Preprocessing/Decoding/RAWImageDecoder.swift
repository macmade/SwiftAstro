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
import SwiftRAW

/// The camera RAW implementation of ``ImageDecoding``: the crop to the visible
/// sensor mosaic, its sample decoding and the detection image.
///
/// This is where the "does it change the bytes" test bites hardest. The crop that
/// drops the optical-black margins also sets the mosaic's Bayer phase — the
/// colour-filter-array pattern is derived *at the crop origin* — so a consumer
/// that cropped even slightly differently would demosaic on the wrong phase and
/// validate a detector against an image nothing else ever sees. The crop and the
/// pattern therefore come from the same code, here.
///
/// - Note: The operations below are declared, documented and reachable, but their
///   bodies have not landed yet. Each throws or answers `nil` until the RAW
///   migration fills it in.
public enum RAWImageDecoder: ImageDecoding
{
    /// An opened, unpacked RAW file. Opening and unpacking it is the consumer's
    /// job.
    public typealias Container = RAWFile

    /// The file's single sensor mosaic.
    public typealias Frame = RAWImageFrame

    /// The cropped mosaic's layout.
    public typealias Properties = RAWImageProperties

    /// Enumerates the file's images — always exactly one.
    ///
    /// The uniform answer, not an omitted operation: a caller enumerating frames
    /// need not know this format can hold only one.
    ///
    /// - Parameter container: The opened, unpacked RAW file.
    /// - Returns: Exactly one frame.
    /// - Throws: ``Error`` when the sensor holds nothing this decoder can read —
    ///   a non-Bayer layout, or an X-Trans mosaic no 2 × 2 pattern describes.
    public static func frames( in container: RAWFile ) throws -> [ RAWImageFrame ]
    {
        throw self.unimplemented( "frames( in: )" )
    }

    /// The sensor mosaic cropped to the visible area, tightly packed in host byte
    /// order, paired with the layout describing it — including the
    /// colour-filter-array pattern taken at the crop origin.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The cropped mosaic bytes and their layout.
    /// - Throws: ``Error`` for an invalid geometry, or a sensor buffer too small
    ///   to hold the visible area.
    public static func contents( of frame: RAWImageFrame ) throws -> ( bytes: Data, properties: RAWImageProperties )
    {
        throw self.unimplemented( "contents( of: )" )
    }

    /// Decodes the cropped mosaic into linear samples — 16-bit sensor values in
    /// host byte order.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The geometry and linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: RAWImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// Decodes the cropped mosaic into planes — always exactly one, because a
    /// sensor mosaic is a single channel until it is demosaiced.
    ///
    /// Another uniform answer: one plane, not a missing operation.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: Exactly one plane.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    public static func planeSamples( bytes: Data, properties: RAWImageProperties ) throws -> [ [ Double ] ]
    {
        throw self.unimplemented( "planeSamples( bytes:properties: )" )
    }

    /// Combines decoded planes into one linear luminance channel. With a single
    /// plane this is that plane.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The geometry and luminance samples, or `nil`.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: RAWImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// The identity transform: sensor counts are already the physical values.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: RAWImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 0, offset: 0 )
    }

    /// The sensor's saturation level — its span, in the same sense as the FITS and
    /// XISF formats' `2ⁿ − 1`, but reported by the sensor rather than implied by
    /// the sample width (a 14-bit sensor stored in 16 bits saturates at `16383`).
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The white level, or `nil` when the sensor reports none.
    public static func fullScale( from properties: RAWImageProperties ) -> Double?
    {
        nil
    }

    /// The sample format of the cropped mosaic — 16-bit samples, always.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The sample format.
    public static func bitsPerPixel( from properties: RAWImageProperties ) -> BitsPerPixel?
    {
        nil
    }

    /// The mosaic's colour-filter-array pattern *at the crop origin*, through the
    /// shared ``ColorFilterArray`` mapping.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The pattern, or `nil` for a monochrome sensor.
    /// - Throws: ``Error`` when the sensor names an unsupported pattern.
    public static func cfaPattern( from properties: RAWImageProperties ) throws -> Processors.Debayer.Pattern?
    {
        throw self.unimplemented( "cfaPattern( from: )" )
    }

    /// The visible mosaic's dimensions, margins already removed.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: RAWImageProperties ) -> ( width: Int, height: Int )?
    {
        nil
    }

    /// `1` — a sensor mosaic is a single channel, colour-filter array or not.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: RAWImageProperties ) -> Int
    {
        0
    }

    /// Decodes the single 16-bit sample stored at a byte index.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - index:      The sample's index into `bytes`.
    ///   - properties: The mosaic's layout.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: RAWImageProperties ) -> Double?
    {
        nil
    }

    /// The byte index covering an image coordinate — one, for the single channel.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column.
    ///   - y:          The zero-based row.
    ///   - properties: The mosaic's layout.
    /// - Returns: One index, or `nil`.
    public static func sampleByteOffsets( x: Int, y: Int, properties: RAWImageProperties ) -> [ Data.Index ]?
    {
        nil
    }

    /// The detection image: the mosaic's linear channel, demosaiced to luminance
    /// when the sensor carries a colour-filter array.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: RAWImageProperties ) -> PixelBuffer?
    {
        nil
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: RAWImageFrame ) throws -> PixelBuffer
    {
        throw self.unimplemented( "detectionImage( of: )" )
    }
}
