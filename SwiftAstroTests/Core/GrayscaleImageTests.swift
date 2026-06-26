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
import Testing

/// Tests for ``GrayscaleImage``.
struct GrayscaleImageTests
{
    /// The initializer stores the geometry and samples.
    @Test
    func storesGeometryAndSamples() throws
    {
        let image = try GrayscaleImage( width: 2, height: 2, pixels: [ 1, 2, 3, 4 ] )

        #expect( image.width  == 2 )
        #expect( image.height == 2 )
        #expect( image.pixels == [ 1, 2, 3, 4 ] )
    }

    /// The initializer rejects a sample count that does not match the geometry.
    @Test
    func throwsWhenSampleCountDoesNotMatchGeometry() throws
    {
        #expect( throws: SwiftAstro.Error.self )
        {
            _ = try GrayscaleImage( width: 2, height: 2, pixels: [ 1, 2, 3 ] )
        }
    }

    /// The initializer rejects negative dimensions.
    @Test
    func throwsForNegativeDimensions() throws
    {
        #expect( throws: SwiftAstro.Error.self )
        {
            _ = try GrayscaleImage( width: -1, height: 2, pixels: [] )
        }
    }

    /// The subscript reads samples in row-major order.
    @Test
    func subscriptReadsRowMajorSamples() throws
    {
        let image = try GrayscaleImage( width: 3, height: 2, pixels: [ 0, 1, 2, 3, 4, 5 ] )

        #expect( image[ 0, 0 ] == 0 )
        #expect( image[ 2, 0 ] == 2 )
        #expect( image[ 0, 1 ] == 3 )
        #expect( image[ 2, 1 ] == 5 )
    }

    /// The subscript returns `nil` for out-of-bounds coordinates rather than wrapping or trapping.
    @Test
    func subscriptReturnsNilForOutOfBounds() throws
    {
        let image = try GrayscaleImage( width: 3, height: 2, pixels: [ 0, 1, 2, 3, 4, 5 ] )

        // An out-of-range column must not wrap into the next row — it is nil.
        #expect( image[ 3,  0 ] == nil )
        #expect( image[ -1, 0 ] == nil )
        #expect( image[ 0,  2 ] == nil )
        #expect( image[ 0, -1 ] == nil )
    }
}
