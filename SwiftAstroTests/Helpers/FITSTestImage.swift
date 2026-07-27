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

/// Loads committed FITS frames into a single-channel ``SwiftPixel/PixelBuffer``,
/// for running the detector against real astronomical data in tests.
///
/// This is the FITS counterpart to ``SyntheticStarField``: where that builds
/// synthetic fixtures, this adapts a real FITS file into the same detector input
/// type. It locates the committed fixture and decodes it through the library's
/// own ``FITSImageDecoder``, so the tests exercise the shipping FITS path rather
/// than a private copy of it.
enum FITSTestImage
{
    /// The base name (without extension) of the real one-shot-colour light frame,
    /// whose filename encodes the acquisition software's reported half-flux radius
    /// (`H3.69`). A RGGB Bayer mosaic from a ZWO ASI585MC Pro.
    static let realLightFrameName = "2025-03-02_21-20-31_G252_B1x1_O7_T-9.80_F_10.00s_0000_H3.69"

    /// The base name (without extension) of the ESA M35 reference frame
    /// (`m35_40min_blue.fits`): a clean, non-mosaiced single-channel star field.
    static let esaM35BlueFrameName = "m35_40min_blue"

    /// The base name (without extension) of a single, short ZWO Seestar S30 light
    /// frame of M42 under light pollution (`Light_M 42_10.0s_LP_20260101-234803.fit`):
    /// a 10 s, 16-bit, `GRBG` one-shot-colour sub whose faint, low-SNR stars over
    /// bright nebulosity the detector must still find. It is the diagnostic
    /// regression fixture for the "zero stars on a real sub" fix, kept under its
    /// original acquisition filename.
    static let seestarM42FrameName = "Light_M 42_10.0s_LP_20260101-234803"

    /// The file extension of the Seestar frame — `fit`, not the `fits` the other
    /// fixtures use (its original acquisition name is preserved).
    static let seestarM42FrameExtension = "fit"

