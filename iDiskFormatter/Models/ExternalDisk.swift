//
//  ExternalDisk.swift
//  iDiskFormatter
//
//  Created by Angelos Staboulis on 17/11/26.
//

import Foundation

struct ExternalDisk: Identifiable, Hashable {
    let identifier: String
    let name: String
    let size: Int64
    let protocolName: String
    let deviceModel: String
    let isWhole: Bool

    var id: String { identifier }
    var devicePath: String { "/dev/\(identifier)" }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
