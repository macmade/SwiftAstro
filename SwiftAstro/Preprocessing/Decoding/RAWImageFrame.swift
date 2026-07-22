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
import SwiftRAW

/// A handle to the single image a camera RAW file holds.
///
/// A RAW file exposes exactly one sensor mosaic, so ``RAWImageDecoder/frames(in:)``
/// always answers with exactly one of these. That is a uniform answer, not a
/// degenerate case: a caller enumerating frames does not need to know that this
/// format can only ever have one.
///
/// `RAWFile` is a non-`Sendable` reference type owning a LibRAW instance, so
/// neither is this handle. Decode the frame within one isolation domain and send
/// the results — the cropped mosaic bytes and ``RAWImageProperties`` that come
/// back from ``RAWImageDecoder/contents(of:)`` both are `Sendable`.
public struct RAWImageFrame
{
    /// The opened, unpacked RAW file this frame refers to.
    public let file: RAWFile

    /// Creates a frame referring to an opened RAW file.
    ///
    /// - Parameter file: The opened, unpacked RAW file.
    public init( file: RAWFile )
    {
        self.file = file
    }
}
