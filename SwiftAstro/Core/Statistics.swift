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

/// Robust descriptive statistics shared across SwiftAstro.
public enum Statistics
{
    /// The median of a set of values: the middle value for an odd count, the
    /// average of the two middle values for an even count, or `nil` when empty.
    ///
    /// Generic over `BinaryFloatingPoint` (and not integers) because the
    /// even-count case averages the two middle values, which integer division
    /// would truncate.
    ///
    /// - Parameter values: The values to summarize.
    /// - Returns: The median, or `nil` for an empty input.
    public static func median< T: BinaryFloatingPoint >( _ values: [ T ] ) -> T?
    {
        guard values.isEmpty == false
        else
        {
            return nil
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple( of: 2 )
        {
            return ( sorted[ middle - 1 ] + sorted[ middle ] ) / 2
        }

        return sorted[ middle ]
    }

    /// The median absolute deviation of a set of values about a center — a robust
    /// measure of spread.
    ///
    /// - Parameters:
    ///   - values: The values to summarize.
    ///   - center: The center to measure deviations from (typically the median).
    /// - Returns: The median of the absolute deviations, or `nil` for an empty
    ///   input.
    public static func medianAbsoluteDeviation< T: BinaryFloatingPoint >( _ values: [ T ], around center: T ) -> T?
    {
        self.median( values.map { abs( $0 - center ) } )
    }
}
