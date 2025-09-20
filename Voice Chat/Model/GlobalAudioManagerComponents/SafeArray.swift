//
//  SafeArray.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

extension Array {
    subscript(safe idx: Int) -> Element? {
        (indices.contains(idx) ? self[idx] : nil)
    }
}
