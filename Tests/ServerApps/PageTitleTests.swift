// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `PageTitleTests` covers `PageTitle`, which shortens a Nextcloud page's own title for use as the app's.
///
/// The rule it implements is positional — drop the last of the components Nextcloud joins a title from — and the reason to test it case by case is that the input is a string a server composed and can compose differently. Half the cases below are therefore not titles this will improve but titles it must not damage: a shortening rule that can return an empty string, or that mangles an instance whose own name is unusual, is worse than no rule, because what it produces is what the user reads.
///
struct PageTitleTests {
    @Test
    func `The instance's name is dropped from an ordinary title`() {
        #expect(PageTitle.withoutSiteName("Files - Nextcloud") == "Files")
    }

    @Test
    func `Only the instance's name is dropped from a title with more parts`() {
        // Talk titles a conversation this way, and "Ada" alone would say less than the app it is in.
        #expect(PageTitle.withoutSiteName("Ada - Talk - Nextcloud") == "Ada - Talk")
    }

    @Test
    func `A title with nothing to drop is left alone`() {
        #expect(PageTitle.withoutSiteName("Nextcloud") == "Nextcloud")
    }

    @Test
    func `An empty title stays empty rather than becoming something`() {
        #expect(PageTitle.withoutSiteName("") == "")
    }

    @Test
    func `A title that is nothing but an instance name is left alone`() {
        // Dropping the last component here would leave the empty string, so the rule declines to apply.
        #expect(PageTitle.withoutSiteName(" - Nextcloud") == " - Nextcloud")
    }

    @Test
    func `An instance whose own name carries the separator is only partly dropped`() {
        // Pinned rather than fixed: the rule cannot tell this apart from a three-component title, and the
        // instance's real name is not known where this runs. A longer title, not a wrong one.
        #expect(PageTitle.withoutSiteName("Files - Ada's - Cloud") == "Files - Ada's")
    }

    @Test
    func `A separator without spaces is not one`() {
        // Nextcloud joins with " - ". A hyphen inside a document's own name is part of the name.
        #expect(PageTitle.withoutSiteName("Second-Quarter Report") == "Second-Quarter Report")
    }
}
