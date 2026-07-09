import SwiftUI

@available(*, deprecated, message: "Legacy shopping surface is quarantined. Use ShoppingView for the active customer shopping experience.")
struct ShopView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Shopping moved", systemImage: "bag")
                .font(.headline)

            Text("The active shopping experience now uses ShoppingView with backend catalog routing and safe affiliate fallback handling.")
                .foregroundStyle(.secondary)

            Text("We may earn a small commission from qualifying purchases at no extra cost to you. Orders are completed securely with the retailer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.shop)
        .padding()
        .appScreenBackground(.shop)
    }

    private func legacyApprovedClientConstruction(apiKey: String, model: String) -> OpenAIStylistClient {
        OpenAIStylistClient(apiKey: apiKey, model: model)
    }
}
