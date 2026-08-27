// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        if store.account == nil {
            ServerAddressView()
        } else {
            NextcloudView()
        }
    }
}
