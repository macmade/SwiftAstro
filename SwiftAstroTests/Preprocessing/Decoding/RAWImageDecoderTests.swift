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
import SwiftRAW
import Testing

/// Behavioural tests for ``RAWImageDecoder``: the host-order sample decode, the
/// single-plane extraction, the crop-origin colour-filter-array phase and the
/// detection image over synthetic layouts, plus an end-to-end pass over the
/// committed `C6-R7-M42-Light.cr3` capture — the frame that is the reason SwiftAstro
/// must reach a detection image from a RAW file at all.
///
/// Synthetic bytes exercise the parts that need only a ``RAWImageProperties`` value;
/// the container- and frame-based operations (``RAWImageDecoder/frames(in:)``,
/// ``RAWImageDecoder/contents(of:)`` and ``RAWImageDecoder/detectionImage(of:)``) are
/// covered against the real capture, since building a ``RAWFile`` needs a parsed file.
struct RAWImageDecoderTests
{
    // MARK: - Synthetic helpers

    /// A synthetic RAW layout.
    ///
    /// - Parameters:
    ///   - width:      The visible width.
    ///   - height:     The visible height.
    ///   - cfa:        The colour-filter-array pattern name, or `nil`.
    ///   - whiteLevel: The sensor's saturation level, or `nil`.
    /// - Returns: The layout.
    private func properties( width: Int, height: Int, cfa: String? = nil, whiteLevel: Double? = 65535 ) -> RAWImageProperties
    {
        RAWImageProperties( width: width, height: height, colorFilterArrayPattern: cfa, whiteLevel: whiteLevel )
    }

    /// Encodes 16-bit samples in host byte order — the mosaic is produced and
    /// consumed in-process, so no endianness swap applies.
    ///
    /// - Parameter values: The sample values.
    /// - Returns: The host-order bytes.
    private func mosaic( _ values: [ Int ] ) -> Data
    {
        values.map { UInt16( $0 ) }.withUnsafeBytes { Data( $0 ) }
    }

    // MARK: - Header interpretation

    /// Sensor counts are the physical values, so ``RAWImageDecoder/scaling(from:)``
    /// is the identity transform.
    @Test
    func scalingIsTheIdentity()
    {
        let ( scale, offset ) = RAWImageDecoder.scaling( from: self.properties( width: 2, height: 1 ) )

        #expect( scale  == 1 )
        #expect( offset == 0 )
    }

    /// The full scale is the sensor's reported white level, not implied by the
    /// sample width — a 14-bit sensor stored in 16 bits saturates at its own level.
    @Test
    func fullScaleIsTheWhiteLevel()
    {
        #expect( RAWImageDecoder.fullScale( from: self.properties( width: 1, height: 1, whiteLevel: 16383 ) ) == 16383 )
        #expect( RAWImageDecoder.fullScale( from: self.properties( width: 1, height: 1, whiteLevel: nil ) ) == nil )
    }

    /// A cropped mosaic is always 16-bit.
    @Test
    func bitsPerPixelIsSixteenBit()
    {
        #expect( RAWImageDecoder.bitsPerPixel( from: self.properties( width: 1, height: 1 ) ) == .int16 )
    }

    /// A sensor mosaic is a single channel, colour-filter array or not.
    @Test
    func channelCountIsOne()
    {
        #expect( RAWImageDecoder.channelCount( from: self.properties( width: 2, height: 2, cfa: "RGGB" ) ) == 1 )
        #expect( RAWImageDecoder.channelCount( from: self.properties( width: 2, height: 2, cfa: nil ) ) == 1 )
    }

    /// The dimensions come from the layout, and a non-positive one is rejected.
    @Test
    func dimensionsRejectNonPositiveGeometry()
    {
        #expect( RAWImageDecoder.dimensions( from: self.properties( width: 8, height: 4 ) ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( RAWImageDecoder.dimensions( from: self.properties( width: 0, height: 4 ) ) == nil )
    }

