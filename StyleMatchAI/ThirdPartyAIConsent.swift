import Foundation
import SwiftUI

enum ThirdPartyAIConsentStatus: String, Codable, Equatable {
    case unknown
    case declined
    case granted
}

struct ThirdPartyAIConsentRecord: Codable, Equatable {
    let disclosureVersion: Int
    let status: ThirdPartyAIConsentStatus
    let decidedAt: Date?
}

enum ThirdPartyAIConsentError: LocalizedError, Equatable {
    case required

    var errorDescription: String? {
        "AI Stylist is unavailable until you allow third-party AI data sharing in Profile. Scanning, saved results, Closet, and Shopping remain available."
    }
}

enum ThirdPartyAIConsentStore {
    static let disclosureVersion = 1
    static let storageKey = "thirdPartyAIConsentRecord"
    static let didChangeNotification = Notification.Name("ThirdPartyAIConsentDidChange")

    static func record(defaults: UserDefaults = .standard) -> ThirdPartyAIConsentRecord {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(ThirdPartyAIConsentRecord.self, from: data),
              stored.disclosureVersion == disclosureVersion else {
            return ThirdPartyAIConsentRecord(
                disclosureVersion: disclosureVersion,
                status: .unknown,
                decidedAt: nil
            )
        }
        return stored
    }

    static func isGranted(defaults: UserDefaults = .standard) -> Bool {
        record(defaults: defaults).status == .granted
    }

    static func setStatus(_ status: ThirdPartyAIConsentStatus, defaults: UserDefaults = .standard) {
        let record = ThirdPartyAIConsentRecord(
            disclosureVersion: disclosureVersion,
            status: status,
            decidedAt: status == .unknown ? nil : Date()
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func withdraw(defaults: UserDefaults = .standard) {
        setStatus(.declined, defaults: defaults)
    }
}

@MainActor
final class ThirdPartyAIConsentCoordinator: ObservableObject {
    static let shared = ThirdPartyAIConsentCoordinator()

    @Published var isPresentingDisclosure = false
    private var waiting: [CheckedContinuation<Bool, Never>] = []

    func authorizeExternalAIRequest() async -> Bool {
        let status = ThirdPartyAIConsentStore.record().status
        if status == .granted { return true }
        if status == .declined { return false }

        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            isPresentingDisclosure = true
        }
    }

    func allow() {
        ThirdPartyAIConsentStore.setStatus(.granted)
        finish(granted: true)
    }

    func decline() {
        ThirdPartyAIConsentStore.setStatus(.declined)
        finish(granted: false)
    }

    private func finish(granted: Bool) {
        isPresentingDisclosure = false
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume(returning: granted) }
    }
}

struct ThirdPartyAIConsentDisclosureView: View {
    @ObservedObject var coordinator: ThirdPartyAIConsentCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Use AI Stylist", systemImage: "sparkles")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("When you use AI Stylist, StyleMatch Pro sends your messages and relevant styling information—such as saved scan results, outfit details, style preferences, sizes, closet items, budget, occasion and weather context—to StyleMatch Pro’s service and OpenAI to generate your response.")

                    Label("Outfit photos are analyzed on your device and are not sent to OpenAI.", systemImage: "iphone.and.arrow.forward")
                        .font(.headline)

                    Text("This permission is optional. If you choose Not Now, AI Stylist and AI explanations will remain unavailable, but you can continue using scanning, saved results, Closet and Shopping. You can change this choice later in Profile.")

                    VStack(spacing: 12) {
                        Button("Allow and Continue") { coordinator.allow() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Allow third-party AI data sharing and continue")

                        Button("Not Now", role: .cancel) { coordinator.decline() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Do not allow third-party AI data sharing")
                    }
                    .controlSize(dynamicTypeSize.isAccessibilitySize ? .large : .regular)
                }
                .font(.body)
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .interactiveDismissDisabled()
        }
    }
}
