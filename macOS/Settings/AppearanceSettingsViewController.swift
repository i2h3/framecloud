// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

class AppearanceSettingsViewController: NSViewController {
    @IBOutlet
    var translucentAppearance: NSSwitch!

    @IBOutlet
    var removeGaps: NSSwitch!

    /// `logger` records the appearance settings tab's activity under the `AppearanceSettingsViewController` category.
    private let logger = Logger(for: AppearanceSettingsViewController.self)

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("Appearance settings tab loaded")

        // Reflect the persisted choices, falling back to the app defaults the account has not overridden yet:
        // translucency is off by default, removing the content gaps is on.
        translucentAppearance.state = (AccountStore.shared.translucentAppearance ?? false) ? .on : .off
        removeGaps.state = (AccountStore.shared.removeGaps ?? true) ? .on : .off
    }

    @IBAction
    func translucentAppearanceSwitched(_: Any) {
        AccountStore.shared.setTranslucentAppearance(translucentAppearance.state == .on)
    }

    @IBAction
    func gapsSwitched(_: Any) {
        AccountStore.shared.setRemoveGaps(removeGaps.state == .on)
    }
}
