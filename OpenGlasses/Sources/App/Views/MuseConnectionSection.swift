import ForITCommon
import SwiftUI
import UIKit

/// The account holder transfers the credential from the phone to Muse's secure form.
@MainActor
struct MuseConnectionSection: View {
    @ObservedObject private var account = AppAccount.shared
    @StateObject private var signIn = CentralAuthBrowserSignIn(configuration: AppAccount.authConfiguration)
    @AppStorage("museVoiceGrantMetadata") private var savedGrants = Data()
    let windowSource: AuthWindowReader.WindowSource

    @State private var issued: ForITVoiceKey?
    @State private var copiedChangeCount: Int?
    @State private var work: Task<Void, Never>?
    @State private var operation: UUID?
    @State private var error: String?
    @State private var confirmingRevoke = false

    private struct Grant: Codable {
        let label: String
        let expiresAt: Date
        let confirmed: Bool
    }

    private var grants: [String: Grant] {
        (try? JSONDecoder().decode([String: Grant].self, from: savedGrants)) ?? [:]
    }

    private var grant: Grant? {
        guard let email = account.email?.lowercased(),
              let grant = grants[email], grant.expiresAt > Date() else { return nil }
        return grant
    }

    var body: some View {
        Section {
            if let fresh = issued {
                Button("Copy Muse connection key") { copy(fresh) }
                    .buttonStyle(.forITText(on: .navy))
                if copiedChangeCount != nil {
                    Text("Paste the key into Muse’s secure form within one minute.")
                        .font(.footnote)
                }
            } else if grant == nil {
                Button("Create Muse connection key") { createKey() }
                    .buttonStyle(.forITText(on: .navy))
                    .disabled(operation != nil || account.isSigningIn)
            }
            if signIn.isWaitingForBrowser {
                Button("Cancel sign-in") { clearTemporaryState() }
                    .buttonStyle(.forITText(on: .navy))
            } else if operation != nil {
                ProgressView()
                    .accessibilityLabel("Updating Muse connection key")
            }
            if let grant {
                if grant.confirmed {
                    LabeledContent("Key expires", value: grant.expiresAt.formatted(date: .abbreviated, time: .omitted))
                } else {
                    Text("Key creation is unverified. Revoke it before trying again.")
                        .font(.footnote)
                }
                Button("Revoke Muse key", role: .destructive) { confirmingRevoke = true }
                    .disabled(operation != nil)
            }
            if let error { Text(error).font(.footnote) }
        } header: {
            Text("Muse")
        } footer: {
            Text("A key lets Muse use your Bernard data and tools for 30 days. Bernard blocks sends and approvals through Muse. You can revoke the key anytime.")
        }
        .confirmationDialog("Revoke Muse key?", isPresented: $confirmingRevoke, titleVisibility: .visible) {
            Button("Revoke key", role: .destructive) { revokeKey() }
        } message: {
            Text("Muse will need a new key to talk to Bernard.")
        }
        .onChange(of: account.email) { _, _ in clearTemporaryState() }
        .onDisappear { clearTemporaryState() }
    }

    private func createKey() {
        guard operation == nil, grant == nil, let email = account.email else { return }
        guard let window = windowSource.window else {
            error = "Couldn’t open sign-in. Try again."
            return
        }
        let anchor = AuthWindowProvider(window: window)
        let id = beginOperation()
        let label = "Muse Bernard " + UUID().uuidString
        work = Task {
            defer { finishOperation(id) }
            do {
                let authorization = try await signIn.signIn(presentationContextProvider: anchor)
                try Task.checkCancellation()
                guard operation == id, account.email == email else { return }
                // Retain a recovery handle before the once-only exchange. No key is stored here.
                let pending = Grant(label: label, expiresAt: Date().addingTimeInterval(30 * 86_400 + 60),
                                    confirmed: false)
                try save(pending, for: email)
                let result = try await ForITVoiceKey.mint(
                    code: authorization.code, codeVerifier: authorization.codeVerifier, nonce: authorization.nonce,
                    expectedEmail: email, label: label)
                guard operation == id, account.email == email, !Task.isCancelled else { return }
                try save(Grant(label: label, expiresAt: result.expiresAt, confirmed: true), for: email)
                issued = result
            } catch CentralAuthError.cancelled {
            } catch is CancellationError {
            } catch {
                guard operation == id else { return }
                switch error {
                case ForITAccountError.identityMismatch:
                    self.error = "Use the same ForIT account as on this iPhone."
                default:
                    self.error = grant == nil ? "Couldn’t create a Muse key. Try again."
                        : "Couldn’t verify the new key. Revoke it before creating another."
                }
            }
        }
    }

    private func copy(_ key: ForITVoiceKey) {
        do {
            copiedChangeCount = try key.copyToPasteboard()
            error = nil
        } catch {
            self.error = "This key has expired. Create a new key."
            discardIssued()
        }
    }

    private func revokeKey() {
        guard operation == nil, let grant, let session = account.session else { return }
        let id = beginOperation()
        work = Task {
            defer { finishOperation(id) }
            do {
                try await ForITVoiceKey.revoke(label: grant.label, using: session.key)
                if grants[session.email.lowercased()]?.label == grant.label {
                    try save(nil, for: session.email)
                }
                guard operation == id else { return }
                discardIssued()
            } catch {
                if operation == id { self.error = "Couldn’t revoke the Muse key. Try again." }
            }
        }
    }

    private func save(_ grant: Grant?, for email: String) throws {
        var current = grants
        current[email.lowercased()] = grant
        savedGrants = try JSONEncoder().encode(current)
    }

    private func beginOperation() -> UUID {
        let id = UUID()
        operation = id
        error = nil
        return id
    }

    private func finishOperation(_ id: UUID) {
        guard operation == id else { return }
        operation = nil
        work = nil
    }

    private func discardIssued() {
        if let copiedChangeCount { ForITVoiceKey.clearCopiedValue(changeCount: copiedChangeCount) }
        copiedChangeCount = nil
        issued = nil
    }

    private func clearTemporaryState() {
        operation = nil
        work?.cancel()
        work = nil
        signIn.cancel()
        discardIssued()
        error = nil
    }
}
