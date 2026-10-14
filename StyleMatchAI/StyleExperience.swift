import Foundation

enum StylistResponseStyle: String, CaseIterable, Identifiable {
    case brief = "Brief", detailed = "Detailed", direct = "Direct"
    var id: String { rawValue }
    func request(_ question: String) -> String {
        let format: String
        switch self {
        case .brief: format = "Keep it brief: what works, one useful improvement, then a next step."
        case .detailed: format = "Explain what works, one useful improvement and why, then a next step."
        case .direct: format = "Be direct and respectful: what works, the most useful change, then a next step."
        }
        return question + "\n\n" + format + " Use only supplied facts. If evidence is missing, say so. Evaluate clothing, not the person's body. Do not invent or change a Style Score."
    }
}

/// Reuses existing Closet and scoring authority; never invents ownership.
enum StyleExperienceAuthority {
    static func alternatives(items: [ClosetItem], primary: DailyStyleRecommendation, temperature: Int?, condition: String?, occasion: String, dressCode: String, workSetting: String) -> [DailyStyleRecommendation] {
        var seen: Set<Set<UUID>> = [Set(primary.itemIDs)]
        var results: [DailyStyleRecommendation] = []
        for id in primary.itemIDs {
            guard let next = DailyStyleRecommendationEngine.recommend(items: items.filter { $0.id != id }, temperatureFahrenheit: temperature, condition: condition, occasion: occasion, dressCode: dressCode, workSetting: workSetting), seen.insert(Set(next.itemIDs)).inserted else { continue }
            results.append(next)
            if results.count == 2 { break }
        }
        return results
    }
    static func shareText(items: [ClosetItem]) -> String {
        // No names, sizes, notes, local IDs, location or scores.
        let pieces = items.map { [$0.color, $0.category].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ") }
        return "My KigoStylist look\n" + pieces.joined(separator: " · ")
    }
    static func purchaseCheck(category: String, colors: [String], closet: [ClosetItem]) -> String {
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !category.isEmpty, !closet.isEmpty else { return "Add your clothes to Closet before checking for similar pieces. Missing records do not mean you need to buy this." }
        let similar = closet.filter { item in
            item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == category
                && colors.contains { !$0.isEmpty && $0.caseInsensitiveCompare(item.color) == .orderedSame }
        }
        guard !similar.isEmpty else { return "No exact category-and-color match in your saved Closet. Check fit, fabric and what you already own before buying; this is not proof of a wardrobe gap." }
        return "Consider skipping this purchase: your Closet has \(similar.count) piece\(similar.count == 1 ? "" : "s") with the same category and color. Compare fit and fabric before deciding."
    }
    static func wearHistory(existing: Data, itemIDs: [UUID], currentItems: [ClosetItem], now: Date) throws -> Data {
        var history = existing.isEmpty ? [:] : try JSONDecoder().decode([String: Date].self, from: existing)
        guard !itemIDs.isEmpty, Set(itemIDs).isSubset(of: Set(currentItems.map(\.id))) else { throw ExperienceError.changedOutfit }
        for id in Set(itemIDs) { history[id.uuidString] = now }
        return try JSONEncoder().encode(history)
    }
    enum ExperienceError: Error { case changedOutfit }
}

#if canImport(UIKit)
import SwiftUI
import UserNotifications

@MainActor
final class DailyStyleReminder: ObservableObject {
    static let identifier = "kigostylist.daily-style-brief.v1"
    static let openNotification = Notification.Name("kigostylist.open-daily-brief")
    @Published var status = "Reminders are optional and use your chosen local time."
    @Published var busy = false
    func schedule(at date: Date) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                status = "Notifications are off. You can enable them in iPhone Settings."
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Your daily style check"
            content.body = "Review today's outfit and make it your own."
            content.sound = .default
            content.userInfo = ["kigoRoute": "dailyStyleBrief"]
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            status = "Reminder saved for \(date.formatted(date: .omitted, time: .shortened)). Opens your current Daily Style Brief."
        } catch { status = "Could not save the reminder. Try again." }
    }
    func remove() {
        guard !busy else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        status = "Daily Style Brief reminder is off."
    }
}

