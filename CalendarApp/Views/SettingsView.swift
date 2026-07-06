import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [CalendarAccount]
    @Environment(SyncManager.self) private var syncManager
    @State private var showingAddAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section("CalDAV Accounts") {
                    ForEach(accounts) { account in
                        NavigationLink(destination: AccountDetailView(account: account)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.name)
                                        .font(.body)
                                    Text(account.username + " @ " + shortURL(account.serverURL))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !account.isEnabled {
                                    Text("Disabled")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteAccounts)

                    Button(action: { showingAddAccount = true }) {
                        Label("Add Account", systemImage: "plus.circle.fill")
                    }
                }

                Section("Sync") {
                    HStack {
                        Text("Status")
                        Spacer()
                        if syncManager.isSyncing {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Syncing…").foregroundStyle(.secondary)
                            }
                        } else if let date = syncManager.lastSyncDate {
                            Text(relativeDate(date))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never").foregroundStyle(.secondary)
                        }
                    }

                    if let error = syncManager.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sync Now") {
                        Task { await syncManager.syncAll() }
                    }
                    .disabled(syncManager.isSyncing)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(modelContext: modelContext)
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            Keychain.delete(account: account.username + "@" + account.serverURL)
            modelContext.delete(account)
        }
        try? modelContext.save()
    }

    private func shortURL(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private func relativeDate(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Account Detail

struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: CalendarAccount

    var body: some View {
        List {
            Section("Calendars") {
                ForEach(account.collections) { col in
                    HStack {
                        Circle()
                            .fill(Color(hex: col.colorHex ?? "#4A90D9") ?? .blue)
                            .frame(width: 12, height: 12)
                        Text(col.displayName)
                        Spacer()
                        Toggle("", isOn: Binding(get: { col.isEnabled }, set: { col.isEnabled = $0 }))
                            .labelsHidden()
                    }
                }
            }

            Section {
                Toggle("Account Enabled", isOn: $account.isEnabled)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Account

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext

    @State private var name = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name (e.g. Nextcloud)", text: $name)
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password or App Token", text: $password)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isTesting {
                        ProgressView()
                    } else {
                        Button("Add") { addAccount() }
                            .fontWeight(.semibold)
                            .disabled(name.isEmpty || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                    }
                }
            }
        }
    }

    private func addAccount() {
        guard var url = serverURL.trimmingCharacters(in: .whitespaces) as String?,
              !url.isEmpty else { return }
        if !url.hasPrefix("http") { url = "https://" + url }

        isTesting = true
        errorMessage = nil

        Task {
            defer { isTesting = false }
            guard let serverURL = URL(string: url) else {
                errorMessage = "Invalid URL"
                return
            }

            let client = CalDAVClient(serverURL: serverURL, username: username, password: password)
            do {
                _ = try await client.discoverPrincipalURL()
                let account = CalendarAccount(name: name, serverURL: url, username: username)
                Keychain.save(password: password, account: username + "@" + url)
                modelContext.insert(account)
                try? modelContext.save()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
