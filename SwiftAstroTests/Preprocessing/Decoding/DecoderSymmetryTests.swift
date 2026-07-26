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
@testable import SwiftAstro
import SwiftFITS
import SwiftPixel
import SwiftRAW
import SwiftXISF
import Testing

/// Guards the rule the whole shared-decoder initiative exists to enforce: every
/// format offers the *same* operations, and a format that answers "there is
/// nothing here" does so with a present member rather than a missing one.
///
/// The stated failure mode is not a bug, it is stopping early — a format left
/// with a partial surface because the remaining piece looked unnecessary. Two
/// mechanisms guard against it here:
///
/// - **At compile time**, every decoder conforms to ``ImageDecoding``. An omitted
///   operation is a conformance error, not a test somebody forgets to extend.
///   ``conformsForEveryFormat()`` pins that conformance so it cannot be dropped
///   silently.
/// - **At run time**, every operation that needs only a `Properties` value is
///   called for all four formats through the same generic helpers, so no format
///   can quietly diverge in shape.
///
/// The container- and frame-based operations (``ImageDecoding/frames(in:)``,
/// ``ImageDecoding/contents(of:)`` and ``ImageDecoding/detectionImage(of:)``) are
/// covered by conformance only at this stage: reaching them needs a real
/// container per format, and the XISF, RAW and photographic captures arrive in
/// the fixture reorganisation. They gain runtime coverage as each format's
/// decoder body lands, and this suite grows into the behavioural, format-agnostic
/// test the closing symmetry milestone requires.
struct DecoderSymmetryTests
{
    // MARK: - Synthetic properties, one per format

    /// A minimal FITS header describing an 8 × 4, 16-bit, monochrome image.
    private var fitsProperties: [ FITSPropertySnapshot ]
    {
        [
            FITSPropertySnapshot( name: "BITPIX", value: .integer( 16 ) ),
            FITSPropertySnapshot( name: "NAXIS",  value: .integer(  2 ) ),
            FITSPropertySnapshot( name: "NAXIS1", value: .integer(  8 ) ),
            FITSPropertySnapshot( name: "NAXIS2", value: .integer(  4 ) ),
        ]
    }

    /// A minimal XISF layout describing an 8 × 4, 16-bit, grayscale image.
    private var xisfProperties: XISFImageProperties
    {
        XISFImageProperties(
            width:                   8,
            height:                  4,
            channelCount:            1,
            sampleFormat:            .uInt16,
            byteOrder:               .little,
            pixelStorage:            .planar,
            colorSpace:              .gray,
            colorFilterArrayPattern: nil
        )
    }

    /// A minimal RAW layout describing an 8 × 4 monochrome sensor mosaic.
    private var rawProperties: RAWImageProperties
    {
        RAWImageProperties( width: 8, height: 4, colorFilterArrayPattern: nil, whiteLevel: 65535 )
    }

    /// A minimal photographic layout describing an 8 × 4, 8-bit grayscale bitmap.
    private var bitmapProperties: BitmapImageProperties
    {
        BitmapImageProperties( width: 8, height: 4, channelCount: 1, componentsPerPixel: 1, bytesPerComponent: 1 )
    }

    /// Enough bytes to hold an 8 × 4 image at two bytes per sample, so a
    /// truncation guard is never what makes an operation refuse.
    private var bytes: Data
    {
        Data( repeating: 0, count: 8 * 4 * 2 )
    }

    // MARK: - Compile-time symmetry

    /// Every format's decoder conforms to ``ImageDecoding``, which is what makes an
    /// omitted operation a compile error rather than an oversight.
    @Test
    func conformsForEveryFormat()
    {
        // Only a conforming type can be passed here, so each call is the assertion:
        // the identity comparison merely gives the compile-time check a run-time
        // expression to carry it.
        func witness< D: ImageDecoding >( _ decoder: D.Type ) -> ObjectIdentifier
        {
            ObjectIdentifier( decoder )
        }

        #expect( witness( FITSImageDecoder.self   ) == ObjectIdentifier( FITSImageDecoder.self   ) )
        #expect( witness( XISFImageDecoder.self   ) == ObjectIdentifier( XISFImageDecoder.self   ) )
        #expect( witness( RAWImageDecoder.self    ) == ObjectIdentifier( RAWImageDecoder.self    ) )
        #expect( witness( BitmapImageDecoder.self ) == ObjectIdentifier( BitmapImageDecoder.self ) )
    }

