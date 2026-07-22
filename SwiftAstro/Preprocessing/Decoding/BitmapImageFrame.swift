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

/// A handle to one image within a photographic container — a JPEG, PNG, TIFF or
/// HEIC, any of which may hold several.
///
/// The handle keeps the source and the index rather than a decoded image:
/// enumerating a multi-frame container's frames must not pay to draw every one of
/// them. The EXIF orientation is read at enumeration time, alongside the frame's
/// other container-level properties, and carried here so the draw that
/// ``BitmapImageDecoder/contents(of:)`` performs can bring the image upright.
///
/// `CGImageSource` is a Core Foundation reference type and not `Sendable`, so
/// neither is this handle. Decode the frame within one isolation domain and send
/// the results — the drawn bytes and ``BitmapImageProperties`` that come back from
/// ``BitmapImageDecoder/contents(of:)`` both are `Sendable`.
public struct BitmapImageFrame
{
    /// The opened image source this frame belongs to.
    public let source: CGImageSource

    /// The frame's zero-based index within ``source``.
    public let index: Int

    /// The frame's EXIF orientation (`1`...`8`), applied before the image is
    /// drawn so a portrait photograph is decoded the right way up. `1` — the
    /// overwhelmingly common case — means no transform.
    public let orientation: Int

    /// Creates a frame referring to one image within a source.
    ///
    /// - Parameters:
    ///   - source:      The opened image source.
    ///   - index:       The frame's zero-based index within `source`.
    ///   - orientation: The frame's EXIF orientation (`1`...`8`).
    public init( source: CGImageSource, index: Int, orientation: Int )
    {
        self.source      = source
        self.index       = index
        self.orientation = orientation
    }
}
