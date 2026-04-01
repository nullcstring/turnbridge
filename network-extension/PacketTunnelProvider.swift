//
//  Created by nullcstring.
//

import NetworkExtension
import WireGuardKit
import WireGuardKitGo
import os

let sharedLogger = Logger(subsystem: "com.netlab.TurnBridge.network-extension", category: "wgtunnel")

enum PacketTunnelProviderError: String, Error {
    case invalidProtocolConfiguration
    case cantParseWgQuickConfig
}

private let goProxyCLoggerCallback: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void = { context, level, messageCStr in
    guard let cStr = messageCStr else { return }
    let message = String(cString: cStr).trimmingCharacters(in: .newlines)
    
    if level == 1 {
        sharedLogger.error("🔴 [GO PROXY]: \(message, privacy: .public)")
    } else {
        sharedLogger.log("🔵 [GO PROXY]: \(message, privacy: .public)")
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { [weak self] _, message in
            sharedLogger.log("🛡 [WG]: \(message, privacy: .public)")
        }
    }()

    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        sharedLogger.log("=== Starting tunnel ===")
        guard let protocolConfiguration = self.protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfiguration = protocolConfiguration.providerConfiguration else {
            sharedLogger.error("Invalid provider configuration")
            completionHandler(PacketTunnelProviderError.invalidProtocolConfiguration)
            return
        }

        guard let wgQuickConfig = providerConfiguration["wgQuickConfig"] as? String,
              let tunnelConfiguration = try? TunnelConfiguration(fromWgQuickConfig: wgQuickConfig) else {
            sharedLogger.error("wg-quick config not parseable")
            completionHandler(PacketTunnelProviderError.cantParseWgQuickConfig)
            return
        }
        
        guard let vkLink = providerConfiguration["vkLink"] as? String,
              let peerAddr = providerConfiguration["peerAddr"] as? String,
              let listenAddr = providerConfiguration["listenAddr"] as? String,
              let nValueInt = providerConfiguration["nValue"] as? Int else {
            sharedLogger.error("Missing proxy parameters in configuration")
            completionHandler(PacketTunnelProviderError.invalidProtocolConfiguration)
            return
        }
        let nValue = Int32(nValueInt)
        
        ProxySetLogger(nil, goProxyCLoggerCallback)
        
        DispatchQueue.global(qos: .userInteractive).async {
            StartProxy(vkLink, peerAddr, listenAddr, nValue)
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let ready = ProxyWaitReady(12000)
            guard let self = self else { return }
            
            if ready == 0 {
                sharedLogger.error("DTLS connection timeout!")
                completionHandler(PacketTunnelProviderError.invalidProtocolConfiguration)
                return
            }
            
            sharedLogger.log("=== DTLS ready, starting WireGuard ===")
            self.adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] adapterError in
                guard let self = self else { return }
                if let adapterError = adapterError {
                    sharedLogger.error("WireGuard adapter error: \(adapterError.localizedDescription)")
                } else {
                    let interfaceName = self.adapter.interfaceName ?? "unknown"
                    sharedLogger.error("Tunnel interface is \(interfaceName)")
                }
                completionHandler(adapterError)
            }
        }
        
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        sharedLogger.log("Stopping tunnel")
        
        StopProxy()
        
        adapter.stop { [weak self] error in
            guard self != nil else { return }
            if let error = error {
                sharedLogger.error("Failed to stop WireGuard adapter: \(error.localizedDescription)")
            }
            completionHandler()

            #if os(macOS)
            // HACK: We have to kill the tunnel process ourselves because of a macOS bug
            exit(0)
            #endif
        }
    }
    

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }
}
