import SwiftUI
import WeatherKit

struct AppleWeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var lightMarkURL: URL?
    @State private var darkMarkURL: URL?
    @State private var legalPageURL: URL?

    var body: some View {
        Group {
            if let legalPageURL {
                Link(destination: legalPageURL) {
                    HStack(spacing: 8) {
                        AsyncImage(url: colorScheme == .dark ? darkMarkURL : lightMarkURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                ProgressView()
                                    .accessibilityLabel("Loading Apple Weather mark")
                            }
                        }
                        .frame(maxWidth: 118, maxHeight: 22, alignment: .leading)

                        Text("Legal attribution")
                            .font(.caption2)
                    }
                }
                .accessibilityLabel("Apple Weather legal attribution")
            } else {
                Text("Loading Apple Weather attribution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard legalPageURL == nil else { return }
            guard let attribution = try? await WeatherService.shared.attribution else { return }
            lightMarkURL = attribution.combinedMarkLightURL
            darkMarkURL = attribution.combinedMarkDarkURL
            legalPageURL = attribution.legalPageURL
        }
    }
}
