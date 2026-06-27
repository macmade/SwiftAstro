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

/// Loads bundled FITS frames into a single-channel ``SwiftPixel/PixelBuffer``,
/// for running the detector against real astronomical data in tests.
///
/// This is the FITS counterpart to ``SyntheticStarField``: where that builds
/// synthetic fixtures, this adapts a real FITS file into the same detector
/// input type. It composes `SwiftFITS` (header geometry + raw data segment) with
/// `SwiftPixel` (`BitsPerPixel` + `PixelUtilities.readRawPixels`) and applies the
/// FITS `BZERO`/`BSCALE` linear rescaling that `readRawPixels` deliberately
/// leaves to the caller.
enum FITSTestImage
{
    /// The base name (without extension) of the real one-shot-colour light frame,
    /// whose filename encodes the acquisition software's reported half-flux radius
    /// (`H3.69`). A RGGB Bayer mosaic from a ZWO ASI585MC Pro.
    static let realLightFrameName = "2025-03-02_21-20-31_G252_B1x1_O7_T-9.80_F_10.00s_0000_H3.69"

    /// The base name (without extension) of the ESA M35 reference frame
    /// (`m35_40min_blue.fits`): a clean, non-mosaiced single-channel star field.
    static let esaM35BlueFrameName = "m35_40min_blue"

    /// Anchors `Bundle(for:)` to the test bundle in Xcode builds.
    private final class BundleToken
    {}

    /// Loads the real one-shot-colour light frame as a single-channel pixel
    /// buffer (the raw Bayer mosaic).
    ///
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: An error if the resource is missing or cannot be decoded.
    static func realLightFrame() throws -> PixelBuffer
    {
        try self.load( resource: self.realLightFrameName )
    }

    /// Loads the ESA M35 reference frame as a single-channel pixel buffer.
    ///
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: An error if the resource is missing or cannot be decoded.
    static func esaM35Blue() throws -> PixelBuffer
    {
        try self.load( resource: self.esaM35BlueFrameName )
    }

    /// Locates a committed FITS test file by name.
    ///
    /// Mirrors how the `SwiftFITS` submodule locates its own fixtures: the heavy
    /// `Test Files` frames live at the repository root (outside any target), so
    /// under SwiftPM they are found relative to this source file's compile-time
    /// path; in an Xcode build they are bundled into the test target and found
    /// through ``BundleToken``.
    ///
    /// - Parameters:
    ///   - resource: The resource base name.
    ///   - ext:      The resource file extension.
    /// - Returns: The located resource URL.
    /// - Throws: ``SwiftAstro/Error`` if the resource cannot be found.
    static func url( resource: String, extension ext: String = "fits" ) throws -> URL
    {
        #if SWIFT_PACKAGE

            // #filePath -> Helpers -> SwiftAstroTests -> repository root -> Test Files.
            let root = URL( fileURLWithPath: #filePath )
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent( "Test Files" )

            let target = "\( resource ).\( ext )"

            if let enumerator = FileManager.default.enumerator( at: root, includingPropertiesForKeys: nil )
            {
                for case let url as URL in enumerator where url.lastPathComponent == target
                {
                    return url
                }
            }

            throw Error( message: "Missing FITS test file: \( target ) under \( root.path )" )

        #else

            guard let url = Bundle( for: BundleToken.self ).url( forResource: resource, withExtension: ext )
            else
            {
                throw Error( message: "Missing bundled FITS test file: \( resource ).\( ext )" )
            }

            return url

        #endif
    }

    /// Loads a bundled FITS resource as a single-channel pixel buffer.
    ///
    /// - Parameters:
    ///   - resource: The resource base name.
    ///   - ext:      The resource file extension.
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: An error if the resource is missing or cannot be decoded.
    static func load( resource: String, extension ext: String = "fits" ) throws -> PixelBuffer
    {
        try self.load( contentsOf: try self.url( resource: resource, extension: ext ) )
    }

    /// Loads a FITS file at the given URL into a single-channel pixel buffer.
    ///
    /// Reads the primary header's geometry and sample format, decodes the raw
    /// data segment big-endian via `SwiftPixel`, and applies the FITS
    /// `BZERO`/`BSCALE` linear rescaling so the samples are physical linear
    /// values.
    ///
    /// - Parameter url: The FITS file location.
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: ``SwiftAstro/Error`` if the file has no usable 2D image, or any
    ///   error raised while parsing or decoding.
    static func load( contentsOf url: URL ) throws -> PixelBuffer
    {
        let file = try FITSFile( url: url, options: .lenient )

        guard let header = file.header
        else
        {
            throw Error( message: "FITS file has no primary header" )
        }

        guard let bitpix = header.bitpix, let format = BitsPerPixel.from( value: bitpix )
        else
        {
            throw Error( message: "FITS file has a missing or unsupported BITPIX" )
        }

        guard header.naxis == 2,
              let width  = header.naxis( 1 ).map( Int.init ), width  > 0,
              let height = header.naxis( 2 ).map( Int.init ), height > 0
        else
        {
            throw Error( message: "FITS file is not a 2D image with positive dimensions" )
        }

        guard let segment = file.sections.first( where: { $0.kind == .data } )
        else
        {
            throw Error( message: "FITS file has no data segment" )
        }

        // The data segment is padded to whole 2880-byte blocks; readRawPixels
        // wants exactly the sample bytes, so trim the trailing block padding.
        let expectedBytes = format.size( numberOfPixels: width * height )
        let raw           = Data( segment.data.prefix( expectedBytes ) )

        guard raw.count == expectedBytes
        else
        {
            throw Error( message: "FITS data segment is smaller than its geometry implies" )
        }

        let stored = try PixelUtilities.readRawPixels( data: raw, width: width, height: height, bitsPerPixel: format )
        let bzero  = self.numericValue( of: header[ "BZERO"  ]?.value ) ?? 0
        let bscale = self.numericValue( of: header[ "BSCALE" ]?.value ) ?? 1

        // readRawPixels intentionally skips BZERO/BSCALE; apply the linear
        // rescaling here so the samples are physical linear values. Skip the
        // per-sample work in the common identity case.
        let pixels = ( bzero == 0 && bscale == 1 ) ? stored : stored.map { bzero + ( bscale * $0 ) }

        return try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// Reads a numeric FITS header value as a `Double`, whether it was parsed as
    /// an integer or a float (e.g. `BZERO = 32768` vs `BSCALE = 1.0`).
    ///
    /// - Parameter value: The header value to read.
    /// - Returns: The value as a `Double`, or `nil` if it is not numeric.
    private static func numericValue( of value: FITSValue? ) -> Double?
    {
        if let integer = value?.integer
        {
            return Double( integer )
        }

        return value?.float
    }
}