    /// The `Test Files` directory at the repository root.
    ///
    /// The heavy fixtures live at the repository root, outside any target
    /// directory, so they cannot be declared as SwiftPM package resources and are
    /// deliberately not bundled into the test bundle either. They are located
    /// relative to this source file's compile-time path, which resolves on the
    /// machine that built the tests under both SwiftPM and Xcode.
    static let testFilesDirectory: URL = .init( fileURLWithPath: #filePath )
        .deletingLastPathComponent() // Helpers/
        .deletingLastPathComponent() // SwiftAstroTests/
        .deletingLastPathComponent() // repository root
        .appendingPathComponent( "Test Files", isDirectory: true )

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
    /// `Test Files` frames live at the repository root, outside any target, and
    /// are searched recursively under ``testFilesDirectory``.
    ///
    /// - Parameters:
    ///   - resource: The resource base name.
    ///   - ext:      The resource file extension.
    /// - Returns: The located resource URL.
    /// - Throws: ``SwiftAstro/Error`` if the resource cannot be found.
    static func url( resource: String, extension ext: String = "fits" ) throws -> URL
    {
        let root   = self.testFilesDirectory
        let target = "\( resource ).\( ext )"

        if let enumerator = FileManager.default.enumerator( at: root, includingPropertiesForKeys: nil )
        {
            for case let url as URL in enumerator where url.lastPathComponent == target
            {
                return url
            }
        }

        throw Error( message: "Missing FITS test file: \( target ) under \( root.path )" )
    }

    /// Loads a committed FITS resource as a single-channel pixel buffer.
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

    /// Loads a FITS file at the given URL into a single-channel linear pixel buffer,
    /// through the library's own ``FITSImageDecoder``.
    ///
    /// - Parameter url: The FITS file location.
    /// - Returns: The frame's linear samples as a ``SwiftPixel/PixelBuffer``.
    /// - Throws: ``SwiftAstro/Error`` if the file has no usable image, or any error
    ///   raised while parsing or decoding.
    static func load( contentsOf url: URL ) throws -> PixelBuffer
    {
        let file  = try FITSFile( url: url, options: .lenient )
        let frame = try Self.firstFrame( in: file )

        let ( bytes, properties ) = try FITSImageDecoder.contents( of: frame )

        guard let linear = FITSImageDecoder.linearImage( bytes: bytes, properties: properties )
        else
        {
            throw Error( message: "FITS frame at \( url.lastPathComponent ) has no decodable linear image" )
        }

        return try PixelBuffer( width: linear.width, height: linear.height, channels: 1, pixels: linear.samples, isNormalized: false )
    }

    /// Loads a FITS file as a detection-ready single-channel image — demosaicing a
    /// Bayer frame to grayscale — through the library's own ``FITSImageDecoder``.
    ///
    /// - Parameter url: The FITS file location.
    /// - Returns: The detection-ready single-channel image.
    /// - Throws: Any error raised while parsing or decoding.
    static func detection( contentsOf url: URL ) throws -> PixelBuffer
    {
        let file  = try FITSFile( url: url, options: .lenient )
        let frame = try Self.firstFrame( in: file )

        return try FITSImageDecoder.detectionImage( of: frame )
    }

    /// The file's first image frame, enumerated through ``FITSImageDecoder``.
    ///
    /// - Parameter file: The parsed FITS file.
    /// - Returns: The first image frame.
    /// - Throws: ``SwiftAstro/Error`` when the file holds no image frame.
    private static func firstFrame( in file: FITSFile ) throws -> FITSImageDecoder.Frame
    {
        guard let frame = try FITSImageDecoder.frames( in: file ).first
        else
        {
            throw Error( message: "FITS file contains no image frame" )
        }

        return frame
    }

    /// The real one-shot-colour light frame, demosaiced to a detection-ready
    /// grayscale image.
    static func realLightFrameDetection() throws -> PixelBuffer
    {
        try self.detection( contentsOf: try self.url( resource: self.realLightFrameName ) )
    }

    /// The ESA M35 reference frame as a detection-ready single-channel image.
    static func esaM35BlueDetection() throws -> PixelBuffer
    {
        try self.detection( contentsOf: try self.url( resource: self.esaM35BlueFrameName ) )
    }

    /// The single short Seestar S30 M42 sub, demosaiced to a detection-ready
    /// grayscale image — the low-SNR one-shot-colour frame the detector must find
    /// stars on.
    static func seestarM42Detection() throws -> PixelBuffer
    {
        try self.detection( contentsOf: try self.url( resource: self.seestarM42FrameName, extension: self.seestarM42FrameExtension ) )
    }

    /// The M42 462-frame stack mosaic as a detection-ready single-channel image.
    ///
    /// This large frame lives only in the `SwiftFITS` submodule's `Test Files`,
    /// so it is resolved by path relative to this source file rather than copied
    /// into this repository or bundled. The
    /// `#filePath` path works under both `swift test` and the Xcode test target.
    static func m42Stack() throws -> PixelBuffer
    {
        let url = URL( fileURLWithPath: #filePath )
            .deletingLastPathComponent() // Helpers/
            .deletingLastPathComponent() // SwiftAstroTests/
            .deletingLastPathComponent() // repository root
            .appendingPathComponent( "Submodules/SwiftFITS/Test Files/Stacked_462_mosaic_M 42_10.0s_LP_20250124-012002.fit" )

        return try self.detection( contentsOf: url )
    }

    /// Extracts a single-channel sub-rectangle of an image.
    ///
    /// The committed frames are large (tens of megapixels); running the full
    /// detector over them in an unoptimized test build is slow because every star
    /// is Gaussian-fitted. Cropping to a representative region keeps the
    /// real-frame assertions fast while still exercising real data.
    ///
    /// - Parameters:
    ///   - image:  The single-channel source image.
    ///   - x:      The crop's left column.
    ///   - y:      The crop's top row.
    ///   - width:  The crop width, in pixels.
    ///   - height: The crop height, in pixels.
    /// - Returns: The cropped single-channel image.
    /// - Throws: An error if the geometry is inconsistent.
    static func crop( _ image: PixelBuffer, x: Int, y: Int, width: Int, height: Int ) throws -> PixelBuffer
    {
        let pixels = ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let sx = x + ( index % width )
            let sy = y + ( index / width )

            return image.pixels[ ( sy * image.width ) + sx ]
        }

        return try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }
}