    // MARK: - Run-time symmetry over the properties-based operations

    /// Calls every operation that needs only a `Properties` value, asserting each
    /// is reachable and answers with the unimplemented stub's contract: the
    /// throwing operations throw, the optional ones return `nil`.
    ///
    /// - Parameters:
    ///   - decoder:    The decoder under test.
    ///   - properties: A synthetic layout for that format.
    ///   - bytes:      Sample bytes matching the layout.
    private func expectUnimplemented< D: ImageDecoding >( _ decoder: D.Type, properties: D.Properties, bytes: Data )
    {
        #expect( throws: SwiftAstro.Error.self ) { try decoder.planeSamples( bytes: bytes, properties: properties ) }
        #expect( throws: SwiftAstro.Error.self ) { try decoder.cfaPattern( from: properties ) }

        #expect( decoder.linearImage( bytes: bytes, properties: properties )                            == nil )
        #expect( decoder.linearLuminance( fromPlanes: [ [ 0 ] ], properties: properties )                == nil )
        #expect( decoder.fullScale( from: properties )                                                   == nil )
        #expect( decoder.bitsPerPixel( from: properties )                                                == nil )
        #expect( decoder.dimensions( from: properties )                                                  == nil )
        #expect( decoder.decodeSample( bytes: bytes, at: bytes.startIndex, properties: properties )       == nil )
        #expect( decoder.sampleByteOffsets( x: 0, y: 0, properties: properties )                          == nil )
        #expect( decoder.detectionImage( bytes: bytes, properties: properties )                           == nil )

        let ( scale, offset ) = decoder.scaling( from: properties )

        #expect( scale  == 0 )
        #expect( offset == 0 )
        #expect( decoder.channelCount( from: properties ) == 0 )
    }

    /// The FITS decoder exposes the whole operation set and, now that its body has
    /// landed, answers each with real behaviour for the synthetic 8 × 4 monochrome
    /// header — no operation left throwing the unimplemented sentinel.
    @Test
    func fitsExposesEveryOperation() throws
    {
        let properties = self.fitsProperties
        let bytes      = self.bytes

        #expect( FITSImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( FITSImageDecoder.bitsPerPixel( from: properties ) == .int16 )
        #expect( FITSImageDecoder.channelCount( from: properties ) == 1 )
        #expect( FITSImageDecoder.fullScale( from: properties ) == 65535 )
        #expect( try FITSImageDecoder.cfaPattern( from: properties ) == nil )

        let ( scale, offset ) = FITSImageDecoder.scaling( from: properties )

        #expect( scale  == 1 )
        #expect( offset == 0 )

        let linear = try #require( FITSImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width == 8 )
        #expect( linear.height == 4 )
        #expect( linear.samples.count == 32 )

        let planes = try FITSImageDecoder.planeSamples( bytes: bytes, properties: properties )

        #expect( planes.count == 1 )
        #expect( planes.first?.count == 32 )

        #expect( FITSImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex, properties: properties ) == 0 )
        #expect( FITSImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) == [ 0 ] )
        #expect( FITSImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties ) == [ 2 ] )
        #expect( FITSImageDecoder.sampleByteOffsets( x: 8, y: 0, properties: properties ) == nil )
        #expect( FITSImageDecoder.detectionImage( bytes: bytes, properties: properties )?.channels == 1 )
    }

