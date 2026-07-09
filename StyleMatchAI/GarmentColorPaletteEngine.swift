import Foundation

struct GarmentPalettePixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let x: Double
    let y: Double
    let isInsidePersonMask: Bool
    let isLikelySkinZone: Bool

    init(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        x: Double = 0.5,
        y: Double = 0.5,
        isInsidePersonMask: Bool = true,
        isLikelySkinZone: Bool = false
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.x = x
        self.y = y
        self.isInsidePersonMask = isInsidePersonMask
        self.isLikelySkinZone = isLikelySkinZone
    }
}

struct GarmentPaletteDebugSnapshot {
    let totalSamples: Int
    let personSamples: Int
    let skinReferenceSamples: Int
    let garmentSamples: Int
    let clusters: [(name: String, count: Int, share: Double)]
    let finalPalette: [String]

    var debugDescription: String {
        let clusterText = clusters
            .map { "\($0.name)=\(String(format: "%.1f", $0.share * 100))%" }
            .joined(separator: ", ")
        return "samples total=\(totalSamples), person=\(personSamples), skinRef=\(skinReferenceSamples), garment=\(garmentSamples), clusters=[\(clusterText)], final=\(finalPalette.joined(separator: ", "))"
    }
}

enum GarmentMaskTier: String, Codable, CaseIterable {
    case foregroundSubject
    case personSegmentation
    case saliencyCrop
    case couldNotIsolateGarment

    var maskingApplied: Bool {
        switch self {
        case .foregroundSubject, .personSegmentation, .saliencyCrop:
            return true
        case .couldNotIsolateGarment:
            return false
        }
    }
}

struct GarmentRegionMask: Equatable {
    let width: Int
    let height: Int
    let included: [Bool]
    let tier: GarmentMaskTier

    init(width: Int, height: Int, included: [Bool], tier: GarmentMaskTier) {
        self.width = max(1, width)
        self.height = max(1, height)
        let requiredCount = max(1, self.width * self.height)
        if included.count == requiredCount {
            self.included = included
        } else {
            self.included = Array(included.prefix(requiredCount)) + Array(repeating: false, count: max(0, requiredCount - included.count))
        }
        self.tier = tier
    }

    static func couldNotIsolate(width: Int, height: Int) -> GarmentRegionMask {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        return GarmentRegionMask(
            width: safeWidth,
            height: safeHeight,
            included: Array(repeating: false, count: safeWidth * safeHeight),
            tier: .couldNotIsolateGarment
        )
    }

    var includedCount: Int {
        included.filter { $0 }.count
    }

    var maskingApplied: Bool {
        tier.maskingApplied
    }

    func contains(x: Int, y: Int) -> Bool {
        let boundedX = min(width - 1, max(0, x))
        let boundedY = min(height - 1, max(0, y))
        return included[boundedY * width + boundedX]
    }

    func eroded(radius: Int) -> GarmentRegionMask {
        guard radius > 0, maskingApplied else {
            return self
        }

        var eroded = Array(repeating: false, count: included.count)
        for y in 0..<height {
            for x in 0..<width where contains(x: x, y: y) {
                var keep = true
                for dy in -radius...radius where keep {
                    for dx in -radius...radius {
                        if !contains(x: x + dx, y: y + dy) {
                            keep = false
                            break
                        }
                    }
                }
                eroded[y * width + x] = keep
            }
        }

        return GarmentRegionMask(width: width, height: height, included: eroded, tier: tier)
    }
}

enum GarmentRegionMasker {
    typealias MaskAttempt = () throws -> GarmentRegionMask?

    static let minimumMaskedPixelCount = 36

    static func tieredMask(
        width: Int,
        height: Int,
        minimumIncludedPixels: Int = minimumMaskedPixelCount,
        foregroundSubject: @escaping MaskAttempt,
        personSegmentation: @escaping MaskAttempt,
        saliencyCrop: @escaping MaskAttempt
    ) -> GarmentRegionMask {
        let attempts: [(GarmentMaskTier, MaskAttempt)] = [
            (.foregroundSubject, foregroundSubject),
            (.personSegmentation, personSegmentation),
            (.saliencyCrop, saliencyCrop)
        ]

        for (tier, attempt) in attempts {
            do {
                if let mask = try attempt(),
                   mask.includedCount >= minimumIncludedPixels {
                    #if DEBUG
                    print("[StyleMatch Color Debug] maskTier=\(tier.rawValue) succeeded with \(mask.includedCount) included pixels.")
                    #endif
                    return mask
                }
            } catch {
                #if DEBUG
                print("[StyleMatch Color Debug] maskTier=\(tier.rawValue) failed: \(error.localizedDescription)")
                #endif
                continue
            }
        }

        #if DEBUG
        print("[StyleMatch Color Debug] all garment mask tiers failed; returning couldNotIsolateGarment.")
        #endif
        return GarmentRegionMask.couldNotIsolate(width: width, height: height)
    }
}

enum GarmentColorPaletteEngine {
    static let minimumGarmentPixelCount = 42