struct StyleExperienceControls: View {
    @State private var showMemory = false
    @State private var showReminder = false
    @StateObject private var memory = AIPersistentMemoryStore()
    @StateObject private var reminder = DailyStyleReminder()
    @State private var reminderTime = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make it yours").font(.headline)
            Text("You choose what your stylist remembers and when you hear from us.").font(.subheadline).foregroundStyle(.secondary)
            Button { showMemory = true } label: { Label("Review & edit style memory", systemImage: "brain") }.frame(minHeight: 44)
            Button { showReminder = true } label: { Label("Set my daily reminder", systemImage: "bell") }.frame(minHeight: 44)
        }
        .padding().appCard(.home)
        .sheet(isPresented: $showMemory) { AIMemoryManagementView(store: memory) }
        .sheet(isPresented: $showReminder) {
            NavigationStack {
                Form {
                    Section("Your schedule") {
                        DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        Text("Choose a time that suits your day or night shift. No outfit, account or location details appear in this reminder.")
                        Button("Save reminder") { Task { await reminder.schedule(at: reminderTime) } }.disabled(reminder.busy)
                        Button("Turn off reminder", role: .destructive) { reminder.remove() }.disabled(reminder.busy)
                        Text(reminder.status).font(.footnote).accessibilityIdentifier("style.reminder.status")
                    }
                }
                .navigationTitle("Daily Style Brief")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showReminder = false } } }
            }
        }
    }
}

struct DailyLookActions: View {
    let recommendation: DailyStyleRecommendation
    let alternatives: [DailyStyleRecommendation]
    let items: [ClosetItem]
    let onChoose: (DailyStyleRecommendation) -> Void
    @AppStorage("closetWearHistoryData") private var wearData = Data()
    @State private var feedback: String?
    @State private var showShare = false
    private var selectedItems: [ClosetItem] { recommendation.itemIDs.compactMap { id in items.first { $0.id == id } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Why this works", systemImage: "sparkles").font(.headline)
            Text(recommendation.rationale).font(.subheadline)
            Text("Fit and comfort need your judgment. This suggestion does not predict a Style Score.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    do {
                        wearData = try StyleExperienceAuthority.wearHistory(existing: wearData, itemIDs: recommendation.itemIDs, currentItems: items, now: Date())
                        feedback = "Saved to Closet wear history."
                    } catch { feedback = "Could not save wear history. Your existing history is unchanged." }
                } label: { Label("Wore this", systemImage: "checkmark.circle") }
                .frame(minHeight: 44)
                Spacer()
                Button { showShare = true } label: { Label("Share look", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
            }
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, option in
                Button {
                    onChoose(option)
                    feedback = nil
                } label: {
                    VStack(alignment: .leading) {
                        Text("Try alternative \(index + 1)").fontWeight(.semibold)
                        Text(option.itemIDs.compactMap { id in items.first { $0.id == id }.map { ClosetItemDisplay.displayName(for: $0) } }.joined(separator: " · ")).font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            if alternatives.isEmpty { Text("No distinct complete alternative in your saved Closet yet.").font(.caption).foregroundStyle(.secondary) }
            if let feedback { Text(feedback).font(.footnote).accessibilityIdentifier("style.wear.status") }
        }
        .padding().appCard(.home)
        .sheet(isPresented: $showShare) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Review your shared look").font(.title2.bold())
                    Text(StyleExperienceAuthority.shareText(items: selectedItems))
                    Text("Only garment categories and colors are included. Your name, sizes, notes and scores stay private.").font(.footnote)
                    ShareLink(item: StyleExperienceAuthority.shareText(items: selectedItems)) { Label("Share", systemImage: "square.and.arrow.up") }
                    Spacer()
                }.padding().navigationTitle("Share look")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showShare = false } } }
            }
        }
    }
}
#endif
