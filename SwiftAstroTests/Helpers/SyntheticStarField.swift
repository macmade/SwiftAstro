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

/// A deterministic, seeded uniform noise source, so synthetic fixtures are
/// reproducible across runs without depending on the system RNG.
struct DeterministicNoise
{
    /// The current state of the linear congruential generator.
    private var state: UInt64

    /// Creates a generator seeded with the given value.
    ///
    /// - Parameter seed: The initial generator state.
    init( seed: UInt64 )
    {
        self.state = seed
    }

    /// Advances the generator and returns the next value in `[-1, 1]`.
    mutating func next() -> Double
    {
        self.state = ( self.state &* 6364136223846793005 ) &+ 1442695040888963407

        return ( Double( self.state >> 11 ) * ( 1.0 / 9007199254740992.0 ) ) * 2 - 1
    }
}

/// Builds synthetic grayscale images of Gaussian "stars" on a flat background,
/// with optional reproducible noise, for detector tests.
struct SyntheticStarField
{
    /// The image width, in pixels.
    let width:      Int

    /// The image height, in pixels.
    let height:     Int

    /// The flat background level the stars sit on.
    let background: Double

    /// The accumulated samples, in row-major order.
    private var pixels: [ Double ]

    /// Creates a field of the given size filled with the background level.
    ///
    /// - Parameters:
    ///   - width:      The image width, in pixels.
    ///   - height:     The image height, in pixels.
    ///   - background: The flat background level.
    init( width: Int, height: Int, background: Double )
    {
        self.width      = width
        self.height     = height
        self.background = background
        self.pixels     = [ Double ]( repeating: background, count: width * height )
    }

    /// Returns a copy with an elliptical Gaussian star added.
    ///
    /// - Parameters:
    ///   - cx:     The centre column, in pixels.
    ///   - cy:     The centre row, in pixels.
    ///   - peak:   The peak value above the background.
    ///   - sigmaX: The Gaussian standard deviation along the x axis.
    ///   - sigmaY: The Gaussian standard deviation along the y axis.
    /// - Returns: A copy with the star added.
    func addingStar( cx: Double, cy: Double, peak: Double, sigmaX: Double, sigmaY: Double ) -> SyntheticStarField
    {
        var copy = self

        copy.pixels = self.pixels.indices.map
        {
            index in

            let x        = index % self.width
            let y        = index / self.width
            let dx       = Double( x ) - cx
            let dy       = Double( y ) - cy
            let exponent = ( ( dx * dx ) / ( 2 * sigmaX * sigmaX ) ) + ( ( dy * dy ) / ( 2 * sigmaY * sigmaY ) )

            return self.pixels[ index ] + ( peak * exp( -exponent ) )
        }

        return copy
    }

    /// Returns a copy with a round Gaussian star added.
    ///
    /// - Parameters:
    ///   - cx:    The centre column, in pixels.
    ///   - cy:    The centre row, in pixels.
    ///   - peak:  The peak value above the background.
    ///   - sigma: The Gaussian standard deviation.
    /// - Returns: A copy with the star added.
    func addingStar( cx: Double, cy: Double, peak: Double, sigma: Double ) -> SyntheticStarField
    {
        self.addingStar( cx: cx, cy: cy, peak: peak, sigmaX: sigma, sigmaY: sigma )
    }

    /// Returns a copy with reproducible uniform noise of the given amplitude
    /// added.
    ///
    /// - Parameters:
    ///   - seed:      The seed for the deterministic noise source.
    ///   - amplitude: The maximum magnitude of the added noise.
    /// - Returns: A copy with noise added.
    func addingNoise( seed: UInt64, amplitude: Double ) -> SyntheticStarField
    {
        var copy  = self
        var noise = DeterministicNoise( seed: seed )

        copy.pixels = self.pixels.map { $0 + ( noise.next() * amplitude ) }

        return copy
    }

    /// Builds the grayscale image from the accumulated samples.
    ///
    /// - Returns: The synthetic grayscale image.
    /// - Throws: ``SwiftAstro/Error`` if the geometry is inconsistent.
    func image() throws -> GrayscaleImage
    {
        try GrayscaleImage( width: self.width, height: self.height, pixels: self.pixels )
    }
}