    static func extractPalette(
        from samples: [GarmentPalettePixel],
        minimumGarmentPixels: Int = minimumGarmentPixelCount
    ) -> (palette: [String], confidence: Int, debug: GarmentPaletteDebugSnapshot) {
        let personSamples = samples.filter(\.isInsidePersonMask)
        let skinReference = coherentSkinReference(from: personSamples.filter(\.isLikelySkinZone))

        let garmentSamples = personSamples.filter { sample in
            guard let reference = skinReference else {
                return true
            }
            return normalizedDistance(sample, reference) > reference.threshold
        }

        guard garmentSamples.count >= minimumGarmentPixels else {
            let debug = GarmentPaletteDebugSnapshot(
                totalSamples: samples.count,
                personSamples: personSamples.count,
                skinReferenceSamples: skinReference?.count ?? 0,
                garmentSamples: garmentSamples.count,
                clusters: [],
                finalPalette: ["neutral"]
            )
            return (["neutral"], 30, debug)
        }

        let colorNames = garmentSamples.compactMap(everydayGarmentColorName)
        let counts = Dictionary(grouping: colorNames, by: { $0 }).mapValues(\.count)
        let total = max(1, colorNames.count)
        let clusters = counts
            .filter { entry in
                entry.key != "background" && Double(entry.value) / Double(total) >= 0.06
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { (name: $0.key, count: $0.value, share: Double($0.value) / Double(total)) }

        let palette = validatedGarmentColors(clusters.map(\.name))
        let leadingShare = clusters.first?.share ?? 0
        let confidence = min(96, max(48, Int((leadingShare * 100).rounded()) + 32))
        let debug = GarmentPaletteDebugSnapshot(
            totalSamples: samples.count,
            personSamples: personSamples.count,
            skinReferenceSamples: skinReference?.count ?? 0,
            garmentSamples: garmentSamples.count,
            clusters: clusters,
            finalPalette: palette
        )
        return (palette, confidence, debug)
    }

    static func validatedGarmentColors(_ colors: [String]) -> [String] {
        let validColors = [
            "black", "white", "gray", "grey", "navy", "blue", "red", "green",
            "brown", "tan", "beige", "olive", "khaki", "maroon", "burgundy",
            "orange", "yellow", "purple", "pink", "cream", "charcoal", "denim"
        ]
        let filtered = colors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { color in
                validColors.contains { valid in color.contains(valid) }
            }
            .removingDuplicates()

        return filtered.isEmpty ? ["neutral"] : filtered
    }

    static func everydayGarmentColorName(for sample: GarmentPalettePixel) -> String? {
        let red = Int(sample.red)
        let green = Int(sample.green)
        let blue = Int(sample.blue)
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let spread = maxValue - minValue
        let brightness = (red + green + blue) / 3

        if brightness < 28 { return "black" }
        if brightness < 62 && spread < 28 { return "charcoal" }
        if brightness > 222 && spread < 34 { return "white" }
        if spread < 20 {
            if brightness < 80 { return "black" }
            if brightness < 118 { return "charcoal" }
            if brightness > 190 { return "white" }
            return "gray"
        }

        if blue > red + 22 && blue > green + 12 {
            return brightness < 88 ? "navy" : "blue"
        }

        if green > red + 12 && green > blue + 8 {
            if red > 70 && blue < 105 && brightness < 150 { return "olive" }
            return "green"
        }

        if red > green + 24 && red > blue + 24 {
            if red > 165 && green > 112 && blue < 85 { return "orange" }
            if red > 165 && green > 78 && blue > 100 { return "pink" }
            if brightness < 95 && blue > 48 { return "maroon" }
            if brightness < 100 { return "burgundy" }
            return "red"
        }

        if red > green && green > blue {
            if brightness < 92 { return "brown" }
            if red > 184 && green > 152 && blue > 112 { return "beige" }
            if red > 180 && green > 150 && blue < 112 { return "khaki" }
            if red > 190 && green > 168 && blue < 105 { return "yellow" }
            if red > 142 && green > 100 && blue < 105 { return "tan" }
            return "brown"
        }

        if red > 120 && blue > 100 && green < 120 {
            return "purple"
        }

        return nil
    }

    private struct SkinReference {
        let red: Double
        let green: Double
        let blue: Double
        let threshold: Double
        let count: Int
    }

    private static func coherentSkinReference(from samples: [GarmentPalettePixel]) -> SkinReference? {
        guard samples.count >= 6 else { return nil }

        let red = samples.map { Double($0.red) }.reduce(0, +) / Double(samples.count)
        let green = samples.map { Double($0.green) }.reduce(0, +) / Double(samples.count)
        let blue = samples.map { Double($0.blue) }.reduce(0, +) / Double(samples.count)

        let distances = samples.map { normalizedDistance($0, SkinReference(red: red, green: green, blue: blue, threshold: 0, count: samples.count)) }
        let meanDistance = distances.reduce(0, +) / Double(max(1, distances.count))
        guard meanDistance < 0.24 else { return nil }

        return SkinReference(
            red: red,
            green: green,
            blue: blue,
            threshold: max(0.16, min(0.28, meanDistance * 2.15)),
            count: samples.count
        )
    }

    private static func normalizedDistance(_ sample: GarmentPalettePixel, _ reference: SkinReference) -> Double {
        let red = Double(sample.red) / 255.0
        let green = Double(sample.green) / 255.0
        let blue = Double(sample.blue) / 255.0
        let refRed = reference.red / 255.0
        let refGreen = reference.green / 255.0
        let refBlue = reference.blue / 255.0
        return sqrt(pow(red - refRed, 2) + pow(green - refGreen, 2) + pow(blue - refBlue, 2))
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
