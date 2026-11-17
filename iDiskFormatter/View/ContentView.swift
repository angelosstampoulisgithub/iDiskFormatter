//
//  ContentView.swift
//  iDiskFormatter
//
//  Created by Angelos Staboulis on 17/11/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var service = DiskService()
    @State private var selectedDisk: ExternalDisk?
    @State private var volumeName = "Untitled"
    @State private var selectedFormat: DiskFormat = .exFAT
    @State private var encryptionPassword = ""
    @State private var showingConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } detail: {
            detail
        }
        .task { await service.refresh() }
        .confirmationDialog(
            "Erase \(selectedDisk?.name ?? "selected disk")?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase Disk", role: .destructive) {
                Task { await performErase() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All data on the selected external disk will be permanently erased. This cannot be undone.")
        }
        .alert("Unable to format disk", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Label("External Disks", systemImage: "externaldrive")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(service.isLoading || service.isFormatting)
                .help("Refresh disk list")
            }
            .padding()

            Divider()

            if service.isLoading && service.disks.isEmpty {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.disks.isEmpty {
                ContentUnavailableView(
                    "No External Disks",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Connect a USB drive, SSD, or external hard disk.")
                )
            } else {
                List(selection: $selectedDisk) {
                    ForEach(service.disks) { disk in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(disk.name, systemImage: "externaldrive.fill")
                                .lineLimit(1)
                            HStack {
                                Text(disk.identifier)
                                Spacer()
                                Text(disk.formattedSize)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(disk)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("External physical disks only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
        .background(.regularMaterial)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Formatter")
                        .font(.largeTitle.bold())
                    Text("Prepare and erase external storage devices")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 24)

            Divider()

            if let disk = selectedDisk {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        diskSummary(disk)
                        formatSettings
                        if selectedFormat == .apfsEncrypted {
                            encryptionSettings
                        }
                        warningPanel
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                showingConfirmation = true
                            } label: {
                                Label("Erase Disk…", systemImage: "trash")
                                    .frame(minWidth: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(service.isFormatting || volumeName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      (selectedFormat == .apfsEncrypted && encryptionPassword.count < 8))
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Select a Disk",
                    systemImage: "externaldrive",
                    description: Text("Choose an external disk from the sidebar to view its details and formatting options.")
                )
            }

            if service.isFormatting || service.operationMessage != nil {
                Divider()
                HStack(spacing: 10) {
                    if service.isFormatting { ProgressView().controlSize(.small) }
                    Text(service.operationMessage ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: service.disks) { _, disks in
            if let selectedDisk, !disks.contains(selectedDisk) {
                self.selectedDisk = nil
            }
        }
    }

    private func diskSummary(_ disk: ExternalDisk) -> some View {
        GroupBox {
            VStack(spacing: 14) {
                summaryRow("Device", value: disk.name, icon: "externaldrive.fill")
                Divider()
                summaryRow("Identifier", value: disk.identifier, icon: "number")
                Divider()
                summaryRow("Capacity", value: disk.formattedSize, icon: "internaldrive")
                Divider()
                summaryRow("Connection", value: disk.protocolName, icon: "cable.connector")
            }
            .padding(.vertical, 5)
        } label: {
            Label("Selected Device", systemImage: "info.circle")
                .font(.headline)
        }
    }

    private func summaryRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }

    private var formatSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                    TextField("Enter volume name", text: $volumeName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.subheadline.weight(.medium))
                    Picker("Filesystem", selection: $selectedFormat) {
                        ForEach(DiskFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text(selectedFormat.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Partition scheme", systemImage: "square.grid.3x3")
                    Spacer()
                    Text(selectedFormat == .fat32 ? "Master Boot Record (MBR)" : "GUID Partition Map (GPT)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 5)
        } label: {
            Label("Formatting Options", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var encryptionSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Encryption password (8+ characters)", text: $encryptionPassword)
                    .textFieldStyle(.roundedBorder)
                Text("Choose a strong password and keep it safe. Without it, the encrypted volume cannot be unlocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        } label: {
            Label("APFS Encryption", systemImage: "lock.fill")
                .font(.headline)
        }
    }

    private var warningPanel: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("This operation permanently erases the selected disk.")
                    .fontWeight(.semibold)
                Text("Check the device name and capacity carefully before continuing. Back up any files you need.")
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func performErase() async {
        guard let selectedDisk else { return }
        do {
            try await service.erase(
                selectedDisk,
                name: volumeName,
                format: selectedFormat,
                password: selectedFormat == .apfsEncrypted ? encryptionPassword : nil
            )
            encryptionPassword = ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    ContentView()
}
