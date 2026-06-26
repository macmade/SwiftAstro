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

/// A single detected star and its measured metrics.
///
/// The metrics are method-agnostic — both the moment-based detector and a future
/// PSF-fitting detector produce the same shape — so a detection result can be
/// consumed uniformly regardless of how it was computed.
public struct Star: Sendable, Equatable
{
    /// The centroid column, in pixels (origin top-left).
    public let x: Double

    /// The centroid row, in pixels (origin top-left).
    public let y: Double

    /// The total background-subtracted flux.
    public let flux: Double

    /// The half-flux radius, in pixels.
    public let hfr: Double

    /// The full width at half maximum, in pixels.
    public let fwhm: Double

    /// The shape eccentricity: `0` for a round star, approaching `1` as it
    /// elongates.
    public let eccentricity: Double

    /// Creates a star from its centroid and metrics.
    public init( x: Double, y: Double, flux: Double, hfr: Double, fwhm: Double, eccentricity: Double )
    {
        self.x            = x
        self.y            = y
        self.flux         = flux
        self.hfr          = hfr
        self.fwhm         = fwhm
        self.eccentricity = eccentricity
    }
}
