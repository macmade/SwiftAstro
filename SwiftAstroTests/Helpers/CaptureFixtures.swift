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

/// Locates the full-frame captures checked into SwiftAstro's `Test Files`
/// directory, by name and without assuming a format.
///
/// This is the format-neutral counterpart to ``FITSTestImage``: that helper is
/// FITS-specific — it decodes a frame into a ``SwiftPixel/PixelBuffer`` — whereas
/// the captures relocated into this repository are FITS, XISF, Canon RAW and JPEG
/// frames, which the per-format decoder milestones consume as *URLs* rather than
/// as an already-decoded buffer. This helper therefore only resolves a capture's
/// location on disk; each format's own decoder tests open it.
///
/// The captures are large (tens of megabytes each), so — exactly like
/// ``FITSTestImage`` — they live at the repository root, outside any target
/// directory, and are located relative to this source file's compile-time path
/// rather than bundled as package resources.
enum CaptureFixtures
{
    /// The `Test Files` directory at the repository root, holding both the
    /// full-frame captures and the small reference frames.
    ///
    /// Resolved relative to this source file's compile-time path, which is valid
    /// on the machine that built the tests under both SwiftPM and Xcode.
    static let testFilesDirectory: URL = .init( fileURLWithPath: #filePath )
        .deletingLastPathComponent() // Helpers/
        .deletingLastPathComponent() // SwiftAstroTests/
        .deletingLastPathComponent() // repository root
        .appendingPathComponent( "Test Files", isDirectory: true )

    /// The manifest of full-frame captures relocated into this repository: every
    /// file name, with its extension, that the per-format decoder tests validate
    /// against.
    ///
    /// It is the single source of truth for the moved set, so a test can iterate
    /// it to assert every capture resolves and no two collide by name — the two
    /// invariants the recursive, name-keyed resolution below depends on.
    static let captureFileNames: [ String ] =
        [
            "C6-ASI533-M104-Final.jpg",
            "C6-ASI533-M104-Light.fits",
            "C6-ASI533-M12-Final.jpg",
            "C6-ASI533-M12-Light.fits",
            "C6-ASI585-M42-Final.jpg",
            "C6-ASI585-M42-Light.fits",
            "C6-R7-M42-Light.cr3",
            "S30-M42-Corrected.xisf",
            "S30-M42-Light.fit",
            "S30Pro-NGC7822-Final.jpg",
            "S30Pro-NGC7822-Light.fit",
            "S30Pro-NGC7822-Stacked.fit",
            "S50-M33-Final.jpg",
            "S50-M33-Light.fit",
        ]

    /// Resolves a capture by its full file name (with extension).
    ///
    /// Mirrors ``FITSTestImage/url(resource:extension:)``: the captures live at the
    /// repository root, outside any target, and are searched recursively under
    /// ``testFilesDirectory``, so a caller does not depend on their exact
    /// sub-directory.
    ///
    /// - Parameter name: The capture's file name, e.g. `S30-M42-Corrected.xisf`.
    /// - Returns: The located capture's URL.
    /// - Throws: ``SwiftAstro/Error`` if no capture of that name is found.
    static func url( named name: String ) throws -> URL
    {
        let root = self.testFilesDirectory

        if let enumerator = FileManager.default.enumerator( at: root, includingPropertiesForKeys: nil )
        {
            for case let url as URL in enumerator where url.lastPathComponent == name
            {
                return url
            }
        }

        throw Error( message: "Missing capture: \( name ) under \( root.path )" )
    }
}
