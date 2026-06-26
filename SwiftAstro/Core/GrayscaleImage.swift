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

/// A single-channel (grayscale) image of linear samples, row-major.
///
/// This is the input to star detection: the caller is expected to supply
/// *linear* luminance values (the un-stretched sensor data), since the star
/// metrics are only physically meaningful on linear data.
public struct GrayscaleImage: Sendable, Equatable
{
    /// The image width in pixels.
    public let width: Int

    /// The image height in pixels.
    public let height: Int

    /// The samples, in row-major order, of length `width × height`.
    public let pixels: [ Double ]

    /// Creates a grayscale image, validating that the geometry and sample count
    /// are consistent.
    ///
    /// - Parameters:
    ///   - width:  The image width in pixels. Must be `>= 0`.
    ///   - height: The image height in pixels. Must be `>= 0`.
    ///   - pixels: The row-major samples; their count must equal `width × height`.
    ///
    /// - Throws: ``Error`` if a dimension is negative or the sample count does
    ///           not match the geometry.
    public init( width: Int, height: Int, pixels: [ Double ] ) throws
    {
        guard width >= 0, height >= 0
        else
        {
            throw Error( message: "Dimensions must not be negative: \( width )x\( height )" )
        }

        guard pixels.count == width * height
        else
        {
            throw Error( message: "Sample count does not match geometry: \( pixels.count ) != \( width * height )" )
        }

        self.width  = width
        self.height = height
        self.pixels = pixels
    }

    /// The sample at the given pixel coordinate, with the origin at the top-left,
    /// or `nil` when the coordinate is out of bounds.
    ///
    /// The bounds are checked rather than left to a raw flat-index access, which
    /// would silently return a sample from a neighbouring row for an `x` outside
    /// `0 ..< width`. An out-of-range coordinate is surfaced as `nil` for the
    /// caller to handle, never a crash.
    ///
    /// - Parameters:
    ///   - x: The column, `0 ..< width`.
    ///   - y: The row, `0 ..< height`.
    public subscript( x: Int, y: Int ) -> Double?
    {
        guard x >= 0, x < self.width, y >= 0, y < self.height
        else
        {
            return nil
        }

        return self.pixels[ ( y * self.width ) + x ]
    }
}
