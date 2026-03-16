//
//  String+ArrayConversion.swift
//  WireguardTunnelProvider
//
//  Created by Shahzain Ali on 13/06/2022.
//  Copyright © 2022 Unseen Online. All rights reserved.
//

import Foundation

import Foundation

extension String {

    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        return split(separator: separator)
            .map {
                if let charSet = trimmingCharacters {
                    return $0.trimmingCharacters(in: charSet)
                } else {
                    return String($0)
                }
        }
    }

}

extension Optional where Wrapped == String {

    func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
        switch self {
        case .none:
            return []
        case .some(let wrapped):
            return wrapped.splitToArray(separator: separator, trimmingCharacters: trimmingCharacters)
        }
    }

}
