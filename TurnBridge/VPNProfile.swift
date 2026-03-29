import Foundation

struct VPNProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var vkLink: String
    var peerAddr: String
    var listenAddr: String
    var nValue: Int
    var wgQuickConfig: String

    init(id: UUID = UUID(), name: String = "", vkLink: String = "", peerAddr: String = "", listenAddr: String = "127.0.0.1:9000", nValue: Int = 1, wgQuickConfig: String = "") {
        self.id = id
        self.name = name
        self.vkLink = vkLink
        self.peerAddr = peerAddr
        self.listenAddr = listenAddr
        self.nValue = nValue
        self.wgQuickConfig = wgQuickConfig
    }
}
