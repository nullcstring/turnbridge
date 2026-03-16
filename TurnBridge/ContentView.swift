//
//  Created by nullcstring.
//

import SwiftUI
import NetworkExtension

struct ContentView: View {
    var app: TurnBridge
    
    @State private var vpnStatus: NEVPNStatus = .disconnected
    @StateObject private var settings = VPNSettings()
    
    @State private var showImportModal = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            VStack {
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
                    .padding(.top, 30)
                
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
                    .disabled(vpnStatus == .connecting || vpnStatus == .disconnecting)
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
                    NavigationLink(destination: SettingsView(settings: settings)) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .disabled(vpnStatus != .disconnected)
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
    
    private var importModalView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showImportModal = false }
                }
            
            VStack(spacing: 25) {
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
    
    private func validateConfig() -> String? {
        if settings.vkLink.isEmpty || settings.vkLink.contains("YOUR_INVITE_LINK") {
            return "Please provide a valid TURN Server URL."
        }
        if settings.peerAddr.isEmpty || settings.peerAddr.contains("SERVER_IP:PORT") {
            return "Please provide a valid Peer Address."
        }
        if settings.listenAddr.isEmpty || settings.listenAddr.contains("LISTEN_PORT") {
            return "Please provide a valid Listen Address."
        }
        if settings.wgQuickConfig.isEmpty ||
           settings.wgQuickConfig.contains("YOUR_CLIENT_PRIVATE_KEY_HERE") ||
           settings.wgQuickConfig.contains("YOUR_SERVER_PUBLIC_KEY_HERE") ||
           settings.wgQuickConfig.contains("IP_ADDRESS") {
            return "Please provide a valid WireGuard configuration with your specific keys and IP address."
        }
        return nil
    }
    
    private func toggleTunnel() {
        if vpnStatus == .connected {
            app.turnOffTunnel()
        } else {
            if let errorMessage = validateConfig() {
                showAlert(title: "Configuration Required", message: errorMessage)
                return
            }
            
            vpnStatus = .connecting
            app.turnOnTunnel(
                vkLink: settings.vkLink,
                peerAddr: settings.peerAddr,
                listenAddr: settings.listenAddr,
                nValue: settings.nValue,
                wgQuickConfig: settings.wgQuickConfig
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
            
            settings.vkLink = config.turn
            settings.peerAddr = config.peer
            settings.listenAddr = config.listen
            settings.nValue = config.n
            settings.wgQuickConfig = config.wg
            
            withAnimation { showImportModal = false }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAlert(title: "Success", message: "Configuration imported successfully!")
            }
            
        } catch {
            withAnimation { showImportModal = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}
