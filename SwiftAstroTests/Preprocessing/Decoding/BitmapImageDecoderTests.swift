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

import AppKit
import CoreGraphics
import Foundation
import ImageIO
@testable import SwiftAstro
import SwiftPixel
import Testing

/// Behavioural tests for ``BitmapImageDecoder``: the interleaved sample decode with
/// its padding-component skip, the per-channel plane extraction, the luminance
/// detection image (no demosaic branch), and the container operations — frame
/// enumeration, the EXIF-orientation upright and the canonical draw — over both a
/// real committed `*-Final.jpg` capture and self-contained bitmaps synthesised in
/// memory.
///
/// Synthetic `Data` exercises the parts that need only a ``BitmapImageProperties``
/// value; the container- and frame-based operations (``BitmapImageDecoder/frames(in:)``,
/// ``BitmapImageDecoder/contents(of:)`` and ``BitmapImageDecoder/detectionImage(of:)``)
/// need a real `CGImageSource`, so they run against a committed JPEG capture and
/// against PNG/TIFF sources built in memory. The synthetic PNG/TIFF/HEIC *files*
/// (`PhotoRGB.png`, `PhotoGray16.tiff`, the multi-frame HEIC, the EXIF-oriented
/// TIFF, …) are not committed to this library's `Test Files`, so this target does
/// not reach them; downstream end-to-end tests cover those, while these tests
/// reproduce the same behaviours from
/// in-memory containers so the library validates its own decoder without them.
struct BitmapImageDecoderTests
{
    // MARK: - Synthetic layouts

    /// A synthetic grayscale layout: one channel, one stored component per pixel.
    ///
    /// - Parameters:
    ///   - width:             The image width.
    ///   - height:            The image height.
    ///   - bytesPerComponent: The number of bytes per component (`1` or `2`).
    /// - Returns: The layout.
    private func gray( width: Int, height: Int, bytesPerComponent: Int = 1 ) -> BitmapImageProperties
    {
        BitmapImageProperties( width: width, height: height, channelCount: 1, componentsPerPixel: 1, bytesPerComponent: bytesPerComponent )
    }

    /// A synthetic colour layout: three meaningful channels stored `RGBX`, the fourth
    /// component the padding CoreGraphics requires.
    ///
    /// - Parameters:
    ///   - width:             The image width.
    ///   - height:            The image height.
    ///   - bytesPerComponent: The number of bytes per component (`1` or `2`).
    /// - Returns: The layout.
    private func color( width: Int, height: Int, bytesPerComponent: Int = 1 ) -> BitmapImageProperties
    {
        BitmapImageProperties( width: width, height: height, channelCount: 3, componentsPerPixel: 4, bytesPerComponent: bytesPerComponent )
    }

    /// Packs 8-bit component values into their host-order bytes.
    ///
    /// - Parameter values: The component values.
    /// - Returns: The bytes.
    private func bytes8( _ values: [ Int ] ) -> Data
    {
        Data( values.map { UInt8( $0 ) } )
    }

    /// Packs 16-bit component values into their host-order bytes — the byte order the
    /// loader draws into and the decoder reads back.
    ///
    /// - Parameter values: The component values.
    /// - Returns: The host-order bytes.
    private func bytes16( _ values: [ Int ] ) -> Data
    {
        values.map { UInt16( $0 ) }.withUnsafeBytes { Data( $0 ) }
    }

    // MARK: - Header interpretation

    /// A drawn bitmap's components are already their stored values, so
    /// ``BitmapImageDecoder/scaling(from:)`` is the identity transform.
    @Test
    func scalingIsTheIdentity()
    {
        let ( scale, offset ) = BitmapImageDecoder.scaling( from: self.gray( width: 2, height: 1 ) )

        #expect( scale  == 1 )
        #expect( offset == 0 )
    }

