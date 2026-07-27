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
@testable import SwiftAstro
import SwiftPixel
import SwiftXISF
import Testing

/// Behavioural tests for ``XISFImageDecoder``: the properties-based sample decode,
/// plane extraction, luminance and detection image over synthetic layouts, plus an
/// end-to-end pass over the committed `S30-M42-Corrected.xisf` capture through the
/// shared ``XISFImageDecoder``.
///
/// Synthetic bytes exercise the parts that need only a ``XISFImageProperties`` value —
/// sample format, byte order, planar/interleaved storage — because building a real
/// ``XISFImage`` needs a parsed file, whereas the container- and frame-based
/// operations (``XISFImageDecoder/frames(in:)``, ``XISFImageDecoder/contents(of:)``
/// and ``XISFImageDecoder/detectionImage(of:)``) are covered against the real capture.
struct XISFImageDecoderTests
{
    // MARK: - Synthetic helpers

    /// A synthetic XISF layout.
    ///
    /// - Parameters:
    ///   - width:        The image width.
    ///   - height:       The image height.
    ///   - channelCount: The channel count.
    ///   - sampleFormat: The sample format.
    ///   - byteOrder:    The byte order.
    ///   - pixelStorage: The planar/interleaved storage model.
    ///   - colorSpace:   The colour space.
    ///   - cfa:          The colour-filter-array pattern name, or `nil`.
    /// - Returns: The layout.
    private func properties( width: Int, height: Int, channelCount: Int = 1, sampleFormat: XISFSampleFormat = .uInt16, byteOrder: XISFByteOrder = .little, pixelStorage: XISFPixelStorage = .planar, colorSpace: XISFColorSpace = .gray, cfa: String? = nil ) -> XISFImageProperties
    {
        XISFImageProperties(
            width:                   width,
            height:                  height,
            channelCount:            channelCount,
            sampleFormat:            sampleFormat,
            byteOrder:               byteOrder,
            pixelStorage:            pixelStorage,
            colorSpace:              colorSpace,
            colorFilterArrayPattern: cfa
        )
    }

    /// Encodes 16-bit unsigned samples little-endian.
    ///
    /// - Parameter values: The sample values.
    /// - Returns: The little-endian bytes.
    private func littleEndian16( _ values: [ Int ] ) -> Data
    {
        Data( values.flatMap { [ UInt8( $0 & 0xFF ), UInt8( ( $0 >> 8 ) & 0xFF ) ] } )
    }

    /// Encodes 16-bit unsigned samples big-endian.
    ///
    /// - Parameter values: The sample values.
    /// - Returns: The big-endian bytes.
    private func bigEndian16( _ values: [ Int ] ) -> Data
    {
        Data( values.flatMap { [ UInt8( ( $0 >> 8 ) & 0xFF ), UInt8( $0 & 0xFF ) ] } )
    }

    // MARK: - Header interpretation

    /// XISF stores physical values, so ``XISFImageDecoder/scaling(from:)`` is the
    /// identity transform.
    @Test
    func scalingIsTheIdentity()
    {
        let ( scale, offset ) = XISFImageDecoder.scaling( from: self.properties( width: 2, height: 1 ) )

        #expect( scale  == 1 )
        #expect( offset == 0 )
    }

