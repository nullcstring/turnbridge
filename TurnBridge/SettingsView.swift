import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    var profileID: UUID
    var isNewProfile: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VPNProfile?
    @State private var showDeleteConfirmation = false

    private var profile: VPNProfile {
        draft ?? store.profiles.first(where: { $0.id == profileID }) ?? VPNProfile()
    }

    var body: some View {
        Form {
            Section(header: Text("Profile")) {
                TextField("Profile Name", text: binding(\.name))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            Section(header: Text("Proxy Settings")) {
                TextField("TURN Server URL", text: binding(\.vkLink))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Peer Address (IP:Port)", text: binding(\.peerAddr))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Listen Address (IP:Port)", text: binding(\.listenAddr))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Stepper("Connections (n): \(profile.nValue)", value: binding(\.nValue), in: 1...10)
            }

            Section(header: Text("WireGuard Config")) {
                TextEditor(text: binding(\.wgQuickConfig))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 150)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            Section {
                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text("Delete Profile")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(isNewProfile ? "New Profile" : "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
        }
        .onAppear {
            if draft == nil {
                draft = store.profiles.first(where: { $0.id == profileID })
            }
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                store.deleteProfile(profileID)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Profile \"\(profile.name)\" will be permanently deleted.")
        }
        .onDisappear {
            guard let draft else { return }
            if store.profiles.contains(where: { $0.id == profileID }) {
                store.selectedProfile = draft
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<VPNProfile, T>) -> Binding<T> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                if draft == nil {
                    draft = store.profiles.first(where: { $0.id == profileID })
                }
                draft?[keyPath: keyPath] = newValue
            }
        )
    }
}
