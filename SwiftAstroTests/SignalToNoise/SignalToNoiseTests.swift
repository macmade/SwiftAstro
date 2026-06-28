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
import SwiftPixel
import Testing

/// Tests for ``SignalToNoise``.
struct SignalToNoiseTests
{
    /// Builds a single-row buffer from the given samples.
    private func buffer( _ pixels: [ Double ] ) throws -> PixelBuffer
    {
        try PixelBuffer( width: pixels.count, height: 1, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// The weight is the inverse of the noise variance, `1 / noise²`.
    @Test
    func weightIsInverseNoiseVariance() throws
    {
        #expect( SignalToNoise( noise: 2 ).weight == 0.25 )
        #expect( SignalToNoise( noise: 0.5 ).weight == 4.0 )
    }

    /// No image yields no estimate.
    @Test
    func nilImageHasNoEstimate() throws
    {
        #expect( SignalToNoise.estimate( in: nil ) == nil )
    }

    /// A flat image has zero spread, hence no measurable noise and no estimate.
    @Test
    func flatImageHasNoEstimate() throws
    {
        let image = try self.buffer( [ 5, 5, 5, 5, 5 ] )

        #expect( SignalToNoise.estimate( in: image ) == nil )
    }

    /// The noise is the robust `1.4826 × MAD` about the median, and the weight is
    /// its inverse variance.
    ///
    /// For `[0, 1, 2, 3, 4, 5, 6]` the median is `3`, the absolute deviations are
    /// `[3, 2, 1, 0, 1, 2, 3]` whose median (MAD) is `2`, so the noise is
    /// `1.4826 × 2 = 2.9652`.
    @Test
    func estimatesRobustNoiseAndWeightFromKnownPixels() throws
    {
        let image    = try self.buffer( [ 0, 1, 2, 3, 4, 5, 6 ] )
        let estimate = try #require( SignalToNoise.estimate( in: image ) )
        let expected = 1.4826 * 2.0

        #expect( abs( estimate.noise  - expected               ) < 1e-9 )
        #expect( abs( estimate.weight - 1.0 / ( expected * expected ) ) < 1e-9 )
    }
}
