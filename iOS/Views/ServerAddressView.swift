// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

struct ServerAddressView: View {
    @State
    private var enteredServerAddress = ""
    @State
    private var isConnecting: Bool

    init(isConnecting: Bool = false) {
        _isConnecting = State(initialValue: isConnecting)
    }

    var body: some View {
        VStack {
            Spacer()

            Text(verbatim: "Cirruscope")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Gradient(colors: [.accent.opacity(0.75), .accent]))
                .shadow(color: .accent, radius: 24, x: 0, y: 0)
                .padding(.bottom)

            Text("Your Nextcloud experience, elevated.")
                .foregroundStyle(.tertiary)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Text("Enter your Nextcloud server address:")

                HStack(spacing: 16) {
                    TextField("Server Address", text: $enteredServerAddress, prompt: Text(verbatim: "https://your.nextcloud.com"))
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .disabled(isConnecting)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Button {
                            //
                        } label: {
                            Label("Connect", systemImage: "arrow.right.circle.fill")
                                .imageScale(.large)
                                .labelStyle(.iconOnly)
                                .controlSize(.extraLarge)
                        }
                    }
                }

                Text("Assuming HTTPS for a secure connection unless specified differently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Link("Privacy Policy", destination: URL(string: "https://cirruscope.app")!) // TODO: Settings.privacyPolicy
                Spacer()
                Link("Support", destination: URL(string: "https://cirruscope.app")!) // TODO: Settings.support
            }
            .font(.footnote)
        }
        .padding()
    }
}

#Preview("Default") {
    ServerAddressView()
}

#Preview("Connecting") {
    ServerAddressView(isConnecting: true)
}
