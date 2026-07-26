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
/// pattern therefore come from the same code: ``contents(of:)`` produces the cropped
/// bytes and the layout (via ``RAWImageProperties/init(file:)``) together.
///
/// A RAW file holds exactly one sensor mosaic, and it is a single channel — a
/// colour-filter array or not — until it is demosaiced, so ``frames(in:)`` answers
/// with exactly one frame and ``planeSamples(bytes:properties:)`` with exactly one
/// plane. Those are uniform answers, not omitted operations.
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
    /// need not know this format can hold only one. This is also where "does the
    /// sensor hold decodable bytes at all" is decided — a non-Bayer sensor layout or
    /// an X-Trans mosaic (which no 2 × 2 Bayer pattern describes) throws here rather
    /// than yielding a frame whose ``contents(of:)`` would fail, so a caller learns
    /// there is nothing to decode at enumeration time.
    ///
    /// - Parameter container: The opened, unpacked RAW file.
    /// - Returns: Exactly one frame.
    /// - Throws: ``Error`` when the sensor holds nothing this decoder can read —
    ///   a non-Bayer layout, or an X-Trans mosaic no 2 × 2 pattern describes.
    public static func frames( in container: RAWFile ) throws -> [ RAWImageFrame ]
    {
        guard container.sensorData.layout == .bayer
        else
        {
            throw Error( message: "Unsupported RAW sensor layout: \( container.sensorData.layout ). Only a 16-bit Bayer/monochrome mosaic can be decoded." )
        }

        guard container.cfaPattern.kind != .xTrans
        else
        {
            throw Error( message: "X-Trans RAW sensors are not supported." )
        }

        return [ RAWImageFrame( file: container ) ]
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
        let properties = RAWImageProperties( file: frame.file )

        guard let bytes = self.croppedMosaic( file: frame.file, sizes: frame.file.imageSizes )
        else
        {
            throw Error( message: "The RAW sensor mosaic could not be read." )
        }

        return ( bytes, properties )
    }

    /// Decodes the cropped mosaic into linear samples — 16-bit sensor values in
    /// host byte order, one channel, at the image geometry.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The geometry and linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: RAWImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        guard let samples = try? self.decodeSamples( bytes: bytes, properties: properties )
        else
        {
            return nil
        }

        return ( width: properties.width, height: properties.height, samples: samples )
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
        [ try self.decodeSamples( bytes: bytes, properties: properties ) ]
    }

    /// Combines decoded planes into one linear luminance channel, as their per-pixel
    /// equal-weight mean. With a single plane — always, for RAW — this is that plane.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The geometry and luminance samples, or `nil` when the planes are
    ///   empty or of unequal length.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: RAWImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
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

    /// The identity transform: sensor counts are already the physical values.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: RAWImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 1, offset: 0 )
    }

    /// The sensor's saturation level — its span, in the same sense as the FITS and
    /// XISF formats' `2ⁿ − 1`, but reported by the sensor rather than implied by
    /// the sample width (a 14-bit sensor stored in 16 bits saturates at `16383`).
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The white level, or `nil` when the sensor reports none.
    public static func fullScale( from properties: RAWImageProperties ) -> Double?
    {
        properties.whiteLevel
    }

    /// The sample format of the cropped mosaic — 16-bit samples, always.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The sample format.
    public static func bitsPerPixel( from properties: RAWImageProperties ) -> BitsPerPixel?
    {
        .int16
    }

    /// The mosaic's colour-filter-array pattern *at the crop origin*, through the
    /// shared ``ColorFilterArray`` mapping.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The pattern, or `nil` for a monochrome sensor.
    /// - Throws: ``Error`` when the sensor names an unsupported pattern.
    public static func cfaPattern( from properties: RAWImageProperties ) throws -> Processors.Debayer.Pattern?
    {
        guard let name = properties.colorFilterArrayPattern
        else
        {
            return nil
        }

        return try ColorFilterArray.pattern( named: name )
    }

    /// The visible mosaic's dimensions, margins already removed.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: RAWImageProperties ) -> ( width: Int, height: Int )?
    {
        guard properties.width > 0, properties.height > 0
        else
        {
            return nil
        }

        return ( properties.width, properties.height )
    }

    /// `1` — a sensor mosaic is a single channel, colour-filter array or not.
    ///
    /// - Parameter properties: The mosaic's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: RAWImageProperties ) -> Int
    {
        1
    }

    /// Decodes the single 16-bit sample stored at a byte index, in host byte order.
    ///
    /// Bounds-checked against the bytes' own index range rather than trapping, so a
    /// read-out over a truncated frame answers `nil`.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - index:      The sample's index into `bytes`, in `bytes`' own index space.
    ///   - properties: The mosaic's layout.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: RAWImageProperties ) -> Double?
    {
        let bytesPerSample = MemoryLayout< UInt16 >.size

        guard index >= bytes.startIndex, index + bytesPerSample <= bytes.endIndex
        else
        {
            return nil
        }

        let offset = index - bytes.startIndex

        return bytes.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) in Double( raw.loadUnaligned( fromByteOffset: offset, as: UInt16.self ) )
        }
    }

    /// The byte index covering an image coordinate — one, for the single channel.
    /// The index is a zero-based offset into a frame's bytes; a caller reading a
    /// `Data` whose start index is non-zero adds that start index before
    /// ``decodeSample(bytes:at:properties:)``.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column, left to right.
    ///   - y:          The zero-based row, top to bottom.
    ///   - properties: The mosaic's layout.
    /// - Returns: One index, or `nil` for an invalid geometry or out-of-bounds
    ///   coordinates.
    public static func sampleByteOffsets( x: Int, y: Int, properties: RAWImageProperties ) -> [ Data.Index ]?
    {
        guard properties.width > 0, properties.height > 0,
              x >= 0, x < properties.width, y >= 0, y < properties.height
        else
        {
            return nil
        }

        return [ ( y * properties.width + x ) * MemoryLayout< UInt16 >.size ]
    }

    /// The detection image: the mosaic's linear channel, demosaiced to luminance
    /// when the sensor carries a colour-filter array.
    ///
    /// A monochrome sensor is already a single luminance channel and is used
    /// directly; a colour-filter-array mosaic is demosaiced (feeding a raw mosaic to
    /// the detector would inject the Bayer grid as false structure). Best-effort by
    /// design — any failure returns `nil` so a consumer skips detection rather than
    /// failing to open the image.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: RAWImageProperties ) -> PixelBuffer?
    {
        guard let linear = self.linearImage( bytes: bytes, properties: properties ),
              let buffer = try? PixelBuffer( width: linear.width, height: linear.height, channels: 1, pixels: linear.samples, isNormalized: false )
        else
        {
            return nil
        }

        // cfaPattern(from:) returns nil for a monochrome sensor and throws on an
        // unsupported pattern; both fall back to the single mosaic channel.
        guard let pattern = ( try? self.cfaPattern( from: properties ) ) ?? nil
        else
        {
            return buffer
        }

        return ( try? BayerGrayscaleConverter( pattern: pattern ).grayscale( from: buffer ) ) ?? buffer
    }

    /// The detection image for a frame, end to end.
    ///
    /// - Parameter frame: The frame to decode.
    /// - Returns: The detection image.
    /// - Throws: ``Error`` when it cannot be built.
    public static func detectionImage( of frame: RAWImageFrame ) throws -> PixelBuffer
    {
        let ( bytes, properties ) = try self.contents( of: frame )

        guard let image = self.detectionImage( bytes: bytes, properties: properties )
        else
        {
            throw Error( message: "RAW frame has no usable detection image" )
        }

        return image
    }

    // MARK: - Cropping and sample decoding

    /// Crops the sensor's full 16-bit Bayer buffer to the visible area, dropping the
    /// optical-black margins, into a tightly-packed row-major mosaic in host byte
    /// order.
    ///
    /// - Parameters:
    ///   - file:  The unpacked RAW file.
    ///   - sizes: The image geometry (visible dimensions, margins, and row pitch).
    /// - Returns: The cropped mosaic bytes, or `nil` for an invalid geometry or a
    ///   buffer too small to hold the visible area.
    private static func croppedMosaic( file: RAWFile, sizes: RAWImageSizes ) -> Data?
    {
        let width         = sizes.width
        let height        = sizes.height
        let samplesPerRow = sizes.rawPitch / 2

        guard width > 0, height > 0, sizes.leftMargin >= 0, sizes.topMargin >= 0, samplesPerRow >= sizes.leftMargin + width
        else
        {
            return nil
        }

        // The vertical bound is enforced against the real buffer length below, once
        // the zero-copy sensor buffer is in scope.

        return file.withRawImage
        {
            ( buffer: UnsafeBufferPointer< UInt16 > ) -> Data? in

            let lastSample = ( sizes.topMargin + height - 1 ) * samplesPerRow + sizes.leftMargin + width

            guard lastSample <= buffer.count, let base = buffer.baseAddress
            else
            {
                return nil
            }

            var mosaic = [ UInt16 ]()

            mosaic.reserveCapacity( width * height )

            ( 0 ..< height ).forEach
            {
                row in

                let start = ( sizes.topMargin + row ) * samplesPerRow + sizes.leftMargin

                mosaic.append( contentsOf: UnsafeBufferPointer( start: base + start, count: width ) )
            }

            return mosaic.withUnsafeBytes { Data( $0 ) }
        } ?? nil
    }

    /// Decodes the cropped mosaic's bytes into raw sample values, in host byte order.
    ///
    /// The mosaic bytes are produced and consumed in-process (``croppedMosaic(file:sizes:)``
    /// crops the sensor buffer), so they carry the host byte order and need no
    /// endianness swap.
    ///
    /// - Parameters:
    ///   - bytes:      The cropped mosaic bytes.
    ///   - properties: The mosaic's layout.
    /// - Returns: The `width × height` samples, in row-major order.
    /// - Throws: ``Error`` for an invalid geometry or truncated bytes.
    private static func decodeSamples( bytes: Data, properties: RAWImageProperties ) throws -> [ Double ]
    {
        guard properties.width > 0, properties.height > 0
        else
        {
            throw Error( message: "Invalid RAW image geometry: \( properties.width ) × \( properties.height )" )
        }

        let count    = properties.width * properties.height
        let required = count * MemoryLayout< UInt16 >.size
        let data     = Data( bytes.prefix( required ) ) // re-wrap: startIndex may be non-zero, and trim trailing bytes

        guard data.count == required
        else
        {
            throw Error( message: "RAW pixel data too small: \( bytes.count ) < \( required )" )
        }

        return data.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) -> [ Double ] in

            ( 0 ..< count ).map
            {
                Double( raw.loadUnaligned( fromByteOffset: $0 * MemoryLayout< UInt16 >.size, as: UInt16.self ) )
            }
        }
    }
}