    /// The XISF decoder exposes the whole operation set and, now that its body has
    /// landed, answers each with real behaviour for the synthetic 8 × 4 grayscale
    /// layout — no operation left throwing the unimplemented sentinel.
    @Test
    func xisfExposesEveryOperation() throws
    {
        let properties = self.xisfProperties
        let bytes      = self.bytes

        #expect( XISFImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( XISFImageDecoder.bitsPerPixel( from: properties ) == .int16 )
        #expect( XISFImageDecoder.channelCount( from: properties ) == 1 )
        #expect( XISFImageDecoder.fullScale( from: properties ) == 65535 )
        #expect( try XISFImageDecoder.cfaPattern( from: properties ) == nil )

        let ( scale, offset ) = XISFImageDecoder.scaling( from: properties )

        #expect( scale  == 1 )
        #expect( offset == 0 )

        let linear = try #require( XISFImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width == 8 )
        #expect( linear.height == 4 )
        #expect( linear.samples.count == 32 )

        let planes = try XISFImageDecoder.planeSamples( bytes: bytes, properties: properties )

        #expect( planes.count == 1 )
        #expect( planes.first?.count == 32 )

        #expect( XISFImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex, properties: properties ) == 0 )
        #expect( XISFImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) == [ 0 ] )
        #expect( XISFImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties ) == [ 2 ] )
        #expect( XISFImageDecoder.sampleByteOffsets( x: 8, y: 0, properties: properties ) == nil )
        #expect( XISFImageDecoder.detectionImage( bytes: bytes, properties: properties )?.channels == 1 )
    }

    /// The RAW decoder exposes the whole operation set — including the ones a
    /// single-frame, single-plane format might have been tempted to omit — and, now
    /// that its body has landed, answers each with real behaviour for the synthetic
    /// 8 × 4 monochrome mosaic.
    @Test
    func rawExposesEveryOperation() throws
    {
        let properties = self.rawProperties
        let bytes      = self.bytes

        #expect( RAWImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( RAWImageDecoder.bitsPerPixel( from: properties ) == .int16 )
        #expect( RAWImageDecoder.channelCount( from: properties ) == 1 )
        #expect( RAWImageDecoder.fullScale( from: properties ) == 65535 )
        #expect( try RAWImageDecoder.cfaPattern( from: properties ) == nil )

        let ( scale, offset ) = RAWImageDecoder.scaling( from: properties )

        #expect( scale  == 1 )
        #expect( offset == 0 )

        let linear = try #require( RAWImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width == 8 )
        #expect( linear.height == 4 )
        #expect( linear.samples.count == 32 )

        let planes = try RAWImageDecoder.planeSamples( bytes: bytes, properties: properties )

        #expect( planes.count == 1 )
        #expect( planes.first?.count == 32 )

        #expect( RAWImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex, properties: properties ) == 0 )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) == [ 0 ] )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties ) == [ 2 ] )
        #expect( RAWImageDecoder.sampleByteOffsets( x: 8, y: 0, properties: properties ) == nil )
        #expect( RAWImageDecoder.detectionImage( bytes: bytes, properties: properties )?.channels == 1 )
    }

    /// The photographic decoder exposes the whole operation set — including
    /// ``ImageDecoding/cfaPattern(from:)``, which a photographic frame answers
    /// with "none" rather than by not having the member.
    @Test
    func bitmapExposesEveryOperation()
    {
        self.expectUnimplemented( BitmapImageDecoder.self, properties: self.bitmapProperties, bytes: self.bytes )
    }

    // MARK: - The shared colour-filter-array mapping

    /// The one CFA mapping all three mosaic formats route through accepts the four
    /// 2 × 2 Bayer patterns.
    @Test
    func colorFilterArrayMapsEverySupportedPattern() throws
    {
        #expect( try ColorFilterArray.pattern( named: "BGGR" ) == .bggr )
        #expect( try ColorFilterArray.pattern( named: "GRBG" ) == .grbg )
        #expect( try ColorFilterArray.pattern( named: "RGGB" ) == .rggb )
        #expect( try ColorFilterArray.pattern( named: "GBRG" ) == .gbrg )
    }

    /// An unknown keyword throws rather than silently yielding "no pattern" — the
    /// behaviour the app and the removed decoder both had, and the one the shared
    /// mapping adopts, so a mosaic is never mistaken for a monochrome frame.
    @Test
    func colorFilterArrayThrowsOnAnUnknownPattern()
    {
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: "RGBG" ) }
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: "XYZW" ) }
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: ""     ) }
    }
}
