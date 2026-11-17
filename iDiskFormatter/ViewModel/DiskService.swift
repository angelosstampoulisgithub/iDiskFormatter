//
//  DiskService.swift
//  iDiskFormatter
//
//  Created by Angelos Staboulis on 17/11/26.
//

import Foundation
import DiskArbitration

@MainActor
final class DiskService: ObservableObject {
    @Published private(set) var disks: [ExternalDisk] = []
    @Published var isLoading = false
    @Published var operationMessage: String?
    @Published var isFormatting = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Ask macOS for external physical disks only.
            let listData = try await run(
                "/usr/sbin/diskutil",
                ["list", "-plist", "external", "physical"]
            )
            guard let plist = try PropertyListSerialization.propertyList(
                from: listData,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw DiskFormatterError.commandFailed(
                    "Unable to read disk information from macOS."
                )
            }

            let wholeDisks = plist["WholeDisks"] as? [String] ?? []
            
            var found: [ExternalDisk] = []

            for identifier in wholeDisks {
                guard identifier.range(
                    of: #"^disk[0-9]+$"#,
                    options: .regularExpression
                ) != nil else {
                    continue
                }

                do {
                    let infoData = try await run(
                        "/usr/sbin/diskutil",
                        ["info", "-plist", identifier]
                    )

                    guard let info = try PropertyListSerialization.propertyList(
                        from: infoData,
                        options: [],
                        format: nil
                    ) as? [String: Any] else {
                        continue
                    }

                    let size = (
                        info["TotalSize"] as? NSNumber
                    )?.int64Value
                    ?? (
                        info["DiskSize"] as? NSNumber
                    )?.int64Value
                    ?? 0

                    guard size > 0 else {
                        NSLog("DiskFormatter: Invalid size for %@", identifier)
                        continue
                    }

                    let mediaName = info["MediaName"] as? String
                    let deviceModel =
                        info["Device / Media Name"] as? String
                        ?? mediaName
                        ?? "External drive"

                    let displayName = mediaName ?? deviceModel

                    let bus =
                        info["BusProtocol"] as? String
                        ?? info["Protocol"] as? String
                        ?? "External"

                    found.append(
                        ExternalDisk(
                            identifier: identifier,
                            name: displayName.isEmpty
                                ? "External drive"
                                : displayName,
                            size: size,
                            protocolName: bus,
                            deviceModel: deviceModel,
                            isWhole: true
                        )
                    )

                } catch {
                    NSLog(
                        "DiskFormatter: Could not read %@: %@",
                        identifier,
                        error.localizedDescription
                    )
                }
            }

            disks = found.sorted {
                $0.identifier.localizedStandardCompare($1.identifier)
                    == .orderedAscending
            }

            if found.isEmpty {
                operationMessage = DiskFormatterError.noDisks.localizedDescription
            }

        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func erase(_ disk: ExternalDisk, name: String, format: DiskFormat, password: String?) async throws {
        guard disks.contains(disk),
              disk.identifier.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              disk.isWhole else {
            throw DiskFormatterError.invalidDisk
        }
        let safeName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !safeName.isEmpty else {
            throw DiskFormatterError.commandFailed("Enter a name for the formatted disk.")
        }

        isFormatting = true
        defer { isFormatting = false }

        operationMessage = "Erasing \(disk.identifier)…"
        let output = try await run("/usr/sbin/diskutil", [
            "eraseDisk", format.diskutilFilesystem, safeName,
            format.partitionScheme, disk.identifier
        ])
        _ = output

        if format == .apfsEncrypted {
            operationMessage = "Enabling APFS encryption…"
            guard let password, password.count >= 8 else {
                throw DiskFormatterError.commandFailed("The disk was formatted as APFS, but encryption was not enabled. Use a password of at least 8 characters and try again.")
            }

            // The passphrase is sent over stdin, not placed in process arguments.
            let infoData = try await run("/usr/sbin/diskutil", ["list", "-plist", disk.identifier])
            let plist = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
            let volumes = plist?["AllDisks"] as? [String] ?? []
            guard let volume = volumes.first(where: { $0.hasPrefix(disk.identifier + "s") }) else {
                throw DiskFormatterError.commandFailed("The APFS container was created, but its volume could not be located for encryption.")
            }
            try await runWithStandardInput(
                "/usr/sbin/diskutil",
                ["apfs", "encryptVolume", volume, "-user", "disk", "-stdinpassphrase"],
                input: password + "\n"
            )
        }

        operationMessage = "Format completed successfully."
        await refresh()
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData.isEmpty ? output : errorData, encoding: .utf8) ?? "diskutil failed."
                throw DiskFormatterError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }

    private func runWithStandardInput(_ executable: String, _ arguments: [String], input: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData.isEmpty ? output : errorData, encoding: .utf8) ?? "Encryption failed."
                throw DiskFormatterError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }
}
