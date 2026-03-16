//
//  Created by nullcstring.
//

import Foundation
import Combine

class VPNSettings: ObservableObject {
    @Published var vkLink: String {
        didSet { UserDefaults.standard.set(vkLink, forKey: "vkLink") }
    }
    
    @Published var peerAddr: String {
        didSet { UserDefaults.standard.set(peerAddr, forKey: "peerAddr") }
    }
    
    @Published var listenAddr: String {
        didSet { UserDefaults.standard.set(listenAddr, forKey: "listenAddr") }
    }
    
    @Published var nValue: Int {
        didSet { UserDefaults.standard.set(nValue, forKey: "nValue") }
    }
    
    @Published var wgQuickConfig: String {
        didSet { UserDefaults.standard.set(wgQuickConfig, forKey: "wgQuickConfig") }
    }
    
    init() {
        self.vkLink = UserDefaults.standard.string(forKey: "vkLink") ?? "YOUR_INVITE_LINK"
        self.peerAddr = UserDefaults.standard.string(forKey: "peerAddr") ?? "SERVER_IP:PORT"
        self.listenAddr = UserDefaults.standard.string(forKey: "listenAddr") ?? "127.0.0.1:LISTEN_PORT"
        
        let savedN = UserDefaults.standard.integer(forKey: "nValue")
        self.nValue = savedN == 0 ? 1 : savedN
        
        self.wgQuickConfig = UserDefaults.standard.string(forKey: "wgQuickConfig") ?? """
        [Interface]
        PrivateKey = YOUR_CLIENT_PRIVATE_KEY_HERE
        Address = IP_ADDRESS/32
        DNS = 8.8.8.8
        MTU = 1280

        [Peer]
        PublicKey = YOUR_SERVER_PUBLIC_KEY_HERE
        AllowedIPs = 0.0.0.0/0
        Endpoint = 127.0.0.1:LISTEN_PORT
        PersistentKeepalive = 25
        """
    }
}
