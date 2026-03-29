import SwiftUI
import NetworkExtension

struct SettingsSheet: Identifiable {
    let id = UUID()
    let profileID: UUID
    let isNew: Bool
}

struct ContentView: View {
    var app: TurnBridge

    @State private var vpnStatus: NEVPNStatus = .disconnected
    @StateObject private var store = ProfileStore()

    @State private var showImportModal = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var settingsSheet: SettingsSheet?

    var body: some View {
        NavigationStack {
            VStack {
                VStack(spacing: 4) {
                    Text("TurnBridge")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 30)

                if !store.profiles.isEmpty {
                    profilePicker
                        .padding(.top, 12)
                        .padding(.horizontal, 40)
                        .disabled(vpnStatus != .disconnected)
                }

                Spacer()

                VStack(spacing: 50) {
                    Image(systemName: vpnStatus == .connected ? "lock.shield.fill" : "lock.shield")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundColor(iconColor)
                        .shadow(color: iconColor.opacity(0.4), radius: vpnStatus == .connected ? 20 : 0)
                        .scaleEffect(vpnStatus == .connecting ? 1.1 : 1.0)
                        .animation(vpnStatus == .connecting ? .easeInOut(duration: 1).repeatForever() : .default, value: vpnStatus)

                    Button(action: toggleTunnel) {
                        Text(buttonText)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(buttonColor)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: buttonColor.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .disabled(vpnStatus == .connecting || vpnStatus == .disconnecting || store.selectedProfile == nil)
                    .padding(.horizontal, 40)
                }

                Spacer()
            }
            .overlay {
                if showImportModal {
                    importModalView
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation { showImportModal = true }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .disabled(vpnStatus != .disconnected)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        guard let id = store.selectedProfileID else { return }
                        settingsSheet = SettingsSheet(profileID: id, isNew: false)
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .disabled(vpnStatus != .disconnected || store.selectedProfile == nil)
                }
            }
            .sheet(item: $settingsSheet) { sheet in
                NavigationStack {
                    SettingsView(store: store, profileID: sheet.profileID, isNewProfile: sheet.isNew)
                }
            }
            .onAppear(perform: checkInitialStatus)
            .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { notification in
                if let connection = notification.object as? NEVPNConnection {
                    withAnimation { self.vpnStatus = connection.status }
                }
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var profilePicker: some View {
        Menu {
            ForEach(store.profiles) { profile in
                Button(action: {
                    store.selectedProfileID = profile.id
                    store.save()
                }) {
                    if profile.id == store.selectedProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            HStack {
                Text(store.selectedProfile?.name ?? "Select Profile")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var importModalView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showImportModal = false }
                }

            VStack(spacing: 16) {
                Text("Add Configuration")
                    .font(.headline)

                Button(action: importFromClipboard) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from Clipboard")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: addManualProfile) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Add Manually")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: {
                    withAnimation { showImportModal = false }
                }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                }
            }
            .padding(24)
            .frame(width: 300)
            .background(.regularMaterial)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private var buttonText: String {
        switch vpnStatus {
        case .connected: return "Disconnect"
        case .connecting: return "Please wait..."
        case .disconnecting: return "Stopping..."
        default: return "Connect"
        }
    }

    private var buttonColor: Color {
        switch vpnStatus {
        case .connected: return .red
        case .connecting, .disconnecting: return .orange
        default: return .blue
        }
    }

    private var iconColor: Color {
        switch vpnStatus {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        default: return .gray
        }
    }

    private func validateConfig(_ profile: VPNProfile) -> String? {
        if profile.vkLink.isEmpty {
            return "Please provide a valid TURN Server URL."
        }
        if profile.peerAddr.isEmpty {
            return "Please provide a valid Peer Address."
        }
        if profile.listenAddr.isEmpty {
            return "Please provide a valid Listen Address."
        }
        if profile.wgQuickConfig.isEmpty {
            return "Please provide a valid WireGuard configuration."
        }
        return nil
    }

    private func toggleTunnel() {
        if vpnStatus == .connected {
            app.turnOffTunnel()
        } else {
            guard let profile = store.selectedProfile else { return }
            if let errorMessage = validateConfig(profile) {
                showAlert(title: "Configuration Required", message: errorMessage)
                return
            }

            vpnStatus = .connecting
            app.turnOnTunnel(
                vkLink: profile.vkLink,
                peerAddr: profile.peerAddr,
                listenAddr: profile.listenAddr,
                nValue: profile.nValue,
                wgQuickConfig: profile.wgQuickConfig
            ) { isSuccess in
                if !isSuccess {
                    vpnStatus = .disconnected
                    print("Failed to turn on tunnel")
                }
            }
        }
    }

    private func checkInitialStatus() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let manager = managers?.first {
                self.vpnStatus = manager.connection.status
            } else {
                self.vpnStatus = .disconnected
            }
        }
    }

    private func importFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else {
            withAnimation { showImportModal = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAlert(title: "Error", message: "Clipboard is empty.")
            }
            return
        }

        do {
            let config = try ConfigParser.parse(from: clipboardString)
            let profile = VPNProfile(
                name: config.name ?? "Profile",
                vkLink: config.turn,
                peerAddr: config.peer,
                listenAddr: config.listen,
                nValue: config.n,
                wgQuickConfig: config.wg
            )
            store.addProfile(profile)

            withAnimation { showImportModal = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAlert(title: "Success", message: "Profile \"\(store.selectedProfile?.name ?? "")\" imported.")
            }
        } catch {
            withAnimation { showImportModal = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func addManualProfile() {
        withAnimation { showImportModal = false }
        let profile = VPNProfile(name: "Profile")
        store.addProfile(profile)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            settingsSheet = SettingsSheet(profileID: profile.id, isNew: true)
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}
