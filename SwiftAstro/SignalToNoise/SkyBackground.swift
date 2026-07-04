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

/// A robust estimate of a frame's sky background and its noise, measured on the
/// linear image the star detector uses.
///
/// The background level is the image median and the noise is the robust
/// `1.4826 × MAD` about it — the same estimator ``SignalToNoise`` and the star
/// detector use, so all three agree on what "background" and "noise" mean.
///
/// The absolute values (``level``, ``noise``, ``minimum``, ``maximum``) are in
/// the image's native linear units (ADU). The relative helpers
/// (``relativeLevel``, ``relativeNoise``) express the background and noise as a
/// fraction of the image's value range, so frames of differing bit depth or
/// scaling can be compared.
public struct SkyBackground: Sendable, Equatable
{
    /// The robust background level — the median of the linear image (ADU).
    public let level: Double

    /// The robust background noise — `1.4826 × MAD` about the median (ADU).
    public let noise: Double

    /// The smallest sample value in the image (ADU).
    public let minimum: Double

    /// The largest sample value in the image (ADU).
    public let maximum: Double

    /// The factor converting a median absolute deviation to a standard deviation
    /// for normally distributed data.
    private static let madToSigma = 1.4826

    /// The image's value range, `maximum − minimum` (ADU).
    public var range: Double
    {
        self.maximum - self.minimum
    }

    /// The background level as a fraction of the image's value range, in
    /// `0 ... 1`, or `nil` for a flat image with no range.
    public var relativeLevel: Double?
    {
        guard self.range > 0
        else
        {
            return nil
        }

        return min( 1, max( 0, ( self.level - self.minimum ) / self.range ) )
    }

    /// The background noise as a fraction of the image's value range, or `nil`
    /// for a flat image with no range.
    public var relativeNoise: Double?
    {
        guard self.range > 0
        else
        {
            return nil
        }

        return self.noise / self.range
    }

    /// Creates a background estimate from measured values.
    ///
    /// - Parameters:
    ///   - level:   The robust background level (ADU).
    ///   - noise:   The robust background noise (ADU).
    ///   - minimum: The smallest sample value (ADU).
    ///   - maximum: The largest sample value (ADU).
    public init( level: Double, noise: Double, minimum: Double, maximum: Double )
    {
        self.level   = level
        self.noise   = noise
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Estimates the sky background of a frame.
    ///
    /// The level is the robust image median, the noise the robust
    /// `1.4826 × MAD` about it. Unlike ``SignalToNoise/estimate(in:)``, a flat
    /// frame still yields an estimate: it has a meaningful background level (the
    /// flat level) even though its noise is zero. The entry point is pure and
    /// works on the `Sendable` ``SwiftPixel/PixelBuffer``, so a caller can run it
    /// off the main actor.
    ///
    /// - Parameter image: The linear image to measure, or `nil` when none is
    ///   available (estimation is then skipped).
    /// - Returns: The estimate, or `nil` when there is no image or it has no
    ///   pixels.
    public static func estimate( in image: PixelBuffer? ) -> SkyBackground?
    {
        guard let image, image.pixels.isEmpty == false,
              let median  = PixelUtilities.median( image.pixels ),
              let minimum = image.pixels.min(),
              let maximum = image.pixels.max()
        else
        {
            return nil
        }

        let mad   = PixelUtilities.medianAbsoluteDeviation( image.pixels, around: median ) ?? 0
        let noise = mad * Self.madToSigma

        return SkyBackground( level: median, noise: noise, minimum: minimum, maximum: maximum )
    }
}
