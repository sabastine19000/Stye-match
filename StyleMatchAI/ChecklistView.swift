import SwiftUI

struct ChecklistView: View {
    private let items = [
        "App launches successfully.",
        "No broken screens.",
        "No console errors from new code.",
        "Navigation works.",
        "Loading states work.",
        "Error states work.",
        "Empty states work.",
        "Data persists if the feature requires persistence.",
        "Feature works for a new user with no data.",
        "Feature works for a returning user with saved data.",
        "Privacy-sensitive data is handled carefully.",
        "New code does not duplicate existing screens or services."
    ]

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square")
                        .foregroundStyle(.secondary)
                    Text(item)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Checklist")
        }
    }
}
