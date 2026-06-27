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
import SwiftPixel

/// A point-spread-function-fitting star detector.
///
/// - Important: Not yet implemented. This is a placeholder conforming to
///   ``StarDetecting`` so the seam for a future PSF-fitting + deblending
///   approach exists; ``detectStars(in:)`` currently returns an empty
///   ``StarField``. PSF fitting is the right tool for crowded/blended fields and
///   precision photometry — see ``MomentStarDetector`` for the implemented
///   moment-based approach used for quality metrics.
public struct PSFStarDetector: StarDetecting
{
    /// Creates a detector.
    public init()
    {}

    /// Detects stars by fitting the point-spread function.
    ///
    /// - Important: Not yet implemented — always returns an empty ``StarField``.
    ///
    /// - Parameter image: The single-channel, linear image to analyze.
    /// - Returns: An empty ``StarField`` until PSF fitting is implemented.
    public func detectStars( in image: PixelBuffer ) throws -> StarField
    {
        // TODO: Implement PSF-fitting + deblending detection.
        StarField( stars: [] )
    }
}
