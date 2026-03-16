//
//  Created by nullcstring.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: VPNSettings

    var body: some View {
        Form {
            Section(header: Text("Proxy Settings")) {
                TextField("TURN Server URL", text: $settings.vkLink)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                TextField("Peer Address (IP:Port)", text: $settings.peerAddr)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                TextField("Listen Address (IP:Port)", text: $settings.listenAddr)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Stepper("Connections (n): \(settings.nValue)", value: $settings.nValue, in: 1...10)
            }
            
            Section(header: Text("WireGuard Config")) {
                TextEditor(text: $settings.wgQuickConfig)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 300)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
