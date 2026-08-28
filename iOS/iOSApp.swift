// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct iOSApp: App {
    let store = Store.restored()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
