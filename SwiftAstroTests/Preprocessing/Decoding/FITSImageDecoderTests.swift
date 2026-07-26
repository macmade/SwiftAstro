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
import SwiftFITS
import SwiftPixel
import Testing

/// Behavioural tests for ``FITSImageDecoder`` against real committed FITS frames:
/// the one-shot-colour light frames and the mono reference frame, decoded through
/// the shared decoder the application also uses.
///
/// RGB colour cubes and multi-image cubes are not among the frames committed to
/// this repository's `Test Files`, so those geometries are covered by the
/// application's golden detection-image baseline rather than here.
struct FITSImageDecoderTests
{
    /// Opens a committed FITS capture by file name.
    ///
    /// - Parameter name: The capture file name (with extension).
    /// - Returns: The parsed, lenient FITS file.
    /// - Throws: Any error locating or parsing the file.
    private func file( named name: String ) throws -> FITSFile
    {
        try FITSFile( url: try CaptureFixtures.url( named: name ), options: .lenient )
    }

    /// A single-image FITS capture enumerates to exactly one frame.
    @Test
    func enumeratesOneFrameForASingleImageCapture() throws
    {
        let frames = try FITSImageDecoder.frames( in: try self.file( named: "C6-ASI533-M104-Light.fits" ) )

        #expect( frames.count == 1 )
    }

    /// A real frame decodes to consistent geometry and finite linear samples, and
    /// its header answers channel count, dimensions and full scale coherently.
    @Test
    func decodesContentsAndLinearImageOfARealFrame() throws
    {
        let frame                 = try #require( try FITSImageDecoder.frames( in: try self.file( named: "C6-ASI533-M104-Light.fits" ) ).first )
        let ( bytes, properties ) = try FITSImageDecoder.contents( of: frame )
        let linear                = try #require( FITSImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width  > 0 )
        #expect( linear.height > 0 )
        #expect( linear.samples.count == linear.width * linear.height )
        #expect( linear.samples.contains { $0.isFinite } )

        #expect( FITSImageDecoder.channelCount( from: properties ) == 1 )
        #expect( FITSImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ linear.width, linear.height ] )

        // A 16-bit integer FITS frame has the full-scale span 2¹⁶ − 1.
        if FITSImageDecoder.bitsPerPixel( from: properties ) == .int16
        {
            #expect( FITSImageDecoder.fullScale( from: properties ) == 65535 )
        }
    }

    /// The one-shot-colour reference frame reports its `BAYERPAT` pattern through
    /// the shared mapping.
    @Test
    func readsBayerpatOfTheRealOneShotColorFrame() throws
    {
        let url                = try FITSTestImage.url( resource: FITSTestImage.realLightFrameName )
        let frame              = try #require( try FITSImageDecoder.frames( in: try FITSFile( url: url, options: .lenient ) ).first )
        let ( _, properties )  = try FITSImageDecoder.contents( of: frame )

        #expect( try FITSImageDecoder.cfaPattern( from: properties ) == .rggb )
    }

    /// A monochrome frame carries no colour-filter-array pattern.
    @Test
    func monochromeFrameHasNoColorFilterArrayPattern() throws
    {
        let url               = try FITSTestImage.url( resource: FITSTestImage.esaM35BlueFrameName )
        let frame             = try #require( try FITSImageDecoder.frames( in: try FITSFile( url: url, options: .lenient ) ).first )
        let ( _, properties ) = try FITSImageDecoder.contents( of: frame )

        #expect( try FITSImageDecoder.cfaPattern( from: properties ) == nil )
    }

    /// The detection image of a mosaic frame is demosaiced to a single luminance
    /// channel, so it differs from the raw mosaic while keeping its geometry.
    @Test
    func detectionImageDemosaicsAMosaicFrame() throws
    {
        let url                   = try FITSTestImage.url( resource: FITSTestImage.realLightFrameName )
        let frame                 = try #require( try FITSImageDecoder.frames( in: try FITSFile( url: url, options: .lenient ) ).first )
        let ( bytes, properties ) = try FITSImageDecoder.contents( of: frame )
        let linear                = try #require( FITSImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try FITSImageDecoder.detectionImage( of: frame )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
        #expect( detection.pixels   != linear.samples )
    }