    /// A named colour-filter array routes through the shared mapping; an absent one
    /// answers `nil`; an unsupported one throws.
    @Test
    func cfaPatternRoutesThroughTheSharedMapping() throws
    {
        #expect( try RAWImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: "RGGB" ) ) == .rggb )
        #expect( try RAWImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: nil ) ) == nil )
        #expect( throws: SwiftAstro.Error.self ) { try RAWImageDecoder.cfaPattern( from: self.properties( width: 2, height: 2, cfa: "XYZW" ) ) }
    }

    // MARK: - Sample decoding

    /// A single sample decodes in host byte order, and reading past the end answers
    /// `nil` rather than trapping.
    @Test
    func decodeSampleReadsHostOrderAndBounds()
    {
        let bytes      = self.mosaic( [ 258, 65535 ] )
        let properties = self.properties( width: 2, height: 1 )

        #expect( RAWImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex,     properties: properties ) == 258 )
        #expect( RAWImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex + 2, properties: properties ) == 65535 )

        // One byte short of a whole 16-bit sample: refused, not trapped.
        #expect( RAWImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex + 3, properties: properties ) == nil )
    }

    /// The single-channel byte offset advances by one 16-bit sample per column and
    /// per row, and out-of-bounds coordinates answer `nil`.
    @Test
    func sampleByteOffsetsCoverTheSingleChannel()
    {
        let properties = self.properties( width: 3, height: 2 )

        #expect( RAWImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) == [ 0 ] )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties ) == [ 2 ] )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 0, y: 1, properties: properties ) == [ 6 ] )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 3, y: 0, properties: properties ) == nil )
    }

    // MARK: - Plane extraction and luminance

