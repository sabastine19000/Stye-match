import SwiftUI

struct PromptDetailView: View {
    let version: RoadmapVersion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(version.version)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(version.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(version.goal)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                section(title: "Features", items: version.features)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Manus Prompt")
                        .font(.headline)

                    Text(version.prompt)
                        .font(.body)
                        .lineSpacing(4)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                section(title: "Acceptance Tests", items: version.acceptanceTests)
            }
            .padding()
        }
        .navigationTitle(version.version)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                    Text(item)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
