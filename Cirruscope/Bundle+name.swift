// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

extension Bundle {
    ///
    /// Run-time lookup of `CFBundleName`.
    ///
    var name: String {
        object(forInfoDictionaryKey: "CFBundleName") as? String ?? "nil"
    }
}
