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

/// A strategy for detecting stars and measuring their metrics in a
/// single-channel image.
///
/// This is the seam that lets the detection method vary:
/// ``MatchedFilterStarDetector`` implements the matched-filter, Gaussian-fit
/// approach today, and an alternative detector can conform without changing
/// callers or the result types.
///
/// The input is a `SwiftPixel.PixelBuffer` of *linear* samples (the un-stretched
/// sensor data), since the star metrics are only physically meaningful on linear
/// data. Detectors operate on a single channel; a multi-channel buffer is
/// rejected.
public protocol StarDetecting: Sendable
{
    /// Detects stars in the given single-channel, linear image.
    ///
    /// - Parameter image: The single-channel, linear image to analyze.
    /// - Returns: The detected stars and their aggregate metrics.
    /// - Throws: If the image cannot be analyzed (e.g. it is not single-channel).
    func detectStars( in image: PixelBuffer ) throws -> StarField
}
