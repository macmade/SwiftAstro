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
        let hdu = try self.imageHDU( in: container.sections )

        // A multi-image cube expands into one frame per plane; a truncated cube with
        // no whole plane present falls back to the single whole-HDU frame. Everything
        // else is one frame.
        guard self.isMultiImageCube( properties: hdu.properties )
        else
        {
            return [ FITSImageFrame( data: hdu.data, properties: hdu.properties ) ]
        }

        let planes = self.cubePlanes( data: hdu.data, properties: hdu.properties )

        guard planes.isEmpty == false
        else
        {
            return [ FITSImageFrame( data: hdu.data, properties: hdu.properties ) ]
        }

        return planes.map { FITSImageFrame( data: $0.data, properties: $0.properties ) }
    }

    /// The frame's bytes with the FITS 2880-byte block padding trimmed to the byte
    /// count its geometry implies, paired with its header.
    ///
    /// The trimmed length spans every channel: three band-sequential planes for an
    /// RGB colour cube, one plane otherwise.
    ///
    /// - Parameter frame: The frame to read.
    /// - Returns: The trimmed bytes and the frame's header.
    /// - Throws: ``Error`` when the geometry is missing or the bytes are short of
    ///   it.
    public static func contents( of frame: FITSImageFrame ) throws -> ( bytes: Data, properties: [ FITSPropertySnapshot ] )
    {
        guard let ( width, height ) = self.dimensions( from: frame.properties ),
              let bitsPerPixel      = self.bitsPerPixel( from: frame.properties )
        else
        {
            throw Error( message: "FITS frame has a missing or unsupported geometry" )
        }

        guard let pixels = self.checkedProduct( width, height ),
              let planeSize = bitsPerPixel.size( numberOfPixels: pixels ),
              let total     = self.checkedProduct( planeSize, self.channelCount( from: frame.properties ) ), total > 0
        else
        {
            throw Error( message: "FITS frame byte size overflows Int" )
        }

        // Re-wrap so a non-zero start index reads from zero, and trim any FITS block
        // padding to the exact sample-data size.
        let bytes = Data( frame.data.prefix( total ) )

        guard bytes.count == total
        else
        {
            throw Error( message: "FITS data segment is smaller than its geometry implies" )
        }

        return ( bytes, frame.properties )
    }

    /// Decodes the bytes into scaled-linear samples: `BITPIX` selects the sample
    /// format, `BLANK` maps undefined integer samples to NaN, then `BSCALE` and
    /// `BZERO` are applied.
    ///
    /// Decodes a single channel: the whole of a monochrome or colour-filter-array
    /// frame, or the first plane of a colour cube (no caller reads a cube this way —
    /// it uses ``planeSamples(bytes:properties:)`` instead).
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - properties: The frame's header.
    /// - Returns: The geometry and scaled-linear samples, or `nil`.
    public static func linearImage( bytes: Data, properties: [ FITSPropertySnapshot ] ) -> ( width: Int, height: Int, samples: [ Double ] )?
    {
        guard let bitsPerPixel = self.bitsPerPixel( from: properties ),
              let ( width, height ) = self.dimensions( from: properties ),
              let raw = self.rawPlane( bytes: bytes, width: width, height: height, bitsPerPixel: bitsPerPixel, properties: properties )
        else
        {
            return nil
        }

        let ( scale, offset ) = self.scaling( from: properties )
        let samples           = raw.map { $0 * scale + offset }

        return ( width: width, height: height, samples: samples )
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
        guard let bitsPerPixel = self.bitsPerPixel( from: properties ),
              let ( width, height ) = self.dimensions( from: properties )
        else
        {
            throw Error( message: "FITS frame has a missing or unsupported geometry" )
        }

        let channels = self.channelCount( from: properties )

        guard let pixels = self.checkedProduct( width, height ),
              let planeSize = bitsPerPixel.size( numberOfPixels: pixels ),
              let total     = self.checkedProduct( planeSize, channels )
        else
        {
            throw Error( message: "FITS frame byte size overflows Int" )
        }

        let pixelData = Data( bytes.prefix( total ) )

        guard pixelData.count == total
        else
        {
            throw Error( message: "FITS data segment is smaller than its geometry implies" )
        }

        // Each channel is a contiguous band-sequential plane; re-wrap each slice into
        // a fresh, zero-based Data so `readRawPixels` reads it in isolation.
        return try ( 0 ..< channels ).map
        {
            plane in

            let slice = Data( pixelData.dropFirst( plane * planeSize ).prefix( planeSize ) )

            return try PixelUtilities.readRawPixels( data: slice, width: width, height: height, bitsPerPixel: bitsPerPixel, blank: self.blankValue( from: properties ) )
        }
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
        guard let ( width, height ) = self.dimensions( from: properties ),
              let first = planes.first,
              planes.allSatisfy( { $0.count == first.count } )
        else
        {
            return nil
        }

        let ( scale, offset ) = self.scaling( from: properties )
        let count             = Double( planes.count )
        let samples           = ( 0 ..< first.count ).map
        {
            index -> Double in

            let sum = planes.reduce( 0.0 ) { $0 + $1[ index ] }

            return ( sum / count ) * scale + offset
        }

        return ( width: width, height: height, samples: samples )
    }

    /// Reads the linear pixel-scaling keywords `BSCALE` (the multiplicative
    /// scale, default `1`) and `BZERO` (the additive offset, default `0`).
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The scale and offset.
    public static func scaling( from properties: [ FITSPropertySnapshot ] ) -> ( scale: Double, offset: Double )
    {
        let bZero  = properties.first { $0.name == "BZERO"  }
        let bScale = properties.first { $0.name == "BSCALE" }

        let offset = bZero?.value.float  ?? bZero?.value.integer.map( Double.init )  ?? 0
        let scale  = bScale?.value.float ?? bScale?.value.integer.map( Double.init ) ?? 1

        return ( scale: scale, offset: offset )
    }

    /// The span of the `BITPIX` sample format: `255`, `65535` or `4294967295` for
    /// the integer formats, applied after ``scaling(from:)``.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The full-scale value, or `nil` for a floating-point `BITPIX`.
    public static func fullScale( from properties: [ FITSPropertySnapshot ] ) -> Double?
    {
        self.bitsPerPixel( from: properties ).flatMap( self.fullScale( for: ) )
    }

    /// The sample format the header's `BITPIX` names.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The sample format, or `nil` when `BITPIX` is missing or names an
    ///   unsupported format.
    public static func bitsPerPixel( from properties: [ FITSPropertySnapshot ] ) -> BitsPerPixel?
    {
        guard let bitPix = properties.first( where: { $0.name == "BITPIX" } )?.value.integer
        else
        {
            return nil
        }

        return BitsPerPixel.from( value: bitPix )
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
        guard let name = properties.first( where: { $0.name == "BAYERPAT" } )?.value.string
        else
        {
            return nil
        }

        return try ColorFilterArray.pattern( named: name )
    }

    /// The dimensions the header's `NAXIS1` and `NAXIS2` keywords give.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The width and height, or `nil` when either keyword is missing or
    ///   not positive.
    public static func dimensions( from properties: [ FITSPropertySnapshot ] ) -> ( width: Int, height: Int )?
    {
        guard let nAxis1 = properties.first( where: { $0.name == "NAXIS1" } )?.value.integer,
              let nAxis2 = properties.first( where: { $0.name == "NAXIS2" } )?.value.integer,
              let width  = Int( exactly: nAxis1 ), width  > 0,
              let height = Int( exactly: nAxis2 ), height > 0
        else
        {
            return nil
        }

        return ( width, height )
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
        self.isRGBPlanes( properties: properties ) ? 3 : 1
    }

    /// Decodes the single big-endian sample stored at a byte index, before
    /// ``scaling(from:)`` is applied.
    ///
    /// Bounds-checked against the bytes' own index range rather than trapping, so a
    /// read-out over a truncated frame answers `nil`.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - index:      The sample's index into `bytes`, in `bytes`' own index space.
    ///   - properties: The frame's header.
    /// - Returns: The stored value, or `nil` when a whole sample does not fit.
    public static func decodeSample( bytes: Data, at index: Data.Index, properties: [ FITSPropertySnapshot ] ) -> Double?
    {
        guard let bitsPerPixel = self.bitsPerPixel( from: properties ),
              let bytesPerSample = bitsPerPixel.size( numberOfPixels: 1 ),
              index >= bytes.startIndex, index + bytesPerSample <= bytes.endIndex
        else
        {
            return nil
        }

        return self.decodeSample( data: bytes, at: index, bitsPerPixel: bitsPerPixel )
    }

    /// The byte indices covering an image coordinate: three band-sequential
    /// indices for an RGB colour cube, one otherwise. Indices are zero-based
    /// offsets into a frame's trimmed bytes; a caller reading a `Data` whose start
    /// index is non-zero adds that start index before ``decodeSample(bytes:at:properties:)``.
    ///
    /// - Parameters:
    ///   - x:          The zero-based column.
    ///   - y:          The zero-based row.
    ///   - properties: The frame's header.
    /// - Returns: One index per channel, or `nil`.
    public static func sampleByteOffsets( x: Int, y: Int, properties: [ FITSPropertySnapshot ] ) -> [ Data.Index ]?
    {
        guard let bitsPerPixel = self.bitsPerPixel( from: properties ),
              let bytesPerSample = bitsPerPixel.size( numberOfPixels: 1 ),
              let ( width, height ) = self.dimensions( from: properties ),
              x >= 0, x < width, y >= 0, y < height
        else
        {
            return nil
        }

        let channels = self.channelCount( from: properties )

        guard channels == 3
        else
        {
            guard let rowStart    = self.checkedProduct( y, width ),
                  let sampleIndex = self.checkedSum( rowStart, x ),
                  let byteOffset  = self.checkedProduct( sampleIndex, bytesPerSample )
            else
            {
                return nil
            }

            return [ byteOffset ]
        }

        guard let planeSampleCount = self.checkedProduct( width, height )
        else
        {
            return nil
        }

        let offsets = ( 0 ..< 3 ).compactMap
        {
            plane -> Data.Index? in

            guard let planeStart  = self.checkedProduct( plane, planeSampleCount ),
                  let rowStart    = self.checkedProduct( y, width ),
                  let pixelIndex  = self.checkedSum( planeStart, rowStart ),
                  let sampleIndex = self.checkedSum( pixelIndex, x ),
                  let byteOffset  = self.checkedProduct( sampleIndex, bytesPerSample )
            else
            {
                return nil
            }

            return byteOffset
        }

        return offsets.count == 3 ? offsets : nil
    }

    /// The detection image: an RGB colour cube combined to luminance, any other
    /// frame decoded to its linear channel and — when `BAYERPAT` names a pattern —
    /// demosaiced to luminance.
    ///
    /// The demosaic is applied uniformly to every non-RGB frame that carries a
    /// pattern, a multi-image cube plane included, so a mosaic is never fed to star
    /// detection as though it were a monochrome frame regardless of how the file
    /// packages it.
    ///
    /// - Parameters:
    ///   - bytes:      The frame's trimmed bytes.
    ///   - properties: The frame's header.
    /// - Returns: The detection image, or `nil`.
    public static func detectionImage( bytes: Data, properties: [ FITSPropertySnapshot ] ) -> PixelBuffer?
    {
        // An RGB image combines its planes into luminance rather than detecting on
        // one plane; a failed luminance decode skips detection.
        if self.channelCount( from: properties ) == 3
        {
            guard let planes = try? self.planeSamples( bytes: bytes, properties: properties ),
                  let luminance = self.linearLuminance( fromPlanes: planes, properties: properties )
            else
            {
                return nil
            }

            return try? PixelBuffer( width: luminance.width, height: luminance.height, channels: 1, pixels: luminance.samples, isNormalized: false )
        }

        // A 2-D image is decoded to its linear single channel; a colour-filter-array
        // frame is then demosaiced to luminance (feeding a raw mosaic to the detector
        // would inject the Bayer grid as false structure). Any failure returns nil so
        // detection is skipped.
        guard let linear = self.linearImage( bytes: bytes, properties: properties ),
              let buffer = try? PixelBuffer( width: linear.width, height: linear.height, channels: 1, pixels: linear.samples, isNormalized: false )
        else
        {
            return nil
        }

        // cfaPattern(from:) returns nil for a monochrome frame and throws on an
        // unsupported BAYERPAT; both fall back to the single (mono / raw) channel.
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
    public static func detectionImage( of frame: FITSImageFrame ) throws -> PixelBuffer
    {
        let ( bytes, properties ) = try self.contents( of: frame )

        guard let image = self.detectionImage( bytes: bytes, properties: properties )
        else
        {
            throw Error( message: "FITS frame has no usable detection image" )
        }

        return image
    }

    // MARK: - HDU selection and cube expansion

    /// Selects the file's image HDU: the first section of kind `.data` at an index
    /// greater than zero, paired with the property snapshots of the section
    /// immediately preceding it.
    ///
    /// This is the single home for the FITS image-HDU selection rule, so
    /// ``frames(in:)`` and any consumer navigating a file's sections apply the same
    /// rule rather than re-deriving it.
    ///
    /// - Parameter sections: The file's sections, in file order.
    /// - Returns: The HDU's raw bytes and its owning header's property snapshots.
    /// - Throws: ``Error`` when the file contains no image data section.
    public static func imageHDU( in sections: [ FITSSection ] ) throws -> ( data: Data, properties: [ FITSPropertySnapshot ] )
    {
        guard let dataIndex = sections.firstIndex( where: { $0.kind == .data } ), dataIndex > 0
        else
        {
            throw Error( message: "FITS file contains no image HDU" )
        }

        let properties = sections[ dataIndex - 1 ].properties.map { FITSPropertySnapshot( name: $0.name, value: $0.value ) }

        return ( try sections[ dataIndex ].data, properties )
    }

    /// Whether the header describes a three-dimensional HDU whose third axis holds
    /// separate red, green and blue image planes.
    ///
    /// The rule: `NAXIS = 3`, `NAXIS3 = 3`, and no present, non-empty `CTYPE3`
    /// (whose presence marks the third axis as a physical coordinate — a data cube,
    /// not colour planes).
    ///
    /// - Parameter properties: The image HDU's header properties.
    /// - Returns: `true` when the header matches the RGB-planes shape.
    private static func isRGBPlanes( properties: [ FITSPropertySnapshot ] ) -> Bool
    {
        guard properties.first( where: { $0.name == "NAXIS"  } )?.value.integer == 3,
              properties.first( where: { $0.name == "NAXIS3" } )?.value.integer == 3
        else
        {
            return false
        }

        return self.trimmedString( named: "CTYPE3", in: properties ) == nil
    }

    /// Whether the header describes a `NAXIS = 3` cube whose third axis holds
    /// multiple distinct images (a stack), rather than RGB colour planes or a
    /// physical data cube.
    ///
    /// The rule: `NAXIS = 3`, `NAXIS3 ≥ 2` and `≠ 3` (a count of 3 is claimed as
    /// colour by ``isRGBPlanes(properties:)``), and no present, non-empty `CTYPE3`.
    ///
    /// - Parameter properties: The image HDU's header properties.
    /// - Returns: `true` when the header matches the multi-image cube shape.
    private static func isMultiImageCube( properties: [ FITSPropertySnapshot ] ) -> Bool
    {
        guard properties.first( where: { $0.name == "NAXIS" } )?.value.integer == 3,
              let nAxis3 = properties.first( where: { $0.name == "NAXIS3" } )?.value.integer,
              nAxis3 >= 2, nAxis3 != 3
        else
        {
            return false
        }

        return self.trimmedString( named: "CTYPE3", in: properties ) == nil
    }

    /// Splits a multi-image `NAXIS = 3` cube into one two-dimensional image HDU per
    /// plane, in third-axis order.
    ///
    /// Each returned HDU carries the plane's own contiguous byte slice and a header
    /// synthesised from the cube's — `NAXIS` set to 2 and `NAXIS3` dropped, every
    /// other keyword preserved. Only whole planes actually present in the data are
    /// returned: a cube truncated below its declared `NAXIS3` yields the fully
    /// present planes rather than broken frames.
    ///
    /// - Parameters:
    ///   - data:       The cube HDU's raw pixel bytes (band-sequential planes).
    ///   - properties: The cube HDU's header properties.
    /// - Returns: One 2-D HDU per fully present plane, empty when the geometry is
    ///   missing/invalid or no whole plane is present.
    private static func cubePlanes( data: Data, properties: [ FITSPropertySnapshot ] ) -> [ ( data: Data, properties: [ FITSPropertySnapshot ] ) ]
    {
        guard let bitsPerPixel = self.bitsPerPixel( from: properties ),
              let ( width, height ) = self.dimensions( from: properties ),
              let nAxis3     = properties.first( where: { $0.name == "NAXIS3" } )?.value.integer,
              let planeCount = Int( exactly: nAxis3 ), planeCount > 0,
              let pixels     = self.checkedProduct( width, height ),
              let planeSize  = bitsPerPixel.size( numberOfPixels: pixels ), planeSize > 0
        else
        {
            return []
        }

        // Only whole planes actually present in the data become frames.
        let availablePlanes = min( planeCount, data.count / planeSize )

        // The per-plane header is the cube's, made two-dimensional.
        let planeProperties = properties.compactMap
        {
            property -> FITSPropertySnapshot? in

            switch property.name
            {
                case "NAXIS":  return FITSPropertySnapshot( name: "NAXIS", value: .integer( 2 ) )
                case "NAXIS3": return nil
                default:       return property
            }
        }

        return ( 0 ..< availablePlanes ).map
        {
            plane in

            // Re-wrap each plane slice into a fresh, zero-based Data.
            let slice = Data( data.dropFirst( plane * planeSize ).prefix( planeSize ) )

            return ( data: slice, properties: planeProperties )
        }
    }

    // MARK: - Sample decoding

    /// Decodes a single, contiguous channel plane into its raw, unscaled samples,
    /// trimming any FITS block padding to the exact plane size.
    ///
    /// - Parameters:
    ///   - bytes:        The frame's bytes (at least one plane).
    ///   - width:        The plane width.
    ///   - height:       The plane height.
    ///   - bitsPerPixel: The sample format.
    ///   - properties:   The frame's header (for `BLANK`).
    /// - Returns: The plane's raw samples, or `nil` for an overflowing geometry or
    ///   truncated bytes.
    private static func rawPlane( bytes: Data, width: Int, height: Int, bitsPerPixel: BitsPerPixel, properties: [ FITSPropertySnapshot ] ) -> [ Double ]?
    {
        guard let pixels = self.checkedProduct( width, height ),
              let size   = bitsPerPixel.size( numberOfPixels: pixels )
        else
        {
            return nil
        }

        let pixelData = Data( bytes.prefix( size ) )

        guard pixelData.count == size
        else
        {
            return nil
        }

        return try? PixelUtilities.readRawPixels( data: pixelData, width: width, height: height, bitsPerPixel: bitsPerPixel, blank: self.blankValue( from: properties ) )
    }

    /// Reads the integer `BLANK` undefined-pixel sentinel, which
    /// `PixelUtilities.readRawPixels` maps to NaN for an integer image.
    ///
    /// - Parameter properties: The frame's header.
    /// - Returns: The `BLANK` value, or `nil` when absent or not an integer.
    private static func blankValue( from properties: [ FITSPropertySnapshot ] ) -> Int64?
    {
        properties.first { $0.name == "BLANK" }?.value.integer
    }

    /// Decodes a single big-endian sample at the given absolute data index.
    ///
    /// - Parameters:
    ///   - data:         The bytes to read.
    ///   - index:        The sample's absolute index.
    ///   - bitsPerPixel: The sample format.
    /// - Returns: The stored value.
    private static func decodeSample( data: Data, at index: Data.Index, bitsPerPixel: BitsPerPixel ) -> Double
    {
        switch bitsPerPixel
        {
            case .uint8:

                return Double( data[ index ] )

            case .int16:

                let raw = ( UInt16( data[ index ] ) << 8 ) | UInt16( data[ index + 1 ] )

                return Double( Int16( bitPattern: raw ) )

            case .int32:

                var raw: UInt32 = 0

                for offset in 0 ..< 4
                {
                    raw = ( raw << 8 ) | UInt32( data[ index + offset ] )
                }

                return Double( Int32( bitPattern: raw ) )

            case .float32:

                var raw: UInt32 = 0

                for offset in 0 ..< 4
                {
                    raw = ( raw << 8 ) | UInt32( data[ index + offset ] )
                }

                return Double( Float32( bitPattern: raw ) )

            case .float64:

                var raw: UInt64 = 0

                for offset in 0 ..< 8
                {
                    raw = ( raw << 8 ) | UInt64( data[ index + offset ] )
                }

                return Double( bitPattern: raw )

            @unknown default:

                return 0
        }
    }

    /// The full-scale span of an integer sample format, or `nil` for a
    /// floating-point one.
    ///
    /// - Parameter bitsPerPixel: The sample format.
    /// - Returns: `255`, `65535` or `4294967295`, or `nil`.
    private static func fullScale( for bitsPerPixel: BitsPerPixel ) -> Double?
    {
        switch bitsPerPixel
        {
            case .uint8:      return 255
            case .int16:      return 65535
            case .int32:      return 4294967295
            case .float32,
                 .float64:    return nil
            @unknown default: return nil
        }
    }

    /// The first non-empty, whitespace-trimmed string value for a keyword.
    ///
    /// - Parameters:
    ///   - name:       The keyword name.
    ///   - properties: The header properties to search.
    /// - Returns: The trimmed string, or `nil` when absent, non-string or empty.
    private static func trimmedString( named name: String, in properties: [ FITSPropertySnapshot ] ) -> String?
    {
        guard let text = properties.first( where: { $0.name == name } )?.value.string?.trimmingCharacters( in: .whitespaces ), text.isEmpty == false
        else
        {
            return nil
        }

        return text
    }

    /// Multiplies two counts, returning `nil` instead of trapping on overflow.
    ///
    /// - Parameters:
    ///   - a: The first factor.
    ///   - b: The second factor.
    /// - Returns: `a × b`, or `nil` on overflow.
    private static func checkedProduct( _ a: Int, _ b: Int ) -> Int?
    {
        let ( product, overflow ) = a.multipliedReportingOverflow( by: b )

        return overflow ? nil : product
    }

    /// Adds two counts, returning `nil` instead of trapping on overflow.
    ///
    /// - Parameters:
    ///   - a: The first term.
    ///   - b: The second term.
    /// - Returns: `a + b`, or `nil` on overflow.
    private static func checkedSum( _ a: Int, _ b: Int ) -> Int?
    {
        let ( sum, overflow ) = a.addingReportingOverflow( b )

        return overflow ? nil : sum
    }
}
