import Foundation
import Combine

class ProfileStore: ObservableObject {
    @Published var profiles: [VPNProfile] = []
    @Published var selectedProfileID: UUID?

    private let profilesKey = "vpnProfiles"
    private let selectedIDKey = "selectedProfileID"

    var selectedProfile: VPNProfile? {
        get {
            guard let id = selectedProfileID else { return nil }
            return profiles.first { $0.id == id }
        }
        set {
            guard let newValue, let idx = profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
            profiles[idx] = newValue
            save()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([VPNProfile].self, from: data) {
            self.profiles = decoded
            if let idString = UserDefaults.standard.string(forKey: selectedIDKey),
               let id = UUID(uuidString: idString),
               decoded.contains(where: { $0.id == id }) {
                self.selectedProfileID = id
            } else {
                self.selectedProfileID = decoded.first?.id
            }
        } else {
            migrateFromLegacy()
        }
    }

    func addProfile(_ profile: VPNProfile) {
        var p = profile
        p.name = uniqueName(for: p.name.isEmpty ? "Profile" : p.name)
        profiles.append(p)
        selectedProfileID = p.id
        save()
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
        save()
    }

    func uniqueName(for base: String) -> String {
        let existingNames = Set(profiles.map(\.name))
        if !existingNames.contains(base) { return base }
        var counter = 2
        while existingNames.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = selectedProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedIDKey)
        }
    }

    private func migrateFromLegacy() {
        let defaults = UserDefaults.standard
        guard let vkLink = defaults.string(forKey: "vkLink"),
              !vkLink.contains("YOUR_INVITE_LINK") else { return }

        let profile = VPNProfile(
            name: "Profile 1",
            vkLink: vkLink,
            peerAddr: defaults.string(forKey: "peerAddr") ?? "",
            listenAddr: defaults.string(forKey: "listenAddr") ?? "127.0.0.1:9000",
            nValue: max(defaults.integer(forKey: "nValue"), 1),
            wgQuickConfig: defaults.string(forKey: "wgQuickConfig") ?? ""
        )
        profiles = [profile]
        selectedProfileID = profile.id
        save()

        for key in ["vkLink", "peerAddr", "listenAddr", "nValue", "wgQuickConfig"] {
            defaults.removeObject(forKey: key)
        }
    }
}
