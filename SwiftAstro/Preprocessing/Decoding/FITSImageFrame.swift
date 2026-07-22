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

/// A handle to one image within a FITS file — the image HDU's untrimmed bytes
/// paired with the header that describes them.
///
/// A plain 2-D image and an RGB colour cube each yield one frame. A multi-image
/// cube yields one frame per plane, each carrying that plane's own byte slice and
/// a header made two-dimensional (`NAXIS` rewritten to `2`, `NAXIS3` dropped), so
/// a plane is indistinguishable from a standalone image once it is a frame.
///
/// Unlike the other formats' handles this one is `Sendable`: a FITS file is
/// already wholly in memory, so a frame can hold its bytes outright rather than a
/// reference to a parser.
public struct FITSImageFrame: Sendable
{
    /// The image HDU's raw bytes, as stored — the FITS 2880-byte block padding is
    /// trimmed by ``FITSImageDecoder/contents(of:)``, not here.
    public let data: Data

    /// The owning header's property snapshots, describing ``data``.
    public let properties: [ FITSPropertySnapshot ]

    /// Creates a frame from an image HDU's bytes and header.
    ///
    /// - Parameters:
    ///   - data:       The image HDU's raw bytes.
    ///   - properties: The owning header's property snapshots.
    public init( data: Data, properties: [ FITSPropertySnapshot ] )
    {
        self.data       = data
        self.properties = properties
    }
}
