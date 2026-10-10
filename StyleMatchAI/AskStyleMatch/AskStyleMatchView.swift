import SwiftUI

/// The shared, consent-first entry point for the three Ask StyleMatch
/// specialties. This local implementation creates only a typed request
/// descriptor; it deliberately has no live provider or network transport.
struct AskStyleMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AskStyleMatchMode = .fashionStylist
    @State private var question = ""
    @State private var selectedWritingText = ""
    @State private var includeProfilePreferences = false
    @State private var includeClosetSummary = false
    @State private var includeScanSummary = false
    @State private var includeWeatherOccasion = false
    @State private var includeBudgetBrand = false
    @State private var status: String?
    @State private var response = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Specialty", selection: $mode) {
                        Text("Fashion Stylist").tag(AskStyleMatchMode.fashionStylist)
                        Text("App Support").tag(AskStyleMatchMode.appSupport)
                        Text("Writing Assist").tag(AskStyleMatchMode.writingAssist)
                    }
                    .accessibilityHint("Choose how Ask KigoStylist should handle this request.")
                } header: {
                    Text("Ask KigoStylist")
                } footer: {
                    Text("Each specialty has its own consent boundary. Your private Style Friends messages, scan images, and credentials are never included.")
                }

                Section("Question") {
                    TextEditor(text: $question)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Question for Ask KigoStylist")
                    Text("\(question.count)/\(AskStyleMatchRequest.maximumQuestionCharacters)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if mode == .writingAssist {
                    Section("Selected text only") {
                        TextEditor(text: $selectedWritingText)
                            .frame(minHeight: 100)
                            .accessibilityLabel("Selected text for Writing Assist")
                        Text("Writing Assist receives only the text you place here. It does not read your chats, profile, scans, or closet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == .fashionStylist {
                    Section("Optional context") {
                        Toggle("Profile preferences", isOn: $includeProfilePreferences)
                        Toggle("Closet summary", isOn: $includeClosetSummary)
                        Toggle("Completed scan summary", isOn: $includeScanSummary)
                        Toggle("Weather and occasion", isOn: $includeWeatherOccasion)
                        Toggle("Budget and brands", isOn: $includeBudgetBrand)
                    }
                }

                Section("Before you send") {
                    let disclosure = AskStyleMatchPrivacyDisclosure.make(for: selectedScopes)
                    Text(disclosure.selectedScopeLabels.isEmpty ? "No personal context selected." : "Selected context: \(disclosure.selectedScopeLabels.joined(separator: ", ")).")
                    Text("Only the context you explicitly authorize for this request is sent.")
                    Text(AskStyleMatchPrivacyDisclosure.imageStatement)
                    Text(AskStyleMatchPrivacyDisclosure.processorStatement)
                    Text(AskStyleMatchPrivacyDisclosure.revocationStatement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(isSending ? "Sending…" : "Send request") {
                        sendRequest()
                    }
                    .disabled(isSending || question.isEmpty || question.count > AskStyleMatchRequest.maximumQuestionCharacters)
                    .accessibilityHint("Sends only the selected, consented request context through the authenticated Ask KigoStylist service.")

                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(status)
                    }
                    if !response.isEmpty {
                        Text(response)
                            .font(.body)
                            .accessibilityLabel("Ask KigoStylist response")
                    }
                } footer: {
                    Text("Only the selected request-scoped context is sent. Scan images, private messages, and credentials are never included.")
                }
            }
            .navigationTitle("Ask KigoStylist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func sendRequest() {
        var scopes = selectedScopes
        switch mode {
        case .fashionStylist:
            // The current entry point has no independently selected completed
            // scan facts yet. Do not claim or construct them from UI text.
            if includeScanSummary {
                status = "Select a completed scan before including scan context."
                return
            }
        case .appSupport, .writingAssist:
            break
        }

        let request = AskStyleMatchRequest(
            modeSelection: .manual(mode),
            question: question,
            localeIdentifier: Locale.current.identifier,
            grantedScopes: scopes,
            selectedWritingText: mode == .writingAssist ? selectedWritingText : nil
        )

        do {
            _ = try AskStyleMatchIntelligenceCore.providerDescriptor(for: request)
            response = ""
            status = "Sending securely…"
            isSending = true
            Task {
                defer { isSending = false }
                do {
                    for try await token in AskStyleMatchV2Transport().send(request) {
                        response += token
                    }
                    status = "Response complete."
                } catch AskStyleMatchV2TransportError.consentRequired {
                    status = "Current AI processing consent is required before sending."
                } catch AskStyleMatchV2TransportError.unauthorized {
                    status = "Sign in again to send this request."
                } catch AskStyleMatchV2TransportError.idempotencyConflict {
                    status = "This request changed. Send it again as a new request."
                } catch {
                    status = "Ask KigoStylist is unavailable. Your request was not saved locally."
                }
            }
        } catch AskStyleMatchValidationError.missingSelectedWritingText {
            status = "Add the text you want Writing Assist to use."
        } catch {
            status = "Check the question and selected context, then try again."
        }
    }

    private var selectedScopes: Set<AskStyleMatchScope> {
        switch mode {
        case .fashionStylist:
            var scopes: Set<AskStyleMatchScope> = []
            if includeProfilePreferences { scopes.insert(.profilePreferences) }
            if includeClosetSummary { scopes.insert(.closetSummary) }
            if includeWeatherOccasion { scopes.insert(.weatherOccasion) }
            if includeBudgetBrand { scopes.insert(.budgetBrand) }
            if includeScanSummary { scopes.insert(.scanSummary) }
            return scopes
        case .appSupport:
            return [.basicAccountStatus]
        case .writingAssist:
            return [.selectedWritingText]
        }
    }
}
