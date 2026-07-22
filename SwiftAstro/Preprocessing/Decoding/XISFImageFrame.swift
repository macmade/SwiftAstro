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
import SwiftXISF

/// A handle to one image within an XISF file.
///
/// An XISF file holds its images as separate elements, so a frame is simply one
/// of them. The handle keeps the parsed ``XISFImage`` rather than its bytes: an
/// image's data block may be compressed, and enumerating a file's frames must not
/// pay to decompress every one of them.
///
/// `XISFImage` is a non-`Sendable` reference type, so neither is this handle.
/// Decode the frame within one isolation domain and send the results — the bytes
/// and ``XISFImageProperties`` that come back from
/// ``XISFImageDecoder/contents(of:)`` both are `Sendable`.
public struct XISFImageFrame
{
    /// The parsed image this frame refers to.
    public let image: XISFImage

    /// Creates a frame referring to a parsed XISF image.
    ///
    /// - Parameter image: The parsed image.
    public init( image: XISFImage )
    {
        self.image = image
    }
}
