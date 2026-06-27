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
    /// Delegates to the library's ``FITSImageDecoder`` — the same code path
    /// consumers use — so this helper only locates the bundled fixture and the
    /// decoding stays in one place.
    ///
    /// - Parameter url: The FITS file location.
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: ``SwiftAstro/Error`` if the file has no usable 2D image, or any
    ///   error raised while parsing or decoding.
    static func load( contentsOf url: URL ) throws -> PixelBuffer
    {
        let file = try FITSFile( url: url, options: .lenient )

        return try FITSImageDecoder.linearImage( from: file )
    }
}
