//
//  DiskFormatterError.swift
//  iDiskFormatter
//
//  Created by Angelos Staboulis on 17/11/26.
//

import Foundation
enum DiskFormatterError: LocalizedError {
    case commandFailed(String)
    case invalidDisk
    case noDisks

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .invalidDisk: return "The selected disk is no longer available or is not eligible for formatting."
        case .noDisks: return "No eligible external disks were found."
        }
    }
}
