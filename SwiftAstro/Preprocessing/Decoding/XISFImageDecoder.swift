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
/// XISF stores physical values, so ``scaling(from:)`` is the identity and there is
/// no format-level affine transform to undo. ``linearImage(bytes:properties:)`` is
/// consequently the frame's equal-weight luminance — the single channel of a
/// grayscale frame, and the per-pixel mean of a colour frame — which is exactly the
/// domain the detection image and the render statistics work in.
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
        guard container.images.isEmpty == false
        else
        {
            throw Error( message: "XISF file contains no image" )
        }

        return container.images.map { XISFImageFrame( image: $0 ) }
    }

    /// The image's pixel bytes, decompressed if the data block was compressed,
    /// paired with the layout describing them.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The bytes and their layout.
    /// - Throws: ``Error`` when the data block cannot be read.
    public static func contents( of frame: XISFImageFrame ) throws -> ( bytes: Data, properties: XISFImageProperties )
    {
        ( bytes: try frame.image.data, properties: XISFImageProperties( image: frame.image ) )
    }

    /// Decodes the bytes into linear samples: the frame's equal-weight luminance,
    /// which is the single channel of a grayscale (or colour-filter-array) frame and
    /// the per-pixel mean of a colour frame.
    ///
    /// XISF stores physical values, so no affine scaling is undone; the mean already
    /// is the scaled-linear image the detection image and the render statistics build
    /// on.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: The geometry and linear samples, or `nil` for an unsupported sample
    ///   format, an invalid geometry, or truncated bytes.
    public static func linearImage( bytes: Data, properties: XISFImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        guard let planes = try? self.planeSamples( bytes: bytes, properties: properties )
        else
        {
            return nil
        }

        return self.linearLuminance( fromPlanes: planes, properties: properties )
    }

    /// Decodes the bytes into one raw, unscaled sample array per channel, honouring
    /// the layout's planar or interleaved pixel storage.
    ///
    /// A single-channel frame — a grayscale image, or a colour-filter-array mosaic —
    /// answers with exactly one plane.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: One plane per channel, each `width × height` samples.
    /// - Throws: ``Error`` for an invalid geometry, an unsupported sample format or
    ///   storage model, or truncated bytes.
    public static func planeSamples( bytes: Data, properties: XISFImageProperties ) throws -> [ [ Double ] ]
    {
        guard properties.width > 0, properties.height > 0, properties.channelCount > 0
        else
        {
            throw Error( message: "Invalid XISF image geometry: \( properties.width ) × \( properties.height ) × \( properties.channelCount )" )
        }

        let pixelCount = properties.width * properties.height
        let samples    = try self.samples( from: bytes, sampleFormat: properties.sampleFormat, byteOrder: properties.byteOrder, count: pixelCount * properties.channelCount )

        if properties.channelCount == 1
        {
            return [ samples ]
        }

        switch properties.pixelStorage
        {
            case .planar:

                // Channel-contiguous: each channel occupies one solid block.
                return ( 0 ..< properties.channelCount ).map
                {
                    channel in Array( samples[ ( channel * pixelCount ) ..< ( ( channel + 1 ) * pixelCount ) ] )
                }

            case .normal:

                // Pixel-interleaved: the channels of each pixel are adjacent.
                return ( 0 ..< properties.channelCount ).map
                {
                    channel in ( 0 ..< pixelCount ).map { samples[ $0 * properties.channelCount + channel ] }
                }

            @unknown default:

                throw Error( message: "Unsupported XISF pixel storage: \( properties.pixelStorage.rawValue )" )
        }
    }

    /// Combines decoded planes into one linear luminance channel, as their per-pixel
    /// equal-weight mean.
    ///
    /// XISF's ``scaling(from:)`` is the identity, so no affine `× scale + offset` is
    /// applied — the per-pixel mean is directly the scaled-linear luminance,
    /// accumulated from a `reduce(0.0)` seed.
    ///
    /// - Parameters:
    ///   - planes:     The decoded planes.
    ///   - properties: The image's layout.
    /// - Returns: The geometry and luminance samples, or `nil` when the planes are
    ///   empty or of unequal length.
    public static func linearLuminance( fromPlanes planes: [ [ Double ] ], properties: XISFImageProperties ) -> ( width: Int, height: Int, samples: [ Double ] )?
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

    /// The identity transform: XISF stores its samples at their physical values,
    /// with no format-level affine scaling to undo.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: XISFImageProperties ) -> ( scale: Double, offset: Double )
    {
        ( scale: 1, offset: 0 )
    }

    /// The span of the layout's sample format — `2ⁿ − 1` for the unsigned integer
    /// formats — deliberately matching the FITS convention so the two paths agree.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The full-scale value, or `nil` for a floating-point or complex
    ///   sample format.
    public static func fullScale( from properties: XISFImageProperties ) -> Double?
    {
        switch properties.sampleFormat
        {
            case .uInt8:      return Double( UInt8.max )
            case .uInt16:     return Double( UInt16.max )
            case .uInt32:     return Double( UInt32.max )
            case .uInt64:     return Double( UInt64.max )
            case .float32,
                 .float64,
                 .complex32,
                 .complex64:  return nil
            @unknown default: return nil
        }
    }

    /// The closest ``BitsPerPixel`` label for the layout's sample format.
    ///
    /// The complex formats have no representable equivalent and answer `nil`; every
    /// other format maps to the label whose storage width it shares (`UInt16` to the
    /// 16-bit label, `UInt32` and `UInt64` to the 32-bit one). The label carries no
    /// sample values — the plane render path consumes decoded `Double`s — so it only
    /// labels the format for the pipeline.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The sample format label, or `nil` when it has no representable
    ///   equivalent.
    public static func bitsPerPixel( from properties: XISFImageProperties ) -> BitsPerPixel?
    {
        switch properties.sampleFormat
        {
            case .uInt8:      return .uint8
            case .uInt16:     return .int16
            case .uInt32,
                 .uInt64:     return .int32
            case .float32:    return .float32
            case .float64:    return .float64
            case .complex32,
                 .complex64:  return nil
            @unknown default: return nil
        }
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
        guard let name = properties.colorFilterArrayPattern
        else
        {
            return nil
        }

        return try ColorFilterArray.pattern( named: name )
    }

    /// The layout's spatial dimensions.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The width and height, or `nil` when either is not positive.
    public static func dimensions( from properties: XISFImageProperties ) -> ( width: Int, height: Int )?
    {
        guard properties.width > 0, properties.height > 0
        else
        {
            return nil
        }

        return ( properties.width, properties.height )
    }

    /// The layout's channel count: `3` for RGB, `1` for grayscale or a
    /// colour-filter-array mosaic.
    ///
    /// - Parameter properties: The image's layout.
    /// - Returns: The channel count.
    public static func channelCount( from properties: XISFImageProperties ) -> Int
    {
        properties.channelCount
    }

    /// Decodes the single sample stored at a byte index, in the layout's sample
    /// format and byte order.
    ///
    /// Bounds-checked against the bytes' own index range rather than trapping, so a
    /// read-out over a truncated frame answers `nil`; a complex sample format, which
    /// is not decodable, answers `nil` too.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - index:      The sample's index into `bytes`, in `bytes`' own index space.
    ///   - properties: The image's layout.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: XISFImageProperties ) -> Double?
    {
        guard properties.sampleFormat.isComplex == false
        else
        {
            return nil
        }

        let bytesPerSample = properties.sampleFormat.bytesPerSample

        guard index >= bytes.startIndex, index + bytesPerSample <= bytes.endIndex
        else
        {
            return nil
        }

        let littleEndian = properties.byteOrder != .big
        let offset       = index - bytes.startIndex

        return bytes.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) in Self.sampleValue( in: raw, at: offset, sampleFormat: properties.sampleFormat, littleEndian: littleEndian )
        }
    }

    /// The byte indices covering an image coordinate, one per channel, following the
    /// layout's planar or interleaved storage. Indices are zero-based offsets into a
    /// frame's bytes; a caller reading a `Data` whose start index is non-zero adds
    /// that start index before ``decodeSample(bytes:at:properties:)``.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column, left to right.
    ///   - y:          The zero-based row, top to bottom.
    ///   - properties: The image's layout.
    /// - Returns: One index per channel, or `nil` for an invalid geometry or
    ///   out-of-bounds coordinates.
    public static func sampleByteOffsets( x: Int, y: Int, properties: XISFImageProperties ) -> [ Data.Index ]?
    {
        guard properties.width > 0, properties.height > 0, properties.channelCount > 0,
              x >= 0, x < properties.width, y >= 0, y < properties.height
        else
        {
            return nil
        }

        let bytesPerSample = properties.sampleFormat.bytesPerSample
        let pixelCount     = properties.width * properties.height
        let pixelIndex     = y * properties.width + x

        return ( 0 ..< properties.channelCount ).map
        {
            channel in

            let sampleIndex = properties.pixelStorage == .planar ? channel * pixelCount + pixelIndex : pixelIndex * properties.channelCount + channel

            return sampleIndex * bytesPerSample
        }
    }

    /// The detection image: the frame's linear luminance, demosaiced to luminance
    /// when the layout names a colour-filter-array pattern.
    ///
    /// A grayscale or RGB frame is already luminance and is used directly; a
    /// colour-filter-array frame is demosaiced (feeding a raw mosaic to the detector
    /// would inject the Bayer grid as false structure). Best-effort by design — any
    /// failure returns `nil` so a consumer skips detection rather than failing to open
    /// the image.
    ///
    /// - Parameters:
    ///   - bytes:      The image's pixel bytes.
    ///   - properties: The image's layout.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: XISFImageProperties ) -> PixelBuffer?
    {
        guard let luminance = self.linearImage( bytes: bytes, properties: properties ),
              let buffer    = try? PixelBuffer( width: luminance.width, height: luminance.height, channels: 1, pixels: luminance.samples, isNormalized: false )
        else
        {
            return nil
        }

        // cfaPattern(from:) returns nil for a non-mosaic frame and throws on an
        // unsupported pattern; both fall back to the single luminance channel.
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
    public static func detectionImage( of frame: XISFImageFrame ) throws -> PixelBuffer
    {
        let ( bytes, properties ) = try self.contents( of: frame )

        guard let image = self.detectionImage( bytes: bytes, properties: properties )
        else
        {
            throw Error( message: "XISF frame has no usable detection image" )
        }

        return image
    }

    // MARK: - Sample decoding

    /// Decodes `count` samples from raw bytes into `Double`s, honouring the sample
    /// format and byte order — the XISF counterpart of SwiftPixel's `readRawPixels`,
    /// which decodes only the big-endian, signed FITS formats.
    ///
    /// - Parameters:
    ///   - data:         The raw sample bytes.
    ///   - sampleFormat: The stored sample format.
    ///   - byteOrder:    The stored byte order.
    ///   - count:        The number of samples to read.
    /// - Returns: The decoded samples.
    /// - Throws: ``Error`` for a complex sample format (unsupported) or truncated
    ///   data.
    private static func samples( from data: Data, sampleFormat: XISFSampleFormat, byteOrder: XISFByteOrder, count: Int ) throws -> [ Double ]
    {
        guard sampleFormat.isComplex == false
        else
        {
            throw Error( message: "Complex XISF sample formats are not supported" )
        }

        let bytesPerSample = sampleFormat.bytesPerSample
        let required       = count * bytesPerSample
        let bytes          = Data( data.prefix( required ) ) // re-wrap: startIndex may be non-zero, and trim trailing bytes

        guard bytes.count == required
        else
        {
            throw Error( message: "XISF pixel data too small: \( data.count ) < \( required )" )
        }

        let littleEndian = byteOrder != .big

        return bytes.withUnsafeBytes
        {
            ( raw: UnsafeRawBufferPointer ) -> [ Double ] in

            ( 0 ..< count ).map
            {
                Self.sampleValue( in: raw, at: $0 * bytesPerSample, sampleFormat: sampleFormat, littleEndian: littleEndian )
            }
        }
    }

    /// Decodes a single sample from a raw byte buffer at a byte offset, applying the
    /// byte order. Shared by the batch ``samples(from:sampleFormat:byteOrder:count:)``
    /// and the per-sample ``decodeSample(bytes:at:properties:)`` read-out.
    ///
    /// - Parameters:
    ///   - raw:          The byte buffer.
    ///   - offset:       The sample's byte offset into the buffer.
    ///   - sampleFormat: The stored sample format.
    ///   - littleEndian: Whether the samples are little-endian.
    /// - Returns: The decoded value (`NaN` for a complex format, which callers reject
    ///   before reaching here).
    private static func sampleValue( in raw: UnsafeRawBufferPointer, at offset: Int, sampleFormat: XISFSampleFormat, littleEndian: Bool ) -> Double
    {
        switch sampleFormat
        {
            case .uInt8:

                return Double( raw.load( fromByteOffset: offset, as: UInt8.self ) )

            case .uInt16:

                let stored = raw.loadUnaligned( fromByteOffset: offset, as: UInt16.self )

                return Double( littleEndian ? UInt16( littleEndian: stored ) : UInt16( bigEndian: stored ) )

            case .uInt32:

                let stored = raw.loadUnaligned( fromByteOffset: offset, as: UInt32.self )

                return Double( littleEndian ? UInt32( littleEndian: stored ) : UInt32( bigEndian: stored ) )

            case .uInt64:

                let stored = raw.loadUnaligned( fromByteOffset: offset, as: UInt64.self )

                return Double( littleEndian ? UInt64( littleEndian: stored ) : UInt64( bigEndian: stored ) )

            case .float32:

                let stored = raw.loadUnaligned( fromByteOffset: offset, as: UInt32.self )

                return Double( Float( bitPattern: littleEndian ? UInt32( littleEndian: stored ) : UInt32( bigEndian: stored ) ) )

            case .float64:

                let stored = raw.loadUnaligned( fromByteOffset: offset, as: UInt64.self )

                return Double( bitPattern: littleEndian ? UInt64( littleEndian: stored ) : UInt64( bigEndian: stored ) )

            case .complex32,
                 .complex64:

                return Double.nan

            @unknown default:

                return Double.nan
        }
    }
}