    /// The full-scale span is `2ⁿ − 1` for every unsigned integer format and `nil`
    /// for the floating-point and complex formats — the same span convention the
    /// FITS decoder follows.
    @Test
    func fullScaleMatchesTheSpanConvention()
    {
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .uInt8  ) ) == 255 )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .uInt16 ) ) == 65535 )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .uInt32 ) ) == 4294967295 )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .uInt64 ) ) == Double( UInt64.max ) )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .float32 ) ) == nil )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .float64 ) ) == nil )
        #expect( XISFImageDecoder.fullScale( from: self.properties( width: 1, height: 1, sampleFormat: .complex32 ) ) == nil )
    }

    /// Each sample format maps to a representative ``BitsPerPixel`` label; the
    /// complex formats have no supported equivalent and answer `nil`.
    @Test
    func bitsPerPixelLabelsEachFormat()
    {
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .uInt8   ) ) == .uint8 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .uInt16  ) ) == .int16 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .uInt32  ) ) == .int32 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .uInt64  ) ) == .int32 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .float32 ) ) == .float32 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .float64 ) ) == .float64 )
        #expect( XISFImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1, sampleFormat: .complex32 ) ) == nil )
    }

    /// The dimensions come straight from the layout, and a non-positive dimension is
    /// rejected.
    @Test
    func dimensionsRejectNonPositiveGeometry()
    {
        #expect( XISFImageDecoder.dimensions( from: self.properties( width: 8, height: 4 ) ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( XISFImageDecoder.dimensions( from: self.properties( width: 0, height: 4 ) ) == nil )
    }

    /// The channel count is the layout's, and it drives colour-ness for XISF.
    @Test
    func channelCountFollowsTheLayout()
    {
        #expect( XISFImageDecoder.channelCount( from: self.properties( width: 2, height: 2, channelCount: 1 ) ) == 1 )
        #expect( XISFImageDecoder.channelCount( from: self.properties( width: 2, height: 2, channelCount: 3, colorSpace: .rgb ) ) == 3 )
    }

    /// A named colour-filter array routes through the shared mapping; an absent one
    /// answers `nil`; an unsupported one throws.
    @Test
    func cfaPatternRoutesThroughTheSharedMapping() throws
    {
        #expect( try XISFImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: "RGGB" ) ) == .rggb )
        #expect( try XISFImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: nil ) ) == nil )
        #expect( throws: SwiftAstro.Error.self ) { try XISFImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: "XYZW" ) ) }
    }

    // MARK: - Sample decoding

    /// A single sample decodes in the layout's byte order, and reading past the end
    /// answers `nil` rather than trapping.
    @Test
    func decodeSampleHonoursByteOrderAndBounds()
    {
        let little = self.littleEndian16( [ 258, 65535 ] ) // 258 = 0x0102
        let big    = self.bigEndian16(    [ 258, 65535 ] )

        let littleProperties = self.properties( width: 2, height: 1, byteOrder: .little )
        let bigProperties    = self.properties( width: 2, height: 1, byteOrder: .big )

        #expect( XISFImageDecoder.decodeSample( bytes: little, at: little.startIndex,     properties: littleProperties ) == 258 )
        #expect( XISFImageDecoder.decodeSample( bytes: little, at: little.startIndex + 2, properties: littleProperties ) == 65535 )
        #expect( XISFImageDecoder.decodeSample( bytes: big,    at: big.startIndex,        properties: bigProperties ) == 258 )

        // One byte short of a whole 16-bit sample: refused, not trapped.
        #expect( XISFImageDecoder.decodeSample( bytes: little, at: little.startIndex + 3, properties: littleProperties ) == nil )
    }

    /// The per-pixel byte offsets follow the storage model: planar channels are one
    /// solid block each, interleaved channels are adjacent within a pixel.
    @Test
    func sampleByteOffsetsFollowTheStorageModel()
    {
        let planar      = self.properties( width: 2, height: 2, channelCount: 3, pixelStorage: .planar, colorSpace: .rgb )
        let interleaved = self.properties( width: 2, height: 2, channelCount: 3, pixelStorage: .normal, colorSpace: .rgb )

        // (1, 1) is pixel index 3 of a 2 × 2 image (pixel count 4). uInt16 → 2 bytes
        // per sample. Planar: channel c → (c · 4 + 3) · 2  →  [ 6, 14, 22 ].
        #expect( XISFImageDecoder.sampleByteOffsets( x: 1, y: 1, properties: planar ) == [ 6, 14, 22 ] )

        // Interleaved: channel c → (3 · 3 + c) · 2  →  [ 18, 20, 22 ].
        #expect( XISFImageDecoder.sampleByteOffsets( x: 1, y: 1, properties: interleaved ) == [ 18, 20, 22 ] )

        // Out-of-bounds coordinates answer nil.
        #expect( XISFImageDecoder.sampleByteOffsets( x: 2, y: 0, properties: planar ) == nil )
    }

    // MARK: - Plane extraction and luminance

    /// A grayscale frame decodes to exactly one plane holding every sample.
    @Test
    func planeSamplesYieldsOnePlaneForGrayscale() throws
    {
        let bytes  = self.littleEndian16( [ 10, 20, 30, 40 ] )
        let planes = try XISFImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 2, height: 2 ) )

        #expect( planes.count == 1 )
        #expect( planes.first == [ 10, 20, 30, 40 ] )
    }

    /// Planar RGB storage splits into channel-contiguous blocks.
    @Test
    func planeSamplesSplitsPlanarChannels() throws
    {
        // Two pixels, three planar channels: R = 1,2  G = 3,4  B = 5,6.
        let bytes  = self.littleEndian16( [ 1, 2, 3, 4, 5, 6 ] )
        let planes = try XISFImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 2, height: 1, channelCount: 3, pixelStorage: .planar, colorSpace: .rgb ) )

        #expect( planes == [ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ] )
    }

    /// Interleaved (normal) RGB storage deinterleaves into per-channel planes.
    @Test
    func planeSamplesDeinterleavesInterleavedChannels() throws
    {
        // Two pixels, three interleaved channels: pixel 0 = (1,3,5), pixel 1 = (2,4,6).
        let bytes  = self.littleEndian16( [ 1, 3, 5, 2, 4, 6 ] )
        let planes = try XISFImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 2, height: 1, channelCount: 3, pixelStorage: .normal, colorSpace: .rgb ) )

        #expect( planes == [ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ] )
    }

    /// The linear luminance is the equal-weight mean of the channels; a grayscale
    /// frame's luminance is its single channel unchanged.
    @Test
    func linearLuminanceIsTheEqualWeightMean() throws
    {
        let luminance = try #require( XISFImageDecoder.linearLuminance( fromPlanes: [ [ 2, 4 ], [ 4, 8 ], [ 6, 12 ] ], properties: self.properties( width: 2, height: 1, channelCount: 3, colorSpace: .rgb ) ) )

        #expect( luminance.width  == 2 )
        #expect( luminance.height == 1 )
        #expect( luminance.samples == [ 4, 8 ] )
    }

    /// ``XISFImageDecoder/linearImage(bytes:properties:)`` decodes to the frame's
    /// equal-weight luminance — for a grayscale frame, the single channel itself.
    @Test
    func linearImageIsTheFramesLuminance() throws
    {
        let bytes  = self.littleEndian16( [ 10, 20, 30, 40 ] )
        let linear = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: self.properties( width: 2, height: 2 ) ) )

        #expect( linear.width   == 2 )
        #expect( linear.height  == 2 )
        #expect( linear.samples == [ 10, 20, 30, 40 ] )
    }

    /// A truncated frame is refused rather than trapping.
    @Test
    func planeSamplesRejectsTruncatedData()
    {
        let bytes = self.littleEndian16( [ 10, 20 ] ) // only two of the four samples

        #expect( throws: SwiftAstro.Error.self ) { try XISFImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 2, height: 2 ) ) }
    }

    // MARK: - Detection image

    /// The detection image of a grayscale frame is its linear channel, unchanged.
    @Test
    func detectionImageLeavesAGrayscaleFrameUnchanged() throws
    {
        let bytes     = self.littleEndian16( [ 10, 20, 30, 40 ] )
        let properties = self.properties( width: 2, height: 2 )
        let linear    = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection = try #require( XISFImageDecoder.detectionImage( bytes: bytes, properties: properties ) )

        #expect( detection.channels == 1 )
        #expect( detection.pixels   == linear.samples )
    }

    /// The detection image of a colour-filter-array frame is demosaiced to a single
    /// luminance channel, so it differs from the raw mosaic while keeping its geometry.
    @Test
    func detectionImageDemosaicsAMosaicFrame() throws
    {
        // A 4 × 4 RGGB mosaic with a gradient, so the demosaic produces a distinct image.
        let values     = ( 0 ..< 16 ).map { $0 * 1000 }
        let bytes      = self.littleEndian16( values )
        let properties = self.properties( width: 4, height: 4, cfa: "RGGB" )
        let linear     = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection  = try #require( XISFImageDecoder.detectionImage( bytes: bytes, properties: properties ) )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
        #expect( detection.pixels   != linear.samples )
    }

    // MARK: - The real committed capture

    /// Opens the committed XISF capture.
    ///
    /// - Returns: The parsed, lenient XISF file.
    /// - Throws: Any error locating or parsing the file.
    private func correctedCapture() throws -> XISFFile
    {
        try XISFFile( data: try Data( contentsOf: try CaptureFixtures.url( named: "S30-M42-Corrected.xisf" ) ), options: .lenient )
    }

    /// The single-image capture enumerates to exactly one frame.
    @Test
    func enumeratesOneFrameForTheCapture() throws
    {
        #expect( try XISFImageDecoder.frames( in: try self.correctedCapture() ).count == 1 )
    }

    /// The real frame decodes to consistent geometry and finite linear samples, and
    /// its layout answers channel count, dimensions and full scale coherently.
    @Test
    func decodesContentsAndLinearImageOfTheRealFrame() throws
    {
        let frame                 = try #require( try XISFImageDecoder.frames( in: try self.correctedCapture() ).first )
        let ( bytes, properties ) = try XISFImageDecoder.contents( of: frame )
        let linear                = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width  > 0 )
        #expect( linear.height > 0 )
        #expect( linear.samples.count == linear.width * linear.height )
        #expect( linear.samples.contains { $0.isFinite } )

        #expect( XISFImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ linear.width, linear.height ] )
        #expect( [ 1, 3 ].contains( XISFImageDecoder.channelCount( from: properties ) ) )
    }

    /// The detection image of the real frame is a single luminance channel matching
    /// the frame's geometry.
    @Test
    func detectionImageOfTheRealFrame() throws
    {
        let frame                 = try #require( try XISFImageDecoder.frames( in: try self.correctedCapture() ).first )
        let ( bytes, properties ) = try XISFImageDecoder.contents( of: frame )
        let linear                = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try XISFImageDecoder.detectionImage( of: frame )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
    }
}