    /// The detection image of a monochrome frame is its linear channel, unchanged.
    @Test
    func detectionImageLeavesAMonochromeFrameUnchanged() throws
    {
        let url                   = try FITSTestImage.url( resource: FITSTestImage.esaM35BlueFrameName )
        let frame                 = try #require( try FITSImageDecoder.frames( in: try FITSFile( url: url, options: .lenient ) ).first )
        let ( bytes, properties ) = try FITSImageDecoder.contents( of: frame )
        let linear                = try #require( FITSImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try FITSImageDecoder.detectionImage( of: frame )

        #expect( detection.pixels == linear.samples )
    }

    /// The per-pixel read-out (``FITSImageDecoder/sampleByteOffsets(x:y:properties:)``
    /// plus ``FITSImageDecoder/decodeSample(bytes:at:properties:)``) reads the same
    /// raw sample the plane decode produces, and advances by one sample per column.
    @Test
    func sampleReadOutMatchesThePlaneDecode() throws
    {
        let url                   = try FITSTestImage.url( resource: FITSTestImage.esaM35BlueFrameName )
        let frame                 = try #require( try FITSImageDecoder.frames( in: try FITSFile( url: url, options: .lenient ) ).first )
        let ( bytes, properties ) = try FITSImageDecoder.contents( of: frame )
        let plane                 = try #require( try FITSImageDecoder.planeSamples( bytes: bytes, properties: properties ).first )
        let bitsPerPixel          = try #require( FITSImageDecoder.bitsPerPixel( from: properties ) )
        let bytesPerSample        = try #require( bitsPerPixel.size( numberOfPixels: 1 ) )

        let offset = try #require( FITSImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: properties )?.first )
        let raw    = try #require( FITSImageDecoder.decodeSample( bytes: bytes, at: bytes.startIndex + offset, properties: properties ) )

        // The top-left sample the read-out decodes is the plane's first sample (a
        // clean reference frame's corner is a finite background value).
        if plane.first?.isFinite == true
        {
            #expect( raw == plane.first )
        }

        // The next column is exactly one sample further into the bytes.
        #expect( FITSImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: properties )?.first == bytesPerSample )
    }

    /// An integer `BLANK` sentinel decodes to NaN, so undefined pixels are dropped
    /// by the non-finite-filtering statistics exactly as a float image's NaN blanks
    /// already are.
    @Test
    func linearImageMasksIntegerBlankPixels() throws
    {
        let properties =
            [
                FITSPropertySnapshot( name: "BITPIX", value: .integer( 8 ) ),
                FITSPropertySnapshot( name: "NAXIS",  value: .integer( 2 ) ),
                FITSPropertySnapshot( name: "NAXIS1", value: .integer( 2 ) ),
                FITSPropertySnapshot( name: "NAXIS2", value: .integer( 2 ) ),
                FITSPropertySnapshot( name: "BLANK",  value: .integer( 255 ) ),
            ]

        let data   = Data( [ 10, 255, 30, 40 ] )
        let result = try #require( FITSImageDecoder.linearImage( bytes: data, properties: properties ) )

        #expect( result.samples[ 0 ] == 10 )
        #expect( result.samples[ 1 ].isNaN )
        #expect( result.samples[ 2 ] == 30 )
        #expect( result.samples[ 3 ] == 40 )
    }

    /// `BLANK` names the raw stored value, so a blank pixel decodes to NaN rather
    /// than to the `BZERO`/`BSCALE`-rescaled sentinel.
    @Test
    func linearImageMasksBlankBeforeScaling() throws
    {
        let properties =
            [
                FITSPropertySnapshot( name: "BITPIX", value: .integer( 16 ) ),
                FITSPropertySnapshot( name: "NAXIS",  value: .integer( 2 ) ),
                FITSPropertySnapshot( name: "NAXIS1", value: .integer( 2 ) ),
                FITSPropertySnapshot( name: "NAXIS2", value: .integer( 1 ) ),
                FITSPropertySnapshot( name: "BZERO",  value: .integer( 32768 ) ),
                FITSPropertySnapshot( name: "BLANK",  value: .integer( -1 ) ),
            ]

        // Two big-endian Int16 samples: -1 (the BLANK sentinel) and 5.
        let data   = Data( [ 0xFF, 0xFF, 0x00, 0x05 ] )
        let result = try #require( FITSImageDecoder.linearImage( bytes: data, properties: properties ) )

        #expect( result.samples[ 0 ].isNaN )
        #expect( result.samples[ 1 ] == 32773 )
    }
}
