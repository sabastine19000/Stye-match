import SwiftUI

@available(*, deprecated, message: "Legacy shopping surface is quarantined. Use ShoppingView for the active customer shopping experience.")
struct ShopView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Shopping moved", systemImage: "bag")
                .font(.headline)

            Text("The active shopping experience now uses ShoppingView with backend catalog routing and safe affiliate fallback handling.")
                .foregroundStyle(.secondary)

            Text(ShoppingCatalogDisclosure.fallback)
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
