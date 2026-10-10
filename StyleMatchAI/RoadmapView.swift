import SwiftUI

struct RoadmapView: View {
    var body: some View {
        NavigationStack {
            List(RoadmapData.versions) { version in
                NavigationLink {
                    PromptDetailView(version: version)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(version.version)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Text(version.title)
                            .font(.headline)

                        Text(version.goal)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Roadmap")
        }
    }
}