    /// The full scale is the span of the component width — `255` for an 8-bit bitmap,
    /// `65535` for a 16-bit one — not the meaningful channel count.
    @Test
    func fullScaleSpansTheComponentWidth()
    {
        #expect( BitmapImageDecoder.fullScale( from: self.gray( width: 1, height: 1, bytesPerComponent: 1 ) )  == 255 )
        #expect( BitmapImageDecoder.fullScale( from: self.gray( width: 1, height: 1, bytesPerComponent: 2 ) )  == 65535 )
        #expect( BitmapImageDecoder.fullScale( from: self.color( width: 1, height: 1, bytesPerComponent: 2 ) ) == 65535 )
    }

    /// The sample format reflects the component width: 8-bit is `.uint8`, 16-bit is
    /// `.int16` — the label the plane render already used.
    @Test
    func bitsPerPixelReflectsTheComponentWidth()
    {
        #expect( BitmapImageDecoder.bitsPerPixel( from: self.gray( width: 1, height: 1, bytesPerComponent: 1 ) )  == .uint8 )
        #expect( BitmapImageDecoder.bitsPerPixel( from: self.color( width: 1, height: 1, bytesPerComponent: 2 ) ) == .int16 )
    }

    /// The meaningful channel count is the layout's — `3` for colour, `1` for
    /// grayscale — never the four stored components a colour bitmap carries.
    @Test
    func channelCountIsTheMeaningfulChannels()
    {
        #expect( BitmapImageDecoder.channelCount( from: self.color( width: 2, height: 2 ) ) == 3 )
        #expect( BitmapImageDecoder.channelCount( from: self.gray( width: 2, height: 2 ) )  == 1 )
    }

    /// The dimensions come from the layout, and a non-positive one is rejected.
    @Test
    func dimensionsRejectNonPositiveGeometry()
    {
        #expect( BitmapImageDecoder.dimensions( from: self.gray( width: 8, height: 4 ) ).map { [ $0.width, $0.height ] } == [ 8, 4 ] )
        #expect( BitmapImageDecoder.dimensions( from: self.gray( width: 0, height: 4 ) ) == nil )
    }

    /// A photographic frame never carries a colour-filter array, so
    /// ``BitmapImageDecoder/cfaPattern(from:)`` answers `nil` — for colour and
    /// grayscale alike — and never throws, unlike the mosaic formats.
    @Test
    func cfaPatternIsAlwaysNil() throws
    {
        #expect( try BitmapImageDecoder.cfaPattern( from: self.color( width: 2, height: 2 ) ) == nil )
        #expect( try BitmapImageDecoder.cfaPattern( from: self.gray( width: 2, height: 2 ) )  == nil )
    }

    // MARK: - Sample decoding

    /// A single 8-bit sample decodes to its stored value, and a 16-bit one decodes in
    /// host byte order; reading past the end answers `nil` rather than trapping.
    @Test
    func decodeSampleReadsHostOrderAndBounds()
    {
        let eight = self.bytes8( [ 0, 128, 255 ] )
        let gray8 = self.gray( width: 3, height: 1, bytesPerComponent: 1 )

        #expect( BitmapImageDecoder.decodeSample( bytes: eight, at: eight.startIndex,     properties: gray8 ) == 0 )
        #expect( BitmapImageDecoder.decodeSample( bytes: eight, at: eight.startIndex + 1, properties: gray8 ) == 128 )
        #expect( BitmapImageDecoder.decodeSample( bytes: eight, at: eight.startIndex + 3, properties: gray8 ) == nil )

        let sixteen = self.bytes16( [ 258, 65535 ] )
        let gray16  = self.gray( width: 2, height: 1, bytesPerComponent: 2 )

        #expect( BitmapImageDecoder.decodeSample( bytes: sixteen, at: sixteen.startIndex,     properties: gray16 ) == 258 )
        #expect( BitmapImageDecoder.decodeSample( bytes: sixteen, at: sixteen.startIndex + 2, properties: gray16 ) == 65535 )

        // One byte short of a whole 16-bit sample: refused, not trapped.
        #expect( BitmapImageDecoder.decodeSample( bytes: sixteen, at: sixteen.startIndex + 3, properties: gray16 ) == nil )
    }

