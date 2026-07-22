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
import ImageIO
import SwiftPixel

/// The photographic implementation of ``ImageDecoding``: the canonical bitmap
/// draw, its sample decoding and the detection image, for JPEG, PNG, TIFF and
/// HEIC.
///
/// The draw is the reason this decoder exists rather than stopping at the
/// container. Drawing a `CGImage` into a bitmap context is what fixes the byte
/// layout every later operation reads — the colour model, the component width,
/// the skipped padding component, the byte order — so a consumer drawing its own
/// bitmap would be decoding different bytes. It moves on the same test as every
/// other row: it can change the detection image.
///
/// That the draw needs ImageIO and Core Graphics costs nothing here: both are
/// system frameworks on a platform this library already requires. They are an
/// implementation detail of this one decoder, not a concept the shared API
/// exposes.
///
/// - Note: The operations below are declared, documented and reachable, but their
///   bodies have not landed yet. Each throws or answers `nil` until the
///   photographic migration fills it in.
public enum BitmapImageDecoder: ImageDecoding
{
    /// An opened image source. Opening it is the consumer's job.
    public typealias Container = CGImageSource

    /// One image within the source.
    public typealias Frame = BitmapImageFrame

    /// The drawn bitmap's layout.
    public typealias Properties = BitmapImageProperties

    /// Enumerates the source's images, in container order, reading each frame's
    /// EXIF orientation as it goes.
    ///
    /// - Parameter container: The opened image source.
    /// - Returns: One frame per image.
    /// - Throws: ``Error`` when the source holds no image.
    public static func frames( in container: CGImageSource ) throws -> [ BitmapImageFrame ]
    {
        throw self.unimplemented( "frames( in: )" )
    }

    /// The frame brought upright by its EXIF orientation and drawn into the
    /// canonical interleaved bitmap, paired with the layout describing it.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The drawn bytes and their layout.
    /// - Throws: ``Error`` when the frame cannot be decoded or drawn.
    public static func contents( of frame: BitmapImageFrame ) throws -> ( bytes: Data, properties: BitmapImageProperties )
    {
        throw self.unimplemented( "contents( of: )" )
    }

    /// Decodes the drawn bytes into linear samples, reading the interleaved layout
    /// and skipping the padding component a colour bitmap carries.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The geometry and linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: BitmapImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// Decodes the drawn bytes into one plane per meaningful channel — three for
    /// colour, one for grayscale — skipping the padding component.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: One plane per channel.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    public static func planeSamples( bytes: Data, properties: BitmapImageProperties ) throws -> [ [ Double ] ]
    {
        throw self.unimplemented( "planeSamples( bytes:properties: )" )
    }

    /// Combines decoded planes into one linear luminance channel, as their
    /// per-pixel mean.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The geometry and luminance samples, or `nil`.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: BitmapImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        nil
    }

    /// The identity transform: a drawn bitmap's components are already their
    /// stored values.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: BitmapImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 0, offset: 0 )
    }

    /// The span of the component width: `255` for an 8-bit bitmap, `65535` for a
    /// 16-bit one.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The full-scale value.
    public static func fullScale( from properties: BitmapImageProperties ) -> Double?
    {
        nil
    }

    /// The sample format of the drawn components.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The sample format.
    public static func bitsPerPixel( from properties: BitmapImageProperties ) -> BitsPerPixel?
    {
        nil
    }

    /// `nil`, always — a photographic frame never carries a colour-filter array.
    ///
    /// The uniform answer that keeps the surface whole: the member is present and
    /// answers "none", rather than being absent and forcing a caller to know which
    /// formats have one.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: `nil`.
    /// - Throws: Never; the signature matches every other format's.
    public static func cfaPattern( from properties: BitmapImageProperties ) throws -> Processors.Debayer.Pattern?
    {
        throw self.unimplemented( "cfaPattern( from: )" )
    }

    /// The bitmap's dimensions, after the orientation transform.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: BitmapImageProperties ) -> ( width: Int, height: Int )?
    {
        nil
    }

    /// The bitmap's meaningful channel count: `3` for colour, `1` for grayscale.
    /// The padding component a colour bitmap stores is not a channel.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: BitmapImageProperties ) -> Int
    {
        0
    }

    /// Decodes the single component stored at a byte index.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - index:      The component's index into `bytes`.
    ///   - properties: The bitmap's layout.
    /// - Returns: The stored value, or `nil` when a whole component does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: BitmapImageProperties ) -> Double?
    {
        nil
    }

    /// The byte indices covering an image coordinate, one per meaningful channel,
    /// skipping the padding component.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column.
    ///   - y:          The zero-based row.
    ///   - properties: The bitmap's layout.
    /// - Returns: One index per channel, or `nil`.
    public static func sampleByteOffsets( x: Int, y: Int, properties: BitmapImageProperties ) -> [ Data.Index ]?
    {
        nil
    }

    /// The detection image: the frame's linear luminance. There is no demosaic
    /// branch — a photographic frame is never a mosaic.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: BitmapImageProperties ) -> PixelBuffer?
    {
        nil
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: BitmapImageFrame ) throws -> PixelBuffer
    {
        throw self.unimplemented( "detectionImage( of: )" )
    }
}
