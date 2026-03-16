# TurnBridge

**TurnBridge** is annetwork utility. It allows you to securely route your iOS network traffic through TURN servers and WireGuard endpoints.

To run the application, you must use a [server](https://github.com/cacggghp/vk-turn-proxy/releases/tag/v1.0.0) running on a VPS.

The project is based on the repositories listed in the **Acknowledgments** section.

## ✨ Features

* **Custom Routing:** Route your traffic through specific TURN protocols and WireGuard endpoints.
* **Advanced WireGuard Support:** Full support for configuring Private/Public Keys, AllowedIPs, DNS, MTU, and PersistentKeepalive.
* **1-Click Import:** Quickly import complex configurations via base64-encoded clipboard links (`turnbridge://`).

## 📸 Screenshot
![Main Screen](screen.png)

## 🚀 Installation & Build

To build and run TurnBridge locally, you need a macOS environment with Xcode installed, as well as Go (for compiling the WireGuard/TURN bridge).

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nullcstring/turnbridge.git
   cd TurnBridge
   ```

2. **Build the Go Bridge:**
Ensure you have Go installed (`brew install go`).

Modify the Go path in the script at script/build_wireguard_go_bridge.sh, according to your setup. Refer to [this Stack Overflow answer](https://stackoverflow.com/a/64212121) for guidance.

3. **Open the project in Xcode:**
Open `TurnBridge.xcodeproj` (or `.xcworkspace` if applicable) in Xcode.
4. **Configure Code Signing:**
* Select the `TurnBridge` project in the Project Navigator.
* Go to the **Signing & Capabilities** tab.
* Select your personal Apple Developer Team.
* Ensure you update the Bundle Identifier (for both the main app and the `network-extension` target) to match your team provisioning profile.

5. **Build and Run:**
Select your target device (iPhone/iPad) and press `Cmd + R` to build and run the app.

## 🛠 Usage (Configuration Import)

TurnBridge uses a specific JSON structure encoded in Base64 for fast configuration imports.

### Configuration JSON Structure

```json
{
  "turn": "https://vk.com/call/join/...",
  "peer": "SERVER_IP:PORT",
  "listen": "127.0.0.1:9000",
  "n": 1,
  "wg": "[Interface]\nPrivateKey = ...\nAddress = 10.100.0.2/32\nDNS = 8.8.8.8\nMTU = 1280\n\n[Peer]\nPublicKey = ...\nAllowedIPs = 0.0.0.0/0\nEndpoint = 127.0.0.1:9000\nPersistentKeepalive = 25"
}
```

### Generate a Quick Import Link

You can use the included `quick_link.py` script to easily generate valid `turnbridge://` clipboard links.

1. Open `quick_link.py` in your text editor and replace the placeholder values in the `config` dictionary with your actual server parameters and WireGuard keys.
2. Run the script from your terminal:
   ```bash
   python3 quick_link.py
   ```

3. Copy the generated `turnbridge://...` link from the terminal output to your iOS clipboard.
4. Open TurnBridge, tap the `+` icon, select **Paste from Clipboard**, and tap **Connect**.

## ☕ Support My Work

If TurnBridge saved you some time, consider supporting its development! As an independent open-source project, any contribution is greatly appreciated.

**Crypto:**
* **TON:** `UQBisIcwzfQz5Rj0TofZhN2CSZXvUhQrwMmTGEiSSa9ErW5b`

Thank you for keeping the open-source spirit alive! 🚀

## License

TurnBridge is released under the [GNU General Public License v3.0](LICENSE).

Copyright (C) 2026 nullcstring

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

---
## Acknowledgements

This project was made possible thanks to the work of the open-source community. It includes code and concepts from the following excellent repositories:

* [WireGuard-Apple](https://github.com/ut360e/wireguard-apple) — Licensed under MIT / GPL.
* [Wireguardkit](https://github.com/Shahzainali/Wireguardkit) — Licensed under MIT / GPL.
* [vk-turn-proxy](https://github.com/cacggghp/vk-turn-proxy) — Licensed under the GNU GPL.