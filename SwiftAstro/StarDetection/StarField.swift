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

/// The result of star detection: the detected stars and robust aggregate
/// metrics over them.
///
/// The aggregates use the **median** rather than the mean, so a handful of
/// outliers — hot pixels, saturated stars, blended pairs — don't skew the
/// reported focus / tracking quality. They are `nil` when no stars were found.
public struct StarField: Sendable, Equatable
{
    /// The detected stars.
    public let stars: [ Star ]

    /// Creates a star field from its detected stars.
    ///
    /// - Parameter stars: The detected stars.
    public init( stars: [ Star ] )
    {
        self.stars = stars
    }

    /// The number of detected stars.
    public var count: Int
    {
        self.stars.count
    }

    /// The median FWHM over the detected stars, or `nil` when there are none.
    public var medianFWHM: Double?
    {
        PixelUtilities.median( self.stars.map { $0.fwhm } )
    }

    /// The median half-flux radius over the detected stars, or `nil` when there
    /// are none.
    public var medianHFR: Double?
    {
        PixelUtilities.median( self.stars.map { $0.hfr } )
    }

    /// The median eccentricity over the detected stars, or `nil` when there are
    /// none.
    public var medianEccentricity: Double?
    {
        PixelUtilities.median( self.stars.map { $0.eccentricity } )
    }
}
