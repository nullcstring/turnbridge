//
//  Created by nullcstring.
//

import SwiftUI
import NetworkExtension

@main
struct TurnBridge: App {
    var body: some Scene {
        WindowGroup {
            ContentView(app: self)
        }
    }
    
    func turnOnTunnel(vkLink: String, peerAddr: String, listenAddr: String, nValue: Int, wgQuickConfig: String,completionHandler: @escaping (Bool) -> Void) {

           NETunnelProviderManager.loadAllFromPreferences { tunnelManagersInSettings, error in
               if let error = error {
                   NSLog("Error (loadAllFromPreferences): \(error)")
                   completionHandler(false)
                   return
               }

               let preExistingTunnelManager = tunnelManagersInSettings?.first
               let tunnelManager = preExistingTunnelManager ?? NETunnelProviderManager()

               // Configure the custom VPN protocol
               let protocolConfiguration = NETunnelProviderProtocol()

               // Set the tunnel extension's bundle id
               protocolConfiguration.providerBundleIdentifier = "com.netlab.TurnBridge.network-extension"
               let cleanIP = peerAddr.components(separatedBy: ":").first ?? peerAddr
               protocolConfiguration.serverAddress = cleanIP
               
               protocolConfiguration.providerConfiguration = [
                "wgQuickConfig": wgQuickConfig,
                "vkLink": vkLink,
                "peerAddr": peerAddr,
                "listenAddr": listenAddr,
                "nValue": nValue
               ]

               tunnelManager.protocolConfiguration = protocolConfiguration
               tunnelManager.isEnabled = true
               tunnelManager.saveToPreferences { error in
                   if let error = error {
                       NSLog("Error (saveToPreferences): \(error)")
                       completionHandler(false)
                       return
                   }
                   // Load it back so we have a valid usable instance.
                   tunnelManager.loadFromPreferences { error in
                       if let error = error {
                           NSLog("Error (loadFromPreferences): \(error)")
                           completionHandler(false)
                           return
                       }

                       // At this point, the tunnel is configured.
                       // Attempt to start the tunnel
                       do {
                           NSLog("Starting the tunnel")
                           guard let session = tunnelManager.connection as? NETunnelProviderSession else {
                               fatalError("tunnelManager.connection is invalid")
                           }
                           try session.startTunnel()
                       } catch {
                           NSLog("Error (startTunnel): \(error)")
                           completionHandler(false)
                       }
                       completionHandler(true)
                   }
               }
           }
       }

       func turnOffTunnel() {
           NETunnelProviderManager.loadAllFromPreferences { tunnelManagersInSettings, error in
               if let error = error {
                   NSLog("Error (loadAllFromPreferences): \(error)")
                   return
               }
               if let tunnelManager = tunnelManagersInSettings?.first {
                   guard let session = tunnelManager.connection as? NETunnelProviderSession else {
                       fatalError("tunnelManager.connection is invalid")
                   }
                   switch session.status {
                   case .connected, .connecting, .reasserting:
                       NSLog("Stopping the tunnel")
                       session.stopTunnel()
                   default:
                       break
                   }
               }
           }
       }
}
