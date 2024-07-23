//
//  Models.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

// 用于解析模型列表的响应
struct ModelListResponse: Codable {
    let object: String
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let id: String
    let object: String
    let created: Int?
    let owned_by: String?
}
