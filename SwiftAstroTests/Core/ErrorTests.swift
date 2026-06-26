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

/// Tests for ``SwiftAstro/Error``.
struct ErrorTests
{
    /// `description` returns the underlying message.
    @Test
    func descriptionIsTheMessage() throws
    {
        let message = "Something went wrong"

        #expect( SwiftAstro.Error( message: message ).description == message )
    }

    /// `errorDescription` returns the underlying message.
    @Test
    func errorDescriptionIsTheMessage() throws
    {
        let message = "Something went wrong"

        #expect( SwiftAstro.Error( message: message ).errorDescription == message )
    }

    /// The error conforms to `LocalizedError`.
    @Test
    func isLocalizedError() throws
    {
        let error = SwiftAstro.Error( message: "Something went wrong" ) as Any

        #expect( error is LocalizedError )
    }

    /// The error conforms to `CustomStringConvertible`.
    @Test
    func isCustomStringConvertible() throws
    {
        let error = SwiftAstro.Error( message: "Something went wrong" ) as Any

        #expect( error is CustomStringConvertible )
    }

    /// Errors compare equal when their messages match.
    @Test
    func isEquatable() throws
    {
        #expect( SwiftAstro.Error( message: "Foo" ) == SwiftAstro.Error( message: "Foo" ) )
        #expect( SwiftAstro.Error( message: "Foo" ) != SwiftAstro.Error( message: "Bar" ) )
    }
}
