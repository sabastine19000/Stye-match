import Foundation

protocol ProductComplementaryPieceRecommending {
    func companions(for product: AffiliateProduct, catalog: [AffiliateProduct], limit: Int) -> [AffiliateProduct]
}

struct CatalogProductComplementaryPieceRecommender: ProductComplementaryPieceRecommending {
    func companions(for product: AffiliateProduct, catalog: [AffiliateProduct], limit: Int = 6) -> [AffiliateProduct] {
        let targetCategories = companionCategories(for: product)
        let productColors = Set(product.colors.map(colorFamily).filter { !$0.isEmpty })
        let ranked = catalog
            .filter { $0.id != product.id }
            .map { candidate -> (product: AffiliateProduct, score: Int) in
                var score = 0
                if targetCategories.contains(candidate.category) {
                    score += 40
                }
                if targetCategories.contains(where: { candidate.subcategory.localizedCaseInsensitiveContains($0.displayName) }) {
                    score += 20
                }
                let candidateColors = Set(candidate.colors.map(colorFamily).filter { !$0.isEmpty })
                if candidateColors.isEmpty || productColors.isEmpty {
                    score += 5
                } else if !candidateColors.isDisjoint(with: compatibleFamilies(for: productColors)) {
                    score += 20
                }
                if candidate.retailer.name == product.retailer.name {
                    score += 3
                }
                return (candidate, score)
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.product.name < rhs.product.name
                }
                return lhs.score > rhs.score
            }

        return Array(ranked.map(\.product).prefix(limit))
    }

    private func companionCategories(for product: AffiliateProduct) -> [ProductCategory] {
        switch product.category {
        case .shoes:
            return [.clothing, .accessories]
        case .accessories:
            return [.clothing, .shoes]
        case .clothing:
            let text = "\(product.subcategory) \(product.name)".lowercased()
            if text.contains("pant") || text.contains("chino") || text.contains("jean") || text.contains("trouser") {
                return [.clothing, .shoes, .accessories]
            }
            if text.contains("jacket") || text.contains("blazer") || text.contains("coat") {
                return [.clothing, .shoes, .accessories]
            }
            return [.shoes, .accessories, .clothing]
        case .electronics, .styleTools:
            return [.accessories]
        }
    }

    private func compatibleFamilies(for families: Set<String>) -> Set<String> {
        var output = Set(["black", "white", "gray", "brown", "blue"])
        if families.contains("black") { output.formUnion(["white", "gray", "brown"]) }
        if families.contains("white") { output.formUnion(["black", "blue", "gray"]) }
        if families.contains("blue") { output.formUnion(["white", "brown", "gray"]) }
        if families.contains("brown") { output.formUnion(["white", "blue", "green"]) }
        if families.contains("green") { output.formUnion(["white", "brown", "black"]) }
        return output
    }

    private func colorFamily(_ color: String) -> String {
        let value = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["black", "charcoal"].contains(value) { return "black" }
        if ["white", "cream"].contains(value) { return "white" }
        if ["gray", "grey", "silver"].contains(value) { return "gray" }
        if ["navy", "blue", "denim"].contains(value) { return "blue" }
        if ["brown", "tan", "beige", "camel"].contains(value) { return "brown" }
        if ["olive", "green"].contains(value) { return "green" }
        return value
    }
}
