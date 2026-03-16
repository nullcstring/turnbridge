//
//  Created by nullcstring.
//

import Foundation

struct TurnConfigImport: Codable {
    let turn: String
    let peer: String
    let listen: String
    let n: Int
    let wg: String
}

enum ConfigParseError: LocalizedError {
    case emptyString
    case invalidScheme
    case invalidBase64
    case invalidJSON(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyString:
            return "The string is empty."
        case .invalidScheme:
            return "Invalid configuration format. Must start with 'turnbridge://'"
        case .invalidBase64:
            return "Invalid Base64 encoding."
        case .invalidJSON(let details):
            return "Failed to parse JSON configuration: \(details)"
        }
    }
}

struct ConfigParser {
    static let scheme = "turnbridge://"
    
    static func parse(from string: String) throws -> TurnConfigImport {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ConfigParseError.emptyString
        }
        
        guard trimmed.hasPrefix(scheme) else {
            throw ConfigParseError.invalidScheme
        }
        
        let base64String = String(trimmed.dropFirst(scheme.count))
        
        guard let jsonData = Data(base64Encoded: base64String) else {
            throw ConfigParseError.invalidBase64
        }
        
        do {
            let config = try JSONDecoder().decode(TurnConfigImport.self, from: jsonData)
            return config
        } catch {
            throw ConfigParseError.invalidJSON(error.localizedDescription)
        }
    }
}
