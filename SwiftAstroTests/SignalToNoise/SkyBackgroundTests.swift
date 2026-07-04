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

/// Tests for ``SkyBackground``.
struct SkyBackgroundTests
{
    /// Builds a single-row buffer from the given samples.
    private func buffer( _ pixels: [ Double ] ) throws -> PixelBuffer
    {
        try PixelBuffer( width: pixels.count, height: 1, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// No image yields no estimate.
    @Test
    func nilImageHasNoEstimate() throws
    {
        #expect( SkyBackground.estimate( in: nil ) == nil )
    }

    /// An image with no pixels yields no estimate.
    @Test
    func emptyImageHasNoEstimate() throws
    {
        let image = try self.buffer( [] )

        #expect( SkyBackground.estimate( in: image ) == nil )
    }

    /// The level is the median, the noise the robust `1.4826 × MAD` about it, and
    /// the minimum and maximum are the sample extremes.
    ///
    /// For `[0, 1, 2, 3, 4, 5, 6]` the median is `3`, the absolute deviations are
    /// `[3, 2, 1, 0, 1, 2, 3]` whose median (MAD) is `2`, so the noise is
    /// `1.4826 × 2`.
    @Test
    func estimatesLevelNoiseAndExtremesFromKnownPixels() throws
    {
        let image    = try self.buffer( [ 0, 1, 2, 3, 4, 5, 6 ] )
        let estimate = try #require( SkyBackground.estimate( in: image ) )

        #expect( estimate.level   == 3 )
        #expect( estimate.minimum == 0 )
        #expect( estimate.maximum == 6 )
        #expect( abs( estimate.noise - 1.4826 * 2.0 ) < 1e-9 )
    }

    /// The relative level and noise are fractions of the image's value range.
    @Test
    func relativeValuesAreFractionsOfRange() throws
    {
        let image    = try self.buffer( [ 0, 1, 2, 3, 4, 5, 6 ] )
        let estimate = try #require( SkyBackground.estimate( in: image ) )

        #expect( estimate.range == 6 )
        #expect( abs( try #require( estimate.relativeLevel ) - 0.5 ) < 1e-9 )
        #expect( abs( try #require( estimate.relativeNoise ) - ( 1.4826 * 2.0 ) / 6.0 ) < 1e-9 )
    }

    /// A flat image has a valid background level but zero noise and no range, so
    /// its relative values are unavailable.
    @Test
    func flatImageHasBackgroundButNoRange() throws
    {
        let image    = try self.buffer( [ 5, 5, 5, 5, 5 ] )
        let estimate = try #require( SkyBackground.estimate( in: image ) )

        #expect( estimate.level         == 5 )
        #expect( estimate.noise         == 0 )
        #expect( estimate.range         == 0 )
        #expect( estimate.relativeLevel == nil )
        #expect( estimate.relativeNoise == nil )
    }
}
