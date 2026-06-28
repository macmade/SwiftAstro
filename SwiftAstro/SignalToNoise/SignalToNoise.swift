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

/// An image-wide signal-to-noise estimate, used to weight whole frames against
/// one another (in the spirit of PixInsight's SubframeSelector "SNRWeight").
///
/// The estimate is **relative**, not an absolute signal-to-noise ratio: it
/// assumes the frames being compared are observations of the same target with
/// similar backgrounds, so the signal is taken as comparable across frames and
/// the weight depends only on the noise. A frame with less noise therefore earns
/// a higher weight, which rewards transparency and good sky conditions.
public struct SignalToNoise: Sendable, Equatable
{
    /// The robust noise standard deviation, estimated as `1.4826 × MAD` about the
    /// image median — the same robust estimator the star detector uses, so the
    /// two agree on what "noise" means.
    public let noise: Double

    /// The relative SNR weight, `1 / noise²` (inverse noise variance) — the
    /// statistically optimal inverse-variance weighting for combining
    /// observations of the same signal. Higher means less noise, i.e. a better
    /// frame.
    public var weight: Double
    {
        1.0 / ( self.noise * self.noise )
    }

    /// The factor converting a median absolute deviation to a standard deviation
    /// for normally distributed data.
    private static let madToSigma = 1.4826

    /// Creates an estimate from a known noise standard deviation.
    ///
    /// - Parameter noise: The robust noise standard deviation.
    public init( noise: Double )
    {
        self.noise = noise
    }

    /// Estimates the image-wide noise and SNR weight of a frame.
    ///
    /// The noise is the robust `1.4826 × MAD` about the image median; the weight
    /// is its inverse variance. The entry point is pure and works on the
    /// `Sendable` ``SwiftPixel/PixelBuffer``, so a caller can run it off the main
    /// actor.
    ///
    /// - Parameter image: The linear image to measure, or `nil` when none is
    ///   available (estimation is then skipped).
    /// - Returns: The estimate, or `nil` when there is no image, it has no
    ///   pixels, or the noise is not positive (a flat or degenerate frame, which
    ///   has no meaningful signal-to-noise).
    public static func estimate( in image: PixelBuffer? ) -> SignalToNoise?
    {
        guard let image, image.pixels.isEmpty == false
        else
        {
            return nil
        }

        let median = PixelUtilities.median( image.pixels ) ?? 0
        let mad    = PixelUtilities.medianAbsoluteDeviation( image.pixels, around: median ) ?? 0
        let noise  = mad * Self.madToSigma

        guard noise > 0
        else
        {
            return nil
        }

        return SignalToNoise( noise: noise )
    }
}
