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
/// - **End to end**, ``reachesADetectionImageForEveryFormatWithoutKnowingIt(capture:)``
///   drives the whole operation set — enumerate frames, read contents, decode
///   linearly, answer the header queries, read one sample, build the detection
///   image — over a real committed capture of each format, through a single
///   generic pipeline that never names a format. It is the concrete answer to the
///   milestone's question: *can a caller reach a detection image the same way
///   without knowing which format it holds?* The only thing that dispatches on
///   format is choosing which container to parse — exactly the choice a consumer
///   makes from a file's type — because container parsing is the consumer's job,
///   not the decode's.
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
    /// ``ImageDecoding/cfaPattern(from:)``, which a photographic frame answers with
    /// "none" (`nil`, never throwing) rather than by not having the member — and, now
    /// that its body has landed, answers each with real behaviour for the synthetic
    /// 8 × 4, 8-bit grayscale layout.
    @Test
    func bitmapExposesEveryOperation() throws
    {
        let properties = self.bitmapProperties
        let bytes      = self.bytes

        #expect( BitmapImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( BitmapImageDecoder.bitsPerPixel( from: properties ) == .uint8 )
        #expect( BitmapImageDecoder.channelCount( from: properties ) == 1 )
        #expect( BitmapImageDecoder.fullScale( from: properties ) == 255 )
        #expect( try BitmapImageDecoder.cfaPattern( from: properties ) == nil )

        let ( scale, offset ) = BitmapImageDecoder.scaling( from: properties )

        #expect( scale  == 1 )
        #expect( offset == 0 )

        let linear = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width == 8 )
        #expect( linear.height == 4 )
        #expect( linear.samples.count == 32 )

        let planes = try BitmapImageDecoder.planeSamples( bytes: bytes, properties: properties )

        #expect( planes.count == 1 )
        #expect( planes.first?.count == 32 )

        #expect( BitmapImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex, properties: properties ) == 0 )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) == [ 0 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties ) == [ 1 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 8, y: 0, properties: properties ) == nil )
        #expect( BitmapImageDecoder.detectionImage( bytes: bytes, properties: properties )?.channels == 1 )
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

    /// An unknown keyword throws rather than silently yielding "no pattern", so a
    /// mosaic whose pattern is unrecognised is never mistaken for a monochrome frame.
    @Test
    func colorFilterArrayThrowsOnAnUnknownPattern()
    {
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: "RGBG" ) }
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: "XYZW" ) }
        #expect( throws: SwiftAstro.Error.self ) { try ColorFilterArray.pattern( named: ""     ) }
    }

    // MARK: - End-to-end symmetry over real committed frames

    /// Runs every ``ImageDecoding`` operation on each frame a container holds and
    /// returns the detection image each frame produces — written once, using only
    /// what the protocol guarantees, and never naming a concrete format.
    ///
    /// This is the format-blind decode pipeline the symmetry rule is about: that it
    /// type-checks and behaves for every format is the proof that no format was left
    /// with a partial surface. Each of the protocol's operations is called here — the
    /// container enumeration, the contents, both linear decodes and the luminance
    /// combine, every header query, the per-pixel read-out, and both detection-image
    /// entry points — so a format that had quietly omitted or diverged on one would
    /// fail here rather than at some future call site.
    ///
    /// - Parameters:
    ///   - container: The opened container.
    ///   - decoder:   The decoder for that container's format.
    /// - Returns: One detection image per frame the container holds.
    /// - Throws: Any error the decode raises, or an expectation failure when an
    ///   operation's answer is not self-consistent.
    private func detectionImagesExercisingEveryOperation< D: ImageDecoding >( in container: D.Container, using decoder: D.Type ) throws -> [ PixelBuffer ]
    {
        try decoder.frames( in: container ).map
        {
            frame in

            let ( bytes, properties ) = try decoder.contents( of: frame )
            let dimensions            = try #require( decoder.dimensions( from: properties ) )
            let channelCount          = decoder.channelCount( from: properties )

            #expect( dimensions.width  > 0 )
            #expect( dimensions.height > 0 )
            #expect( channelCount >= 1 )

            // bitsPerPixel and fullScale label the sample format; both are present
            // members that answer a value or nil (nil for a floating-point frame,
            // which has no fixed span), never an omitted operation. cfaPattern answers
            // a pattern, nil or a throw — present for every format.
            _ = decoder.bitsPerPixel( from: properties )
            _ = decoder.fullScale( from: properties )
            _ = try decoder.cfaPattern( from: properties )

            let ( scale, _ ) = decoder.scaling( from: properties )

            #expect( scale != 0 )

            let linear = try #require( decoder.linearImage( bytes: bytes, properties: properties ) )

            #expect( linear.width  == dimensions.width )
            #expect( linear.height == dimensions.height )
            #expect( linear.samples.count == dimensions.width * dimensions.height )

            let planes = try decoder.planeSamples( bytes: bytes, properties: properties )

            #expect( planes.count == channelCount )

            let luminance = decoder.linearLuminance( fromPlanes: planes, properties: properties )

            #expect( luminance?.samples.count == dimensions.width * dimensions.height )

            let offsets = try #require( decoder.sampleByteOffsets( x: 0, y: 0, properties: properties ) )

            #expect( offsets.count == channelCount )

            let firstOffset = try #require( offsets.first )
            let sample      = decoder.decodeSample( bytes: bytes, at: bytes.startIndex + firstOffset, properties: properties )

            #expect( sample != nil )

            // Both detection-image entry points agree in shape: the bytes-based
            // primitive a consumer already holding contents calls, and the frame-based
            // convenience that reads the contents itself.
            let detectionFromBytes = decoder.detectionImage( bytes: bytes, properties: properties )
            let detection          = try decoder.detectionImage( of: frame )

            #expect( detectionFromBytes?.width    == detection.width )
            #expect( detectionFromBytes?.height   == detection.height )
            #expect( detectionFromBytes?.channels == detection.channels )

            return detection
        }
    }

    /// Opens the container the capture's file type calls for and reaches its
    /// detection images through the one format-blind pipeline above.
    ///
    /// The `switch` is the whole extent of "knowing the format": it only chooses
    /// which container parser to run, the same choice a consumer makes from a
    /// file's type. Everything after the container is opened is
    /// ``detectionImagesExercisingEveryOperation(in:using:)``, which is blind to
    /// which case produced the container.
    ///
    /// - Parameter name: A committed capture's file name, resolved by ``CaptureFixtures``.
    /// - Returns: One detection image per frame the capture holds.
    /// - Throws: ``SwiftAstro/Error`` for an unresolved or unsupported capture, or
    ///   any error the container parse or decode raises.
    private func detectionImages( fromCaptureNamed name: String ) throws -> [ PixelBuffer ]
    {
        let url = try CaptureFixtures.url( named: name )

        switch url.pathExtension.lowercased()
        {
            case "fits",
                 "fit":
                return try self.detectionImagesExercisingEveryOperation( in: try FITSFile( url: url, options: .lenient ), using: FITSImageDecoder.self )

            case "xisf":
                return try self.detectionImagesExercisingEveryOperation( in: try XISFFile( data: try Data( contentsOf: url ), options: .lenient ), using: XISFImageDecoder.self )

            case "cr3":
                return try self.detectionImagesExercisingEveryOperation( in: try RAWFile( url: url ), using: RAWImageDecoder.self )

            case "jpg",
                 "jpeg",
                 "png",
                 "tiff",
                 "tif",
                 "heic":
                guard let source = CGImageSourceCreateWithURL( url as CFURL, nil )
                else
                {
                    throw SwiftAstro.Error( message: "Could not open an image source for capture: \( name )" )
                }

                return try self.detectionImagesExercisingEveryOperation( in: source, using: BitmapImageDecoder.self )

            default:
                throw SwiftAstro.Error( message: "Unsupported capture extension: \( url.pathExtension )" )
        }
    }

    /// A caller reaches a detection image the same way for every format, knowing
    /// only a URL — the milestone's stated test, made concrete.
    ///
    /// One committed capture per format is opened and driven through the single
    /// format-blind pipeline. That the same code reaches a valid, single-channel
    /// detection image for a FITS light, an XISF frame, a Canon RAW mosaic and a
    /// processed JPEG is the proof the four surfaces are genuinely symmetric — not
    /// four independent migrations that happen to resemble one another.
    @Test( arguments:
        [
            "C6-ASI533-M104-Light.fits", // FITS — a one-shot-colour light frame
            "S30-M42-Corrected.xisf",    // XISF — a processed frame
            "C6-R7-M42-Light.cr3",       // RAW — a Canon Bayer sensor mosaic
            "C6-ASI533-M104-Final.jpg",  // Photographic — a processed JPEG
        ]
    )
    func reachesADetectionImageForEveryFormatWithoutKnowingIt( capture: String ) throws
    {
        let detectionImages = try self.detectionImages( fromCaptureNamed: capture )

        #expect( detectionImages.isEmpty == false )

        detectionImages.forEach
        {
            image in

            #expect( image.channels == 1 )
            #expect( image.width  > 0 )
            #expect( image.height > 0 )
            #expect( image.pixels.count == image.width * image.height )
        }
    }

    // MARK: - Cross-format invariants

    /// ``FITSImageDecoder/fullScale(from:)`` and ``XISFImageDecoder/fullScale(from:)``
    /// were written to agree on the full-scale span convention — `2ⁿ − 1`, applied
    /// *after* any `BSCALE`/`BZERO` — for the integer sample formats the two formats
    /// share. The two paths must not have been quietly separated by the migration:
    /// a FITS `BITPIX` and the matching XISF sample format answer the same span, and
    /// both answer `nil` for a floating-point format, which has no fixed span.
    @Test
    func fitsAndXisfAgreeOnTheFullScaleSpan()
    {
        func xisf( _ sampleFormat: XISFSampleFormat ) -> XISFImageProperties
        {
            XISFImageProperties(
                width:                   1,
                height:                  1,
                channelCount:            1,
                sampleFormat:            sampleFormat,
                byteOrder:               .little,
                pixelStorage:            .planar,
                colorSpace:              .gray,
                colorFilterArrayPattern: nil
            )
        }

        func fits( bitpix: Int64 ) -> [ FITSPropertySnapshot ]
        {
            [ FITSPropertySnapshot( name: "BITPIX", value: .integer( bitpix ) ) ]
        }

        // 8-bit — both span 2⁸ − 1.
        #expect( FITSImageDecoder.fullScale( from: fits( bitpix: 8 ) ) == 255 )
        #expect( XISFImageDecoder.fullScale( from: xisf( .uInt8 )     ) == 255 )

        // 16-bit — both span 2¹⁶ − 1.
        #expect( FITSImageDecoder.fullScale( from: fits( bitpix: 16 ) ) == 65535 )
        #expect( XISFImageDecoder.fullScale( from: xisf( .uInt16 )    ) == 65535 )

        // 32-bit integer — both span 2³² − 1.
        #expect( FITSImageDecoder.fullScale( from: fits( bitpix: 32 ) ) == 4294967295 )
        #expect( XISFImageDecoder.fullScale( from: xisf( .uInt32 )    ) == 4294967295 )

        // Floating point — neither has a fixed span.
        #expect( FITSImageDecoder.fullScale( from: fits( bitpix: -32 ) ) == nil )
        #expect( XISFImageDecoder.fullScale( from: xisf( .float32 )    ) == nil )
    }
}
