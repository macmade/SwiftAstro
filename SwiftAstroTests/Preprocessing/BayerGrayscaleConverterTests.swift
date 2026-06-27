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

/// Tests for ``BayerGrayscaleConverter``.
struct BayerGrayscaleConverterTests
{
    /// Builds an RGGB mosaic whose sites carry per-colour flat values.
    private func rggbMosaic( width: Int, height: Int, r: Double, g: Double, b: Double ) throws -> PixelBuffer
    {
        let pixels = ( 0 ..< ( width * height ) ).map
        {
            index -> Double in

            let x = index % width
            let y = index / width

            switch ( x.isMultiple( of: 2 ), y.isMultiple( of: 2 ) )
            {
                case ( true,  true  ): return r // (even, even) → R
                case ( false, true  ): return g // (odd,  even) → G
                case ( true,  false ): return g // (even, odd)  → G
                case ( false, false ): return b // (odd,  odd)  → B
            }
        }

        return try PixelBuffer( width: width, height: height, channels: 1, pixels: pixels, isNormalized: false )
    }

    /// The converter yields a single-channel buffer of the same geometry, not
    /// normalized.
    @Test
    func producesSingleChannelGrayscaleOfSameGeometry() throws
    {
        let mosaic = try self.rggbMosaic( width: 8, height: 8, r: 500, g: 500, b: 500 )
        let gray   = try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: mosaic )

        #expect( gray.width        == 8 )
        #expect( gray.height       == 8 )
        #expect( gray.channels     == 1 )
        #expect( gray.isNormalized == false )
        #expect( gray.pixels.count == 64 )
    }

    /// A mosaic flat across all sites maps to a flat grayscale of that level.
    @Test
    func flatMosaicMapsToFlatGrayscale() throws
    {
        let mosaic = try self.rggbMosaic( width: 8, height: 8, r: 500, g: 500, b: 500 )
        let gray   = try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: mosaic )

        #expect( gray.pixels.allSatisfy { abs( $0 - 500 ) < 1e-6 } )
    }

    /// The three colour channels are combined by an equal-weight mean, so a
    /// per-channel-flat mosaic yields their average away from the edges.
    @Test
    func combinesColourChannelsByMean() throws
    {
        let mosaic   = try self.rggbMosaic( width: 16, height: 16, r: 100, g: 200, b: 300 )
        let gray     = try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: mosaic )
        let interior = gray.pixels[ ( 8 * 16 ) + 8 ]

        #expect( abs( interior - 200 ) < 1.0 )
    }

    /// A multi-channel input is rejected — the converter expects a raw mosaic.
    @Test
    func rejectsMultiChannelInput() throws
    {
        let rgb = try PixelBuffer( width: 2, height: 2, channels: 3, pixels: [ Double ]( repeating: 1, count: 12 ), isNormalized: false )

        #expect( throws: (any Swift.Error).self )
        {
            _ = try BayerGrayscaleConverter( pattern: .rggb ).grayscale( from: rgb )
        }
    }
}
