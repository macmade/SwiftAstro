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

/// Smoke tests for ``FITSTestImage`` loading the committed real light frame.
///
/// These only assert that the bundled FITS frame loads into a geometrically
/// consistent, single-channel ``PixelBuffer``; the detection-quality assertions
/// (median HFR ≈ 3.69 px) live in the real-frame validation test.
struct FITSTestImageTests
{
    /// The committed real light frame loads with positive, consistent geometry.
    @Test
    func loadsTheRealFrameWithConsistentGeometry() throws
    {
        let image = try FITSTestImage.realLightFrame()

        #expect( image.width    > 0 )
        #expect( image.height   > 0 )
        #expect( image.channels == 1 )
        #expect( image.pixels.count == image.width * image.height )
    }

    /// The loaded samples are finite (the BZERO/BSCALE rescaling produced usable
    /// linear values, not NaN/infinity).
    @Test
    func loadedSamplesAreFinite() throws
    {
        let image = try FITSTestImage.realLightFrame()

        #expect( image.pixels.allSatisfy { $0.isFinite } )
    }
}