    /// A colour coordinate resolves to one byte offset per meaningful channel, the
    /// stored padding component skipped, advancing by the whole pixel per column.
    @Test
    func sampleByteOffsetsSkipThePaddingComponent()
    {
        let eight = self.color( width: 3, height: 2, bytesPerComponent: 1 )

        #expect( BitmapImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: eight ) == [ 0, 1, 2 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: eight ) == [ 4, 5, 6 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 0, y: 1, properties: eight ) == [ 12, 13, 14 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 3, y: 0, properties: eight ) == nil )

        let sixteen = self.color( width: 2, height: 1, bytesPerComponent: 2 )

        #expect( BitmapImageDecoder.sampleByteOffsets( x: 0, y: 0, properties: sixteen ) == [ 0, 2, 4 ] )
        #expect( BitmapImageDecoder.sampleByteOffsets( x: 1, y: 0, properties: sixteen ) == [ 8, 10, 12 ] )
    }

    // MARK: - Plane extraction and luminance

    /// The interleaved colour bytes decode to one plane per meaningful channel, the
    /// padding component dropped.
    @Test
    func planeSamplesSkipsThePaddingComponent() throws
    {
        // Two RGBX pixels: (10, 20, 30, pad) and (40, 50, 60, pad).
        let bytes  = self.bytes8( [ 10, 20, 30, 200, 40, 50, 60, 201 ] )
        let planes = try BitmapImageDecoder.planeSamples( bytes: bytes, properties: self.color( width: 2, height: 1 ) )

        #expect( planes.count == 3 )
        #expect( planes[ 0 ]  == [ 10, 40 ] )
        #expect( planes[ 1 ]  == [ 20, 50 ] )
        #expect( planes[ 2 ]  == [ 30, 60 ] )
    }

    /// A grayscale image decodes to exactly one plane holding every sample.
    @Test
    func planeSamplesYieldsOnePlaneForGrayscale() throws
    {
        let bytes  = self.bytes8( [ 10, 20, 30, 40, 50, 60 ] )
        let planes = try BitmapImageDecoder.planeSamples( bytes: bytes, properties: self.gray( width: 3, height: 2 ) )

        #expect( planes.count == 1 )
        #expect( planes.first == [ 10, 20, 30, 40, 50, 60 ] )
    }

    /// A truncated buffer is refused rather than trapping.
    @Test
    func planeSamplesRejectsTruncatedData()
    {
        let bytes = self.bytes8( [ 10, 20, 30, 200 ] ) // only one of the two RGBX pixels

        #expect( throws: SwiftAstro.Error.self ) { try BitmapImageDecoder.planeSamples( bytes: bytes, properties: self.color( width: 2, height: 1 ) ) }
    }