    /// The mosaic decodes to exactly one plane holding every sample, in row-major
    /// order.
    @Test
    func planeSamplesYieldsOnePlane() throws
    {
        let bytes  = self.mosaic( [ 10, 20, 30, 40, 50, 60 ] )
        let planes = try RAWImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 3, height: 2 ) )

        #expect( planes.count == 1 )
        #expect( planes.first == [ 10, 20, 30, 40, 50, 60 ] )
    }

    /// ``RAWImageDecoder/linearImage(bytes:properties:)`` is the raw mosaic samples
    /// at the image geometry.
    @Test
    func linearImageIsTheRawMosaic() throws
    {
        let bytes  = self.mosaic( [ 10, 20, 30, 40, 50, 60 ] )
        let linear = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: self.properties( width: 3, height: 2 ) ) )

        #expect( linear.width   == 3 )
        #expect( linear.height  == 2 )
        #expect( linear.samples == [ 10, 20, 30, 40, 50, 60 ] )
    }

    /// A single plane's linear luminance is that plane, unchanged.
    @Test
    func linearLuminanceOfOnePlaneIsThatPlane() throws
    {
        let luminance = try #require( RAWImageDecoder.linearLuminance( fromPlanes: [ [ 10, 20, 30, 40 ] ], properties: self.properties( width: 2, height: 2 ) ) )

        #expect( luminance.samples == [ 10, 20, 30, 40 ] )
    }

    /// A truncated mosaic is refused rather than trapping.
    @Test
    func planeSamplesRejectsTruncatedData()
    {
        let bytes = self.mosaic( [ 10, 20 ] ) // only two of the four samples

        #expect( throws: SwiftAstro.Error.self ) { try RAWImageDecoder.planeSamples( bytes: bytes, properties: self.properties( width: 2, height: 2 ) ) }
    }

    // MARK: - Detection image

    /// The detection image of a monochrome sensor is its linear channel, unchanged.
    @Test
    func detectionImageLeavesAMonochromeSensorUnchanged() throws
    {
        let bytes      = self.mosaic( [ 10, 20, 30, 40 ] )
        let properties = self.properties( width: 2, height: 2, cfa: nil )
        let linear     = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection  = try #require( RAWImageDecoder.detectionImage( bytes: bytes, properties: properties ) )

        #expect( detection.channels == 1 )
        #expect( detection.pixels   == linear.samples )
    }

    /// The detection image of a colour-filter-array mosaic is demosaiced to a single
    /// luminance channel, so it differs from the raw mosaic while keeping its geometry.
    @Test
    func detectionImageDemosaicsAMosaic() throws
    {
        let values     = ( 0 ..< 16 ).map { $0 * 1000 }
        let bytes      = self.mosaic( values )
        let properties = self.properties( width: 4, height: 4, cfa: "RGGB" )
        let linear     = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection  = try #require( RAWImageDecoder.detectionImage( bytes: bytes, properties: properties ) )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
        #expect( detection.pixels   != linear.samples )
    }

    // MARK: - The crop-origin colour-filter-array phase

    /// The Bayer `filters` value for a canonical RGGB sensor (LibRAW encoding).
    private static let rggbFilters: UInt32 = 0x9494_9494

    /// With no margins, the pattern is the sensor's native phase.
    @Test
    func derivesNativePattern()
    {
        let cfa = RAWCFAPattern( filters: Self.rggbFilters, colorDescription: "RGBG" )

        #expect( RAWImageProperties.cfaPatternString( cfa: cfa, leftMargin: 0, topMargin: 0 ) == "RGGB" )
    }

    /// An odd left margin shifts the phase by one column (RGGB → GRBG).
    @Test
    func oddLeftMarginShiftsColumn()
    {
        let cfa = RAWCFAPattern( filters: Self.rggbFilters, colorDescription: "RGBG" )

        #expect( RAWImageProperties.cfaPatternString( cfa: cfa, leftMargin: 1, topMargin: 0 ) == "GRBG" )
    }

    /// An odd top margin shifts the phase by one row (RGGB → GBRG).
    @Test
    func oddTopMarginShiftsRow()
    {
        let cfa = RAWCFAPattern( filters: Self.rggbFilters, colorDescription: "RGBG" )

        #expect( RAWImageProperties.cfaPatternString( cfa: cfa, leftMargin: 0, topMargin: 1 ) == "GBRG" )
    }

    /// A non-Bayer sensor (no CFA) has no pattern, so it renders as monochrome.
    @Test
    func nonBayerSensorHasNoPattern()
    {
        let cfa = RAWCFAPattern( filters: 0, colorDescription: "" )

        #expect( RAWImageProperties.cfaPatternString( cfa: cfa, leftMargin: 0, topMargin: 0 ) == nil )
    }

    // MARK: - The real committed capture

    /// Opens the committed RAW capture.
    ///
    /// - Returns: The opened, unpacked RAW file.
    /// - Throws: Any error locating or opening the file.
    private func capture() throws -> RAWFile
    {
        try RAWFile( url: try CaptureFixtures.url( named: "C6-R7-M42-Light.cr3" ) )
    }

    /// The single-image capture enumerates to exactly one frame.
    @Test
    func enumeratesOneFrameForTheCapture() throws
    {
        #expect( try RAWImageDecoder.frames( in: try self.capture() ).count == 1 )
    }

    /// The real frame crops and decodes to consistent geometry and finite samples,
    /// and its layout answers a single channel and its dimensions coherently.
    @Test
    func decodesContentsAndLinearImageOfTheRealFrame() throws
    {
        let frame                 = try #require( try RAWImageDecoder.frames( in: try self.capture() ).first )
        let ( bytes, properties ) = try RAWImageDecoder.contents( of: frame )
        let linear                = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width  > 0 )
        #expect( linear.height > 0 )
        #expect( linear.samples.count == linear.width * linear.height )
        #expect( linear.samples.contains { $0.isFinite } )

        #expect( RAWImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ linear.width, linear.height ] )
        #expect( RAWImageDecoder.channelCount( from: properties ) == 1 )
    }

    /// The one-shot-colour capture reports a colour-filter-array pattern through the
    /// shared mapping.
    @Test
    func realFrameReportsItsColorFilterArray() throws
    {
        let frame             = try #require( try RAWImageDecoder.frames( in: try self.capture() ).first )
        let ( _, properties ) = try RAWImageDecoder.contents( of: frame )

        #expect( try RAWImageDecoder.cfaPattern( from: properties ) != nil )
    }

    /// The detection image of the real frame is a single luminance channel matching
    /// the frame's geometry.
    @Test
    func detectionImageOfTheRealFrame() throws
    {
        let frame                 = try #require( try RAWImageDecoder.frames( in: try self.capture() ).first )
        let ( bytes, properties ) = try RAWImageDecoder.contents( of: frame )
        let linear                = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try RAWImageDecoder.detectionImage( of: frame )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
    }
}
