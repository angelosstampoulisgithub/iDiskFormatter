//
//  Models.swift
//  iDiskFormatter
//
//  Created by Angelos Staboulis on 17/11/26.
//

import Foundation

enum DiskFormat: String, CaseIterable, Identifiable {
    case apfs = "APFS"
    case apfsEncrypted = "APFS Encrypted"
    case exFAT = "exFAT"
    case fat32 = "FAT32"
    case macOSJournaled = "Mac OS Extended (Journaled)"

    var id: String { rawValue }

    var diskutilFilesystem: String {
        switch self {
        case .apfs, .apfsEncrypted: return "APFS"
        case .exFAT: return "ExFAT"
        case .fat32: return "MS-DOS"
        case .macOSJournaled: return "JHFS+"
        }
    }

    var partitionScheme: String {
        self == .fat32 ? "MBRFormat" : "GPTFormat"
    }

    var explanation: String {
        switch self {
        case .apfs: return "Best for modern macOS systems and SSDs."
        case .apfsEncrypted: return "APFS with password-based encryption."
        case .exFAT: return "Works with modern macOS and Windows."
        case .fat32: return "Broad compatibility; individual files are limited to 4 GB."
        case .macOSJournaled: return "Legacy Mac format; useful for older macOS versions."
        }
    }
}