    /// ``BitmapImageDecoder/linearImage(bytes:properties:)`` is the per-pixel mean of
    /// the meaningful channels — the domain the detection image is built in.
    @Test
    func linearImageIsTheLuminanceMean() throws
    {
        // (10, 20, 30) → 20 ; (40, 50, 60) → 50.
        let bytes  = self.bytes8( [ 10, 20, 30, 0, 40, 50, 60, 0 ] )
        let linear = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: self.color( width: 2, height: 1 ) ) )

        #expect( linear.width   == 2 )
        #expect( linear.height  == 1 )
        #expect( linear.samples == [ 20, 50 ] )
    }

    /// A grayscale image's linear image is its single channel, unchanged.
    @Test
    func linearImageOfGrayscaleIsTheChannel() throws
    {
        let bytes  = self.bytes8( [ 10, 20, 30, 40 ] )
        let linear = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: self.gray( width: 2, height: 2 ) ) )

        #expect( linear.samples == [ 10, 20, 30, 40 ] )
    }

    /// Combining planes is their per-pixel mean.
    @Test
    func linearLuminanceOfPlanesIsTheMean() throws
    {
        let luminance = try #require( BitmapImageDecoder.linearLuminance( fromPlanes: [ [ 10, 40 ], [ 20, 50 ], [ 30, 60 ] ], properties: self.color( width: 2, height: 1 ) ) )

        #expect( luminance.samples == [ 20, 50 ] )
    }

    // MARK: - Detection image

    /// The detection image is the frame's single-channel luminance, with no demosaic
    /// branch — a photographic frame is never a mosaic — so it matches the linear image.
    @Test
    func detectionImageIsSingleChannelLuminance() throws
    {
        let bytes      = self.bytes8( [ 10, 20, 30, 0, 40, 50, 60, 0 ] )
        let properties = self.color( width: 2, height: 1 )
        let linear     = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection  = try #require( BitmapImageDecoder.detectionImage( bytes: bytes, properties: properties ) )

        #expect( detection.channels == 1 )
        #expect( detection.width    == 2 )
        #expect( detection.height   == 1 )
        #expect( detection.pixels   == linear.samples )
    }

    // MARK: - In-memory containers

    /// Draws a solid-colour `CGImage`.
    ///
    /// - Parameters:
    ///   - width:  The width.
    ///   - height: The height.
    ///   - gray:   Whether to draw a single-channel grayscale image.
    /// - Returns: The image.
    /// - Throws: When a bitmap context or image cannot be created.
    private func makeImage( width: Int, height: Int, gray: Bool = false ) throws -> CGImage
    {
        let space      = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let components = gray ? 1 : 4
        let info       = ( gray ? CGImageAlphaInfo.none : CGImageAlphaInfo.premultipliedLast ).rawValue

        let context = try #require( CGContext( data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * components, space: space, bitmapInfo: info ) )

        context.setFillColor( red: 0.25, green: 0.5, blue: 0.75, alpha: 1 )
        context.fill( CGRect( x: 0, y: 0, width: width, height: height ) )

        return try #require( context.makeImage() )
    }

    /// Authors a container's bytes with `NSBitmapImageRep` and opens them as a
    /// `CGImageSource`.
    ///
    /// `CGImageDestination` — the direct way to author a container — is not importable
    /// in this test target, whose C++ interoperability (needed for the RAW library)
    /// hides it, so `NSBitmapImageRep` authors the PNG and multi-page TIFF bytes
    /// instead. It cannot tag an EXIF orientation, which is why the upright path is
    /// driven through a hand-built ``BitmapImageFrame`` below.
    ///
    /// - Parameters:
    ///   - images: The images to encode, in order.
    ///   - type:   The bitmap file type to author.
    /// - Returns: The opened image source.
    /// - Throws: When the bytes cannot be authored or reopened.
    private func makeSource( images: [ CGImage ], type: NSBitmapImageRep.FileType ) throws -> CGImageSource
    {
        let reps = images.map { NSBitmapImageRep( cgImage: $0 ) }
        let data = try #require( NSBitmapImageRep.representationOfImageReps( in: reps, using: type, properties: [ : ] ) )

        return try #require( CGImageSourceCreateWithData( data as CFData, nil ) )
    }

    /// Every image in a multi-frame container is enumerated, in order — the uniform
    /// answer, not a single-frame special case — each defaulting to the no-transform
    /// orientation when the container carries none.
    @Test
    func enumeratesEveryFrameOfAMultiFrameContainer() throws
    {
        let source = try self.makeSource( images: [ try self.makeImage( width: 4, height: 2 ), try self.makeImage( width: 4, height: 2 ) ], type: .tiff )
        let frames = try BitmapImageDecoder.frames( in: source )

        #expect( frames.count == 2 )
        #expect( frames.map( \.index )       == [ 0, 1 ] )
        #expect( frames.map( \.orientation ) == [ 1, 1 ] )
    }

    /// A single-image container enumerates to exactly one frame; contents draws it and
    /// its detection image is a single-channel luminance at the drawn geometry.
    @Test
    func decodesContentsAndDetectionImageOfAnInMemoryFrame() throws
    {
        let source                = try self.makeSource( images: [ try self.makeImage( width: 5, height: 3 ) ], type: .png )
        let frame                 = try #require( try BitmapImageDecoder.frames( in: source ).first )
        let ( bytes, properties ) = try BitmapImageDecoder.contents( of: frame )
        let linear                = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try BitmapImageDecoder.detectionImage( of: frame )

        #expect( properties.width        == 5 )
        #expect( properties.height       == 3 )
        #expect( properties.channelCount == 3 )
        #expect( linear.samples.count    == 15 )
        #expect( detection.channels      == 1 )
        #expect( detection.width         == 5 )
        #expect( detection.height        == 3 )
    }

    /// A grayscale container draws to a single meaningful channel with one stored
    /// component per pixel.
    @Test
    func decodesAGrayscaleFrameAsOneChannel() throws
    {
        let source            = try self.makeSource( images: [ try self.makeImage( width: 4, height: 2, gray: true ) ], type: .png )
        let frame             = try #require( try BitmapImageDecoder.frames( in: source ).first )
        let ( _, properties ) = try BitmapImageDecoder.contents( of: frame )

        #expect( properties.channelCount       == 1 )
        #expect( properties.componentsPerPixel == 1 )
        #expect( properties.bytesPerComponent  == 1 )
    }

    /// A non-`1` orientation is applied by the draw, so a 4 × 2 image decoded through a
    /// frame carrying a 90° rotation comes back 2 × 4. ``BitmapImageDecoder/frames(in:)``
    /// reads the orientation from the container into the frame; here it is set directly,
    /// exercising the upright transform without an EXIF-tagged container this target
    /// cannot author. Downstream end-to-end tests cover the tagged-container path.
    @Test
    func appliesTheFrameExifOrientation() throws
    {
        let source            = try self.makeSource( images: [ try self.makeImage( width: 4, height: 2 ) ], type: .png )
        let frame             = BitmapImageFrame( source: source, index: 0, orientation: 6 )
        let ( _, properties ) = try BitmapImageDecoder.contents( of: frame )

        #expect( properties.width  == 2 )
        #expect( properties.height == 4 )
    }

    /// An empty source is refused with a thrown error rather than an empty frame list.
    @Test
    func framesThrowsForAnEmptySource() throws
    {
        let source = try #require( CGImageSourceCreateIncremental( nil ) )

        #expect( throws: SwiftAstro.Error.self ) { try BitmapImageDecoder.frames( in: source ) }
    }

    // MARK: - The real committed captures

    /// Opens a committed processed JPEG capture as an image source.
    ///
    /// - Returns: The opened source.
    /// - Throws: Any error locating or opening the file.
    private func jpegCapture() throws -> CGImageSource
    {
        let url = try CaptureFixtures.url( named: "C6-ASI533-M104-Final.jpg" )

        return try #require( CGImageSourceCreateWithURL( url as CFURL, nil ) )
    }

    /// The single-image JPEG capture enumerates to exactly one frame.
    @Test
    func enumeratesOneFrameForTheJpegCapture() throws
    {
        #expect( try BitmapImageDecoder.frames( in: try self.jpegCapture() ).count == 1 )
    }

    /// The real frame draws and decodes to a coherent colour geometry, and its layout
    /// answers its dimensions and channel count consistently.
    @Test
    func decodesContentsAndLinearImageOfTheRealCapture() throws
    {
        let frame                 = try #require( try BitmapImageDecoder.frames( in: try self.jpegCapture() ).first )
        let ( bytes, properties ) = try BitmapImageDecoder.contents( of: frame )
        let linear                = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: properties ) )

        #expect( linear.width  > 0 )
        #expect( linear.height > 0 )
        #expect( linear.samples.count == linear.width * linear.height )

        #expect( BitmapImageDecoder.dimensions( from: properties ).map { [ $0.width, $0.height ] } == [ linear.width, linear.height ] )
        #expect( BitmapImageDecoder.channelCount( from: properties ) == 3 )
        #expect( try BitmapImageDecoder.cfaPattern( from: properties ) == nil )
    }

    /// The detection image of the real capture is a single luminance channel matching
    /// the frame's geometry — no demosaic.
    @Test
    func detectionImageOfTheRealCapture() throws
    {
        let frame                 = try #require( try BitmapImageDecoder.frames( in: try self.jpegCapture() ).first )
        let ( bytes, properties ) = try BitmapImageDecoder.contents( of: frame )
        let linear                = try #require( BitmapImageDecoder.linearImage( bytes: bytes, properties: properties ) )
        let detection             = try BitmapImageDecoder.detectionImage( of: frame )

        #expect( detection.channels == 1 )
        #expect( detection.width    == linear.width )
        #expect( detection.height   == linear.height )
    }
}
