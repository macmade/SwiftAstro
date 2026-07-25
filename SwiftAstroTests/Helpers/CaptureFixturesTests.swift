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

/// Verifies that every relocated capture resolves by name from SwiftAstro's
/// `Test Files` tree — the invariant the per-format decoder milestones rely on
/// when they open a capture through ``CaptureFixtures/url(named:)``.
@Suite( "CaptureFixtures" )
struct CaptureFixturesTests
{
    /// Every capture in the manifest resolves to a file that exists on disk. This
    /// pins the fixture relocation: a capture that failed to move, or moved under
    /// the wrong name, fails here rather than surfacing as a missing-file error in
    /// a later decoder test.
    @Test
    func everyCaptureResolvesToAFileThatExists() throws
    {
        try CaptureFixtures.captureFileNames.forEach
        {
            name in

            let url = try CaptureFixtures.url( named: name )

            #expect( FileManager.default.fileExists( atPath: url.path ), "Capture \( name ) resolved to \( url.path ), which does not exist." )
            #expect( url.lastPathComponent == name )
        }
    }

    /// No two captures share a file name. The resolver keys on `lastPathComponent`
    /// and returns the first match, so a name collision would silently resolve to
    /// the wrong file; the manifest must stay unique for the lookup to be
    /// unambiguous.
    @Test
    func captureNamesAreUnique()
    {
        let names  = CaptureFixtures.captureFileNames
        let unique = Set( names )

        #expect( unique.count == names.count, "Two captures share a file name; the name-keyed resolver needs them unique." )
    }

    /// Resolving a name that is not a committed capture throws rather than
    /// returning a bogus URL, so a typo in a decoder test fails loudly.
    @Test
    func resolvingAnUnknownCaptureThrows()
    {
        #expect( throws: ( any Swift.Error ).self )
        {
            try CaptureFixtures.url( named: "ThisCaptureDoesNotExist.fits" )
        }
    }
}
