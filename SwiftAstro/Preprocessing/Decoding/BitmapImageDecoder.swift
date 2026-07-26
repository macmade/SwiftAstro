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

import CoreGraphics
import CoreImage
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
    /// The orientation is read here — alongside the frame's other container-level
    /// properties — rather than at draw time, so enumerating a multi-frame
    /// container's frames does not pay to decode every one of them. A frame with no
    /// orientation defaults to `1`, the no-transform case.
    ///
    /// - Parameter container: The opened image source.
    /// - Returns: One frame per image.
    /// - Throws: ``Error`` when the source holds no image.
    public static func frames( in container: CGImageSource ) throws -> [ BitmapImageFrame ]
    {
        let count = CGImageSourceGetCount( container )

        guard count > 0
        else
        {
            throw Error( message: "The image source holds no image." )
        }

        return ( 0 ..< count ).map
        {
            index in

            let properties  = CGImageSourceCopyPropertiesAtIndex( container, index, nil ) as? [ String: Any ] ?? [ : ]
            let orientation = ( properties[ kCGImagePropertyOrientation as String ] as? NSNumber )?.intValue ?? 1

            return BitmapImageFrame( source: container, index: index, orientation: orientation )
        }
    }

    /// The frame brought upright by its EXIF orientation and drawn into the
    /// canonical interleaved bitmap, paired with the layout describing it.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The drawn bytes and their layout.
    /// - Throws: ``Error`` when the frame cannot be decoded or drawn.
    public static func contents( of frame: BitmapImageFrame ) throws -> ( bytes: Data, properties: BitmapImageProperties )
    {
        guard let cgImage = CGImageSourceCreateImageAtIndex( frame.source, frame.index, nil )
        else
        {
            throw Error( message: "The image could not be decoded." )
        }

        return try self.draw( cgImage, orientation: frame.orientation )
    }

    /// Decodes the drawn bytes into linear samples — the frame's per-pixel luminance,
    /// the equal-weight mean of its meaningful channels — the domain the detection
    /// image is built in and the domain a consumer renders from.
    ///
    /// A photographic image is display-encoded, so these samples are the stored
    /// (gamma-encoded) values, not scene-linear ones; "linear" here means unstretched
    /// and undemosaiced, the same sense the other formats use.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The geometry and linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: BitmapImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        guard let planes = try? self.planeSamples( bytes: bytes, properties: properties )
        else
        {
            return nil
        }

        return self.linearLuminance( fromPlanes: planes, properties: properties )
    }

    /// Decodes the drawn bytes into one plane per meaningful channel — three for
    /// colour, one for grayscale — reading the interleaved layout and skipping the
    /// padding component a colour bitmap carries.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: One plane per channel.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    public static func planeSamples( bytes: Data, properties: BitmapImageProperties ) throws -> [ [ Double ] ]
    {
        guard properties.width > 0, properties.height > 0, properties.channelCount > 0,
              properties.componentsPerPixel >= properties.channelCount, properties.bytesPerComponent > 0
        else
        {
            throw Error( message: "Invalid photographic image geometry: \( properties.width ) × \( properties.height ) × \( properties.channelCount )." )
        }

        let pixelCount    = properties.width * properties.height
        let bytesPerPixel = properties.componentsPerPixel * properties.bytesPerComponent
        let required      = pixelCount * bytesPerPixel
        let data          = Data( bytes.prefix( required ) ) // re-wrap: startIndex may be non-zero, and trim trailing bytes

        guard data.count == required
        else
        {
            throw Error( message: "Photographic pixel data too small: \( bytes.count ) < \( required )." )
        }

        return data.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) -> [ [ Double ] ] in

            ( 0 ..< properties.channelCount ).map
            {
                channel in ( 0 ..< pixelCount ).map
                {
                    pixel in self.sample( raw, at: ( pixel * properties.componentsPerPixel + channel ) * properties.bytesPerComponent, bytesPerComponent: properties.bytesPerComponent )
                }
            }
        }
    }

    /// Combines decoded planes into one linear luminance channel, as their per-pixel
    /// equal-weight mean. A grayscale image's single plane is that plane, unchanged.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The geometry and luminance samples, or `nil` when the planes are
    ///   empty or of unequal length.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: BitmapImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        guard let first = planes.first, planes.allSatisfy( { $0.count == first.count } )
        else
        {
            return nil
        }

        let count   = Double( planes.count )
        let samples = ( 0 ..< first.count ).map
        {
            index -> Double in

            let sum = planes.reduce( 0.0 ) { $0 + $1[ index ] }

            return sum / count
        }

        return ( width: properties.width, height: properties.height, samples: samples )
    }

    /// The identity transform: a drawn bitmap's components are already their
    /// stored values.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: BitmapImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 1, offset: 0 )
    }

    /// The span of the component width: `255` for an 8-bit bitmap, `65535` for a
    /// 16-bit one.
    ///
    /// A drawn bitmap is an integer format with a fixed span — the value the
    /// per-pixel read-out expresses as a `0...1` fraction and the render scales the
    /// samples into `[0, 1]` by — so, unlike a floating-point format, it is never
    /// `nil`.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The full-scale value.
    public static func fullScale( from properties: BitmapImageProperties ) -> Double?
    {
        properties.fullScale
    }

    /// The sample format of the drawn components: `.uint8` for an 8-bit bitmap,
    /// `.int16` for a 16-bit one — the label the plane render already used.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The sample format.
    public static func bitsPerPixel( from properties: BitmapImageProperties ) -> BitsPerPixel?
    {
        properties.bytesPerComponent >= 2 ? .int16 : .uint8
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
        nil
    }

    /// The bitmap's dimensions, after the orientation transform.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: BitmapImageProperties ) -> ( width: Int, height: Int )?
    {
        guard properties.width > 0, properties.height > 0
        else
        {
            return nil
        }

        return ( properties.width, properties.height )
    }

    /// The bitmap's meaningful channel count: `3` for colour, `1` for grayscale.
    /// The padding component a colour bitmap stores is not a channel.
    ///
    /// - Parameter properties: The bitmap's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: BitmapImageProperties ) -> Int
    {
        properties.channelCount
    }

    /// Decodes the single component stored at a byte index, in host byte order — the
    /// order the loader drew the bitmap into.
    ///
    /// Bounds-checked against the bytes' own index range rather than trapping, so a
    /// read-out over a truncated frame answers `nil`.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - index:      The component's index into `bytes`, in `bytes`' own index space.
    ///   - properties: The bitmap's layout.
    /// - Returns: The stored value, or `nil` when a whole component does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: BitmapImageProperties ) -> Double?
    {
        let bytesPerComponent = properties.bytesPerComponent

        guard bytesPerComponent > 0, index >= bytes.startIndex, index + bytesPerComponent <= bytes.endIndex
        else
        {
            return nil
        }

        let offset = index - bytes.startIndex

        return bytes.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) in self.sample( raw, at: offset, bytesPerComponent: bytesPerComponent )
        }
    }

    /// The byte indices covering an image coordinate, one per meaningful channel,
    /// skipping the padding component. The indices are zero-based offsets into a
    /// frame's bytes; a caller reading a `Data` whose start index is non-zero adds
    /// that start index before ``decodeSample(bytes:at:properties:)``.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column, left to right.
    ///   - y:          The zero-based row, top to bottom.
    ///   - properties: The bitmap's layout.
    /// - Returns: One index per channel, or `nil` for an invalid geometry or
    ///   out-of-bounds coordinates.
    public static func sampleByteOffsets( x: Int, y: Int, properties: BitmapImageProperties ) -> [ Data.Index ]?
    {
        guard properties.width > 0, properties.height > 0, properties.channelCount > 0,
              properties.componentsPerPixel >= properties.channelCount, properties.bytesPerComponent > 0,
              x >= 0, x < properties.width, y >= 0, y < properties.height
        else
        {
            return nil
        }

        let pixelIndex = y * properties.width + x

        return ( 0 ..< properties.channelCount ).map
        {
            channel in ( pixelIndex * properties.componentsPerPixel + channel ) * properties.bytesPerComponent
        }
    }

    /// The detection image: the frame's linear luminance. There is no demosaic
    /// branch — a photographic frame is never a mosaic.
    ///
    /// Best-effort by design — any failure returns `nil` so a consumer skips
    /// detection rather than failing to open the image.
    ///
    /// - Parameters:
    ///   - bytes:      The drawn bitmap bytes.
    ///   - properties: The bitmap's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: BitmapImageProperties ) -> PixelBuffer?
    {
        guard let luminance = self.linearImage( bytes: bytes, properties: properties )
        else
        {
            return nil
        }

        return try? PixelBuffer( width: luminance.width, height: luminance.height, channels: 1, pixels: luminance.samples, isNormalized: false )
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: BitmapImageFrame ) throws -> PixelBuffer
    {
        let ( bytes, properties ) = try self.contents( of: frame )

        guard let image = self.detectionImage( bytes: bytes, properties: properties )
        else
        {
            throw Error( message: "Photographic frame has no usable detection image" )
        }

        return image
    }

    // MARK: - Drawing and sample decoding

    /// Brings a decoded `CGImage` upright per its EXIF orientation, draws it into a
    /// canonical, tightly-packed bitmap and captures the layout describing the bytes.
    ///
    /// A grayscale image is drawn as a single channel; any other colour model is
    /// drawn as `RGBX` in the sRGB space (the fourth component is unused padding
    /// CoreGraphics requires). A source deeper than 8 bits per component is preserved
    /// at 16 bits, stored little-endian to match the host byte order the sample
    /// decode reads. Alpha is not composited — the raw colour components are taken —
    /// so an opaque image (the common case) is reproduced exactly.
    ///
    /// - Parameters:
    ///   - cgImage:     The decoded image, in its stored pixel orientation.
    ///   - orientation: The frame's EXIF orientation (`1`...`8`); the image is rotated
    ///                  or flipped upright before it is drawn, so a portrait phone
    ///                  photo is decoded the right way up.
    /// - Returns: The drawn bytes and the layout describing them.
    /// - Throws: ``Error`` for invalid dimensions or a bitmap context that cannot be
    ///   created.
    private static func draw( _ cgImage: CGImage, orientation: Int ) throws -> ( bytes: Data, properties: BitmapImageProperties )
    {
        let image  = self.upright( cgImage, orientation: orientation )
        let width  = image.width
        let height = image.height

        guard width > 0, height > 0
        else
        {
            throw Error( message: "Invalid image dimensions: \( width ) × \( height )." )
        }

        let isColor            = ( image.colorSpace?.model ?? .rgb ) != .monochrome
        let bytesPerComponent  = image.bitsPerComponent > 8 ? 2 : 1
        let channelCount       = isColor ? 3 : 1
        let componentsPerPixel = isColor ? 4 : 1
        let bitsPerComponent   = bytesPerComponent * 8
        let bytesPerRow        = width * componentsPerPixel * bytesPerComponent
        let colorSpace         = isColor ? ( CGColorSpace( name: CGColorSpace.sRGB ) ?? CGColorSpaceCreateDeviceRGB() ) : CGColorSpaceCreateDeviceGray()
        var bitmapInfo         = ( isColor ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.none ).rawValue

        if bytesPerComponent >= 2
        {
            bitmapInfo |= CGBitmapInfo.byteOrder16Little.rawValue
        }

        var buffer = [ UInt8 ]( repeating: 0, count: bytesPerRow * height )
        let drew   = buffer.withUnsafeMutableBytes
        {
            ( raw: UnsafeMutableRawBufferPointer ) -> Bool in

            guard let base = raw.baseAddress,
                  let context = CGContext( data: base, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo )
            else
            {
                return false
            }

            context.draw( image, in: CGRect( x: 0, y: 0, width: width, height: height ) )

            return true
        }

        guard drew
        else
        {
            throw Error( message: "The image could not be drawn into a bitmap context." )
        }

        let properties = BitmapImageProperties( width: width, height: height, channelCount: channelCount, componentsPerPixel: componentsPerPixel, bytesPerComponent: bytesPerComponent )

        return ( Data( buffer ), properties )
    }

    /// Returns the image rotated/flipped upright per its EXIF orientation, so a
    /// portrait phone photo (a non-`1` orientation, common in HEIC and JPEG) is
    /// decoded the right way up rather than sideways.
    ///
    /// An orientation of `1` (the default and overwhelmingly common case) is returned
    /// unchanged, so ordinary images take the exact same path as before. Any other
    /// orientation is applied via Core Image's canonical `oriented(forExifOrientation:)`,
    /// preserving the source's bit depth (a deeper-than-8-bit source stays 16-bit). If
    /// the transform cannot be rendered, the original image is returned unchanged.
    ///
    /// - Parameters:
    ///   - cgImage:     The decoded image, in its stored pixel orientation.
    ///   - orientation: The EXIF orientation (`1`...`8`).
    /// - Returns: The uprighted image, or `cgImage` when no transform applies.
    private static func upright( _ cgImage: CGImage, orientation: Int ) -> CGImage
    {
        guard ( 2 ... 8 ).contains( orientation )
        else
        {
            return cgImage
        }

        let oriented   = CIImage( cgImage: cgImage ).oriented( forExifOrientation: Int32( orientation ) )
        let colorSpace = cgImage.colorSpace ?? ( CGColorSpace( name: CGColorSpace.sRGB ) ?? CGColorSpaceCreateDeviceRGB() )
        let format     = cgImage.bitsPerComponent > 8 ? CIFormat.RGBA16 : CIFormat.RGBA8

        guard let uprighted = CIContext().createCGImage( oriented, from: oriented.extent, format: format, colorSpace: colorSpace )
        else
        {
            return cgImage
        }

        return uprighted
    }

    /// Decodes a single component from a raw byte buffer at a byte offset, in host
    /// byte order — the order the loader drew the bitmap into.
    ///
    /// - Parameters:
    ///   - raw:               The byte buffer.
    ///   - offset:            The component's byte offset into the buffer.
    ///   - bytesPerComponent: The number of bytes per component (`1` or `2`).
    /// - Returns: The decoded value.
    private static func sample( _ raw: UnsafeRawBufferPointer, at offset: Int, bytesPerComponent: Int ) -> Double
    {
        if bytesPerComponent >= 2
        {
            return Double( raw.loadUnaligned( fromByteOffset: offset, as: UInt16.self ) )
        }

        return Double( raw.load( fromByteOffset: offset, as: UInt8.self ) )
    }
}
