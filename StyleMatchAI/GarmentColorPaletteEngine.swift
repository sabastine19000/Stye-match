import Foundation

#if DEBUG
enum StyleMatchDebugLogEmitter {
    private static let queue = DispatchQueue(label: "com.stylematch.debug-log-emitter")

    static func emit(_ message: @autoclosure () -> String) {
        queue.sync {
            print(message())
            fflush(stdout)
        }
    }
}
#endif

enum GarmentPaletteTimedStage {
    case illuminant
    case naming
    case confidence
}

final class GarmentPaletteStageTiming {
    private let lock = NSLock()
    private var illuminantSeconds = 0.0
    private var namingSeconds = 0.0
    private var confidenceSeconds = 0.0

    func add(_ elapsed: Double, to stage: GarmentPaletteTimedStage) {
        #if DEBUG
        lock.lock()
        switch stage {
        case .illuminant:
            illuminantSeconds += elapsed
        case .naming:
            namingSeconds += elapsed
        case .confidence:
            confidenceSeconds += elapsed
        }
        lock.unlock()
        #endif
    }

    func milliseconds(for stage: GarmentPaletteTimedStage) -> Double {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let seconds: Double
        switch stage {
        case .illuminant:
            seconds = illuminantSeconds
        case .naming:
            seconds = namingSeconds
        case .confidence:
            seconds = confidenceSeconds
        }
        return seconds * 1_000
        #else
        return 0
        #endif
    }
}

enum GarmentRegionGeometry {
    static func subdividedBoxes(
        of box: CGRect,
        imageSize: CGSize,
        oversizedAreaThreshold: CGFloat = 0.60
    ) -> [CGRect] {
        guard box.width * box.height > oversizedAreaThreshold else { return [] }

        let pixelWidth = box.width * imageSize.width
        let pixelHeight = box.height * imageSize.height
        if pixelWidth >= pixelHeight {
            let halfWidth = box.width / 2
            return [
                CGRect(x: box.minX, y: box.minY, width: halfWidth, height: box.height),
                CGRect(x: box.minX + halfWidth, y: box.minY, width: halfWidth, height: box.height)
            ]
        }

        let halfHeight = box.height / 2
        return [
            CGRect(x: box.minX, y: box.minY, width: box.width, height: halfHeight),
            CGRect(x: box.minX, y: box.minY + halfHeight, width: box.width, height: halfHeight)
        ]
    }
}

enum FashionColorCatalog {
    struct Anchor: Equatable {
        let name: String
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    static let anchors: [Anchor] = [
        Anchor(name: "white", red: 248, green: 248, blue: 246),
        Anchor(name: "ivory", red: 245, green: 240, blue: 220),
        Anchor(name: "cream", red: 238, green: 225, blue: 190),
        Anchor(name: "beige", red: 218, green: 200, blue: 170),
        Anchor(name: "sand", red: 194, green: 178, blue: 140),
        Anchor(name: "tan", red: 190, green: 155, blue: 110),
        Anchor(name: "camel", red: 166, green: 123, blue: 82),
        Anchor(name: "brown", red: 112, green: 72, blue: 45),
        Anchor(name: "chocolate", red: 67, green: 40, blue: 28),
        Anchor(name: "taupe", red: 140, green: 126, blue: 112),
        Anchor(name: "gray", red: 150, green: 150, blue: 150),
        Anchor(name: "charcoal", red: 54, green: 57, blue: 63),
        Anchor(name: "black", red: 14, green: 14, blue: 16),
        Anchor(name: "navy", red: 25, green: 42, blue: 78),
        Anchor(name: "royal blue", red: 45, green: 78, blue: 180),
        Anchor(name: "blue", red: 55, green: 120, blue: 200),
        Anchor(name: "light blue", red: 172, green: 208, blue: 226),
        Anchor(name: "sky blue", red: 112, green: 185, blue: 225),
        Anchor(name: "denim", red: 72, green: 104, blue: 145),
        Anchor(name: "teal", red: 35, green: 125, blue: 132),
        Anchor(name: "turquoise", red: 62, green: 190, blue: 185),
        Anchor(name: "mint", red: 172, green: 222, blue: 195),
        Anchor(name: "green", red: 50, green: 145, blue: 75),
        Anchor(name: "forest green", red: 35, green: 82, blue: 50),
        Anchor(name: "olive", red: 115, green: 112, blue: 55),
        Anchor(name: "lime", red: 145, green: 190, blue: 65),
        Anchor(name: "yellow", red: 235, green: 205, blue: 55),
        Anchor(name: "mustard", red: 190, green: 145, blue: 40),
        Anchor(name: "gold", red: 205, green: 165, blue: 55),
        Anchor(name: "orange", red: 225, green: 120, blue: 45),
        Anchor(name: "rust", red: 170, green: 72, blue: 42),
        Anchor(name: "coral", red: 225, green: 112, blue: 95),
        Anchor(name: "red", red: 205, green: 45, blue: 50),
        Anchor(name: "burgundy", red: 105, green: 32, blue: 48),
        Anchor(name: "maroon", red: 82, green: 32, blue: 42),
        Anchor(name: "pink", red: 225, green: 125, blue: 165),
        Anchor(name: "blush", red: 225, green: 184, blue: 190),
        Anchor(name: "magenta", red: 190, green: 55, blue: 145),
        Anchor(name: "purple", red: 112, green: 65, blue: 150),
        Anchor(name: "lavender", red: 188, green: 168, blue: 215)
    ]

    struct NameContribution: Equatable {
        let name: String
        let weight: Double
    }

    struct FamilyContribution: Equatable {
        let family: String
        let weight: Double
    }

    struct NamingEvaluation: Equatable {
        let contributions: [NameContribution]
        let calibrationDecision: String?
    }

    private struct RankedAnchor {
        let anchor: Anchor
        let distance: Double
        let hueDistance: Double
    }

    private static let neutralAnchorNames: Set<String> = [
        "white", "ivory", "cream", "gray", "charcoal", "black"
    ]
    private static let chromaticNearTieMargin = 0.08

    static func nearestName(red: UInt8, green: UInt8, blue: UInt8) -> String {
        nameContributions(red: red, green: green, blue: blue, hasSpatialEvidence: false)
            .max { $0.weight < $1.weight }?.name ?? "black"
    }

    static func nameContributions(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        hasSpatialEvidence: Bool,
        allowsHueTieBreak: Bool = true,
        preferredChromaticFamily: String? = nil,
        corroboratedChromaticFamilies: Set<String> = [],
        enforcesLightNeutralEvidence: Bool = false,
        preCorrectionSaturation: Double? = nil
    ) -> [NameContribution] {
        namingEvaluation(
            red: red,
            green: green,
            blue: blue,
            hasSpatialEvidence: hasSpatialEvidence,
            allowsHueTieBreak: allowsHueTieBreak,
            preferredChromaticFamily: preferredChromaticFamily,
            corroboratedChromaticFamilies: corroboratedChromaticFamilies,
            enforcesLightNeutralEvidence: enforcesLightNeutralEvidence,
            preCorrectionSaturation: preCorrectionSaturation
        ).contributions
    }

    static func namingEvaluation(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        hasSpatialEvidence: Bool,
        allowsHueTieBreak: Bool = true,
        preferredChromaticFamily: String? = nil,
        corroboratedChromaticFamilies: Set<String> = [],
        enforcesLightNeutralEvidence: Bool = false,
        preCorrectionSaturation: Double? = nil
    ) -> NamingEvaluation {
        let sample = hsl(red: red, green: green, blue: blue)
        let ranked = rankedChromaticAnchors(to: sample)
        let calibrationDecision = calibrationDecision(
            red: red,
            green: green,
            blue: blue,
            sample: sample,
            ranked: ranked,
            allowsHueTieBreak: allowsHueTieBreak,
            preferredChromaticFamily: preferredChromaticFamily
        )

        let contributions: [NameContribution]

        if preCorrectionSaturation.map({ $0 < 0.08 }) == true {
            contributions = [NameContribution(name: nearestNeutralName(to: sample), weight: 1)]
        } else if isUnsupportedBrightWarmTint(sample, hasSpatialEvidence: hasSpatialEvidence) {
            contributions = [NameContribution(name: sample.lightness >= 0.90 ? "white" : "ivory", weight: 1)]
        } else if hasCoherentDarkChromaticSignal(red: red, green: green, blue: blue, sample: sample) {
            contributions = [
                NameContribution(name: nearestChromaticName(
                    to: sample,
                    allowsHueTieBreak: allowsHueTieBreak,
                    preferredFamily: preferredChromaticFamily,
                    ranked: ranked
                ), weight: 0.65),
                NameContribution(name: nearestNeutralName(to: sample), weight: 0.35)
            ]
        } else if sample.saturation <= 0.08 {
            contributions = [NameContribution(name: nearestNeutralName(to: sample), weight: 1)]
        } else if sample.saturation < 0.16 {
            let chromaticName = nearestChromaticName(
                to: sample,
                allowsHueTieBreak: allowsHueTieBreak,
                preferredFamily: preferredChromaticFamily,
                ranked: ranked
            )
            let chromaticFamily = FashionColorFamilyCatalog.family(for: chromaticName)
            if enforcesLightNeutralEvidence,
               sample.lightness >= 0.62,
               !hasSpatialEvidence,
               !corroboratedChromaticFamilies.contains(chromaticFamily) {
                contributions = [NameContribution(name: nearestNeutralName(to: sample), weight: 1)]
            } else {
                let chromaticWeight = (sample.saturation - 0.08) / 0.08
                contributions = [
                    NameContribution(name: nearestNeutralName(to: sample), weight: 1 - chromaticWeight),
                    NameContribution(name: chromaticName, weight: chromaticWeight)
                ].filter { $0.weight > 0 }
            }
        } else {
            contributions = [NameContribution(name: nearestChromaticName(
                to: sample,
                allowsHueTieBreak: allowsHueTieBreak,
                preferredFamily: preferredChromaticFamily,
                ranked: ranked
            ), weight: 1)]
        }

        return NamingEvaluation(
            contributions: contributions,
            calibrationDecision: calibrationDecision
        )
    }

    static func familyContributions(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        hasSpatialEvidence: Bool,
        allowsHueTieBreak: Bool = true,
        preferredChromaticFamily: String? = nil,
        corroboratedChromaticFamilies: Set<String> = [],
        enforcesLightNeutralEvidence: Bool = false,
        preCorrectionSaturation: Double? = nil
    ) -> [FamilyContribution] {
        let sample = hsl(red: red, green: green, blue: blue)
        let ranked = rankedChromaticAnchors(to: sample)

        if preCorrectionSaturation.map({ $0 < 0.08 }) == true {
            return [FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestNeutralName(to: sample)), weight: 1)]
        }

        if isUnsupportedBrightWarmTint(sample, hasSpatialEvidence: hasSpatialEvidence) {
            return [FamilyContribution(family: "white", weight: 1)]
        }

        if hasCoherentDarkChromaticSignal(red: red, green: green, blue: blue, sample: sample) {
            return [
                FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestChromaticName(
                    to: sample,
                    allowsHueTieBreak: allowsHueTieBreak,
                    preferredFamily: preferredChromaticFamily,
                    ranked: ranked
                )), weight: 0.65),
                FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestNeutralName(to: sample)), weight: 0.35)
            ]
        }

        if sample.saturation <= 0.08 {
            return [FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestNeutralName(to: sample)), weight: 1)]
        }

        if sample.saturation < 0.16 {
            let chromaticName = nearestChromaticName(
                to: sample,
                allowsHueTieBreak: allowsHueTieBreak,
                preferredFamily: preferredChromaticFamily,
                ranked: ranked
            )
            let chromaticFamily = FashionColorFamilyCatalog.family(for: chromaticName)
            if enforcesLightNeutralEvidence,
               sample.lightness >= 0.62,
               !hasSpatialEvidence,
               !corroboratedChromaticFamilies.contains(chromaticFamily) {
                return [FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestNeutralName(to: sample)), weight: 1)]
            }

            let chromaticWeight = (sample.saturation - 0.08) / 0.08
            return [
                FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestNeutralName(to: sample)), weight: 1 - chromaticWeight),
                FamilyContribution(family: chromaticFamily, weight: chromaticWeight)
            ].filter { $0.weight > 0 }
        }

        return [FamilyContribution(family: FashionColorFamilyCatalog.family(for: nearestChromaticName(
            to: sample,
            allowsHueTieBreak: allowsHueTieBreak,
            preferredFamily: preferredChromaticFamily,
            ranked: ranked
        )), weight: 1)]
    }

    private static func nearestNeutralName(to sample: HSL) -> String {
        anchors.filter { neutralAnchorNames.contains($0.name) }.min {
            neutralDistance(from: sample, to: $0) < neutralDistance(from: sample, to: $1)
        }?.name ?? "gray"
    }

    private static func nearestChromaticName(
        to sample: HSL,
        allowsHueTieBreak: Bool = true,
        preferredFamily: String? = nil,
        ranked: [RankedAnchor]? = nil
    ) -> String {
        let ranked = ranked ?? rankedChromaticAnchors(to: sample)
        guard let best = ranked.first else { return "black" }
        let nearTies = ranked.filter { $0.distance - best.distance <= chromaticNearTieMargin }
        if !allowsHueTieBreak,
           let preferredFamily,
           let preferred = nearTies
            .filter({ FashionColorFamilyCatalog.family(for: $0.anchor.name) == preferredFamily })
            .min(by: { $0.distance < $1.distance }) {
            return preferred.anchor.name
        }
        return nearTies.min { lhs, rhs in
            if lhs.hueDistance == rhs.hueDistance { return lhs.distance < rhs.distance }
            return lhs.hueDistance < rhs.hueDistance
        }?.anchor.name ?? best.anchor.name
    }

    private static func rankedChromaticAnchors(to sample: HSL) -> [RankedAnchor] {
        anchors
            .filter { !neutralAnchorNames.contains($0.name) }
            .map { anchor in
                RankedAnchor(
                    anchor: anchor,
                    distance: chromaticDistance(from: sample, to: anchor),
                    hueDistance: hueDistance(from: sample, to: anchor)
                )
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance { return lhs.anchor.name < rhs.anchor.name }
                return lhs.distance < rhs.distance
            }
    }

    static func calibrationDecision(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        allowsHueTieBreak: Bool = true,
        preferredChromaticFamily: String? = nil
    ) -> String? {
        let sample = hsl(red: red, green: green, blue: blue)
        return calibrationDecision(
            red: red,
            green: green,
            blue: blue,
            sample: sample,
            ranked: rankedChromaticAnchors(to: sample),
            allowsHueTieBreak: allowsHueTieBreak,
            preferredChromaticFamily: preferredChromaticFamily
        )
    }

    private static func calibrationDecision(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        sample: HSL,
        ranked: [RankedAnchor],
        allowsHueTieBreak: Bool,
        preferredChromaticFamily: String?
    ) -> String? {
        if hasCoherentDarkChromaticSignal(red: red, green: green, blue: blue, sample: sample) {
            return "darkChromaticPreference=\(nearestChromaticName(to: sample, ranked: ranked))"
        }
        guard ranked.count >= 2, ranked[1].distance - ranked[0].distance <= chromaticNearTieMargin else { return nil }
        let candidates = ranked.filter { $0.distance - ranked[0].distance <= chromaticNearTieMargin }
        if !allowsHueTieBreak,
           let preferredChromaticFamily,
           let preferred = candidates
            .filter({ FashionColorFamilyCatalog.family(for: $0.anchor.name) == preferredChromaticFamily })
            .min(by: { $0.distance < $1.distance }) {
            return "hueTieBreakSuppressed=\(preferred.anchor.name)"
        }
        let winner = candidates.min { $0.hueDistance < $1.hueDistance }?.anchor.name ?? ranked[0].anchor.name
        return "hueTieBreak=\(winner)"
    }

    private static func neutralDistance(from sample: HSL, to anchor: Anchor) -> Double {
        let target = hsl(red: anchor.red, green: anchor.green, blue: anchor.blue)
        let saturationDelta = abs(sample.saturation - target.saturation)
        let lightnessDelta = abs(sample.lightness - target.lightness)
        return lightnessDelta * 6 + saturationDelta * 1.5
    }

    private static func chromaticDistance(from sample: HSL, to anchor: Anchor) -> Double {
        let target = hsl(red: anchor.red, green: anchor.green, blue: anchor.blue)
        let hueDelta = hueDistance(from: sample, to: anchor)
        let saturationDelta = abs(sample.saturation - target.saturation)
        let lightnessDelta = abs(sample.lightness - target.lightness)
        return hueDelta * 5 + saturationDelta * 1.25 + lightnessDelta * 1.75
    }

    private static func hueDistance(from sample: HSL, to anchor: Anchor) -> Double {
        let target = hsl(red: anchor.red, green: anchor.green, blue: anchor.blue)
        return min(abs(sample.hue - target.hue), 1 - abs(sample.hue - target.hue))
    }

    private static func hasCoherentDarkChromaticSignal(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        sample: HSL
    ) -> Bool {
        let channelSpread = Int(max(red, green, blue)) - Int(min(red, green, blue))
        return sample.lightness <= 0.36 &&
            sample.saturation >= 0.07 &&
            sample.saturation < 0.20 &&
            channelSpread >= 8
    }

    private static func isUnsupportedBrightWarmTint(_ sample: HSL, hasSpatialEvidence: Bool) -> Bool {
        guard !hasSpatialEvidence,
              sample.lightness >= 0.72,
              sample.saturation >= 0.08,
              sample.saturation <= 0.45 else { return false }
        return sample.hue <= 0.10 || sample.hue >= 0.92
    }

    private struct HSL {
        let hue: Double
        let saturation: Double
        let lightness: Double
    }

    private static func hsl(red: UInt8, green: UInt8, blue: UInt8) -> HSL {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = (((blue - red) / delta) + 2) / 6
        } else {
            hue = (((red - green) / delta) + 4) / 6
        }

        return HSL(hue: hue < 0 ? hue + 1 : hue, saturation: saturation, lightness: lightness)
    }

    static func saturation(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        hsl(red: red, green: green, blue: blue).saturation
    }

    static func chromaticFamily(red: UInt8, green: UInt8, blue: UInt8) -> String {
        FashionColorFamilyCatalog.family(for: nearestChromaticName(
            to: hsl(red: red, green: green, blue: blue),
            allowsHueTieBreak: false
        ))
    }
}

enum SleepwearPrimaryPaletteSignal {
    static func score(for palette: [String]) -> Int {
        let normalized = palette.map { $0.lowercased() }
        let hasPinkOrRed = normalized.contains(where: { $0.contains("pink") || $0.contains("red") })
        let hasLightSleepwearColor = normalized.contains(where: {
            ["cream", "white", "pastel"].contains($0) ||
                $0.contains("cream") ||
                $0.contains("white") ||
                $0.contains("pastel")
        })
        var score = 0
        if hasPinkOrRed { score += 2 }
        if hasLightSleepwearColor { score += 1 }
        if hasPinkOrRed && hasLightSleepwearColor { score += 2 }
        return score
    }
}

struct GarmentPalettePixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let x: Double
    let y: Double
    let isInsidePersonMask: Bool
    let isLikelySkinZone: Bool
    let isStrongForegroundEvidence: Bool

    init(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        x: Double = 0.5,
        y: Double = 0.5,
        isInsidePersonMask: Bool = true,
        isLikelySkinZone: Bool = false,
        isStrongForegroundEvidence: Bool = false
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.x = x
        self.y = y
        self.isInsidePersonMask = isInsidePersonMask
        self.isLikelySkinZone = isLikelySkinZone
        self.isStrongForegroundEvidence = isStrongForegroundEvidence
    }
}

struct GarmentPaletteDebugSnapshot {
    let totalSamples: Int
    let personSamples: Int
    let skinReferenceSamples: Int
    let garmentSamples: Int
    let clusters: [(name: String, count: Int, share: Double)]
    let familyShares: [(name: String, share: Double)]
    let finalPalette: [String]
    let whiteBalanceGains: (red: Double, green: Double, blue: Double)
    let illuminantReference: String
    let namingCalibrationDecisions: [String]
    let backgroundReferences: [(name: String, share: Double)]
    let downWeightedSamples: Int
    let clusterWeightDecisions: [(name: String, foregroundConcentration: Double, downWeighted: Bool)]
    let leadershipDecision: String
    let confidenceReason: String

    var debugDescription: String {
        let clusterText = clusters
            .map { "\($0.name)=\(String(format: "%.1f", $0.share * 100))%" }
            .joined(separator: ", ")
        let gains = "r=\(String(format: "%.2f", whiteBalanceGains.red)), g=\(String(format: "%.2f", whiteBalanceGains.green)), b=\(String(format: "%.2f", whiteBalanceGains.blue))"
        let familyText = familyShares
            .map { "\($0.name)=\(String(format: "%.1f", $0.share * 100))%" }
            .joined(separator: ", ")
        let backgroundText = backgroundReferences
            .map { "\($0.name)=\(String(format: "%.1f", $0.share * 100))%" }
            .joined(separator: ", ")
        let decisionText = clusterWeightDecisions
            .map {
                "\($0.name):foregroundConcentration=\(String(format: "%.2f", $0.foregroundConcentration)):downWeighted=\($0.downWeighted)"
            }
            .joined(separator: ", ")
        return "samples total=\(totalSamples), person=\(personSamples), skinRef=\(skinReferenceSamples), garment=\(garmentSamples), whiteBalance=[\(gains)], illuminantReference=\(illuminantReference), namingCalibration=\(namingCalibrationDecisions), clusters=[\(clusterText)], familyShares=[\(familyText)], backgroundRefs=[\(backgroundText)], downWeighted=\(downWeightedSamples), clusterDecisions=[\(decisionText)], leadershipDecision=\(leadershipDecision), confidenceReason=\(confidenceReason), final=\(finalPalette.joined(separator: ", "))"
    }
}

enum FashionColorFamilyCatalog {
    private static let families: [String: Set<String>] = [
        "white": ["white", "ivory", "cream"],
        "brown": ["beige", "sand", "tan", "camel", "brown", "chocolate", "taupe", "khaki"],
        "neutral": ["gray", "grey", "charcoal", "black"],
        "blue": ["navy", "royal blue", "blue", "light blue", "sky blue", "denim", "teal", "turquoise", "aqua"],
        "green": ["green", "forest green", "olive", "lime", "mint"],
        "yellow": ["yellow", "mustard", "gold"],
        "orange": ["orange", "rust", "coral"],
        "red": ["red", "burgundy", "maroon"],
        "pink": ["pink", "blush", "magenta"],
        "purple": ["purple", "lavender"]
    ]

    static func family(for colorName: String) -> String {
        let normalized = colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return families.first(where: { $0.value.contains(normalized) })?.key ?? normalized
    }

    static func aggregatedCounts(_ colorCounts: [String: Int]) -> [String: (count: Int, representative: String)] {
        Dictionary(grouping: colorCounts.keys, by: family(for:)).mapValues { names in
            let representative = names.max { lhs, rhs in
                let left = colorCounts[lhs] ?? 0
                let right = colorCounts[rhs] ?? 0
                return left == right ? lhs > rhs : left < right
            } ?? names[0]
            return (names.reduce(0) { $0 + (colorCounts[$1] ?? 0) }, representative)
        }
    }

    static func aggregatedWeights(_ colorWeights: [String: Double]) -> [String: (weight: Double, representative: String)] {
        Dictionary(grouping: colorWeights.keys, by: family(for:)).mapValues { names in
            let representative = names.max { lhs, rhs in
                let left = colorWeights[lhs] ?? 0
                let right = colorWeights[rhs] ?? 0
                return left == right ? lhs > rhs : left < right
            } ?? names[0]
            return (names.reduce(0) { $0 + (colorWeights[$1] ?? 0) }, representative)
        }
    }
}

enum GarmentCropContributionBalancer {
    static func balance(_ crops: [[GarmentPalettePixel]]) -> (samples: [GarmentPalettePixel], rawSampleCount: Int) {
        let garmentCrops = crops.map { $0.filter(\.isInsidePersonMask) }.filter { !$0.isEmpty }
        let rawSampleCount = garmentCrops.reduce(0) { $0 + $1.count }
        guard let targetCount = garmentCrops.map(\.count).min(), targetCount > 0 else {
            return ([], rawSampleCount)
        }
        return (garmentCrops.flatMap { evenlySample($0, count: targetCount) }, rawSampleCount)
    }

    private static func evenlySample(_ samples: [GarmentPalettePixel], count: Int) -> [GarmentPalettePixel] {
        guard count < samples.count else { return samples }
        guard count > 1 else { return [samples[samples.count / 2]] }
        let step = Double(samples.count - 1) / Double(count - 1)
        return (0..<count).map { samples[Int((Double($0) * step).rounded())] }
    }
}

struct GarmentPaletteSampleCandidate {
    let samples: [GarmentPalettePixel]
    let tier: GarmentMaskTier
    let source: GarmentPaletteSource
    let maskingApplied: Bool
    let garmentSampleCount: Int
    let familyShares: [String: Double]

    init(
        samples: [GarmentPalettePixel],
        tier: GarmentMaskTier,
        source: GarmentPaletteSource,
        maskingApplied: Bool,
        garmentSampleCount: Int,
        familyShares: [String: Double] = [:]
    ) {
        self.samples = samples
        self.tier = tier
        self.source = source
        self.maskingApplied = maskingApplied
        self.garmentSampleCount = garmentSampleCount
        self.familyShares = familyShares
    }
}

enum GarmentPaletteSourceSelector {
    static let minimumReliableGarmentSamples = 500

    struct RankedCandidate {
        let candidate: GarmentPaletteSampleCandidate
        let score: Double
        let agreement: Double
    }

    struct Selection {
        let candidate: GarmentPaletteSampleCandidate?
        let metQualityBar: Bool
        let rankedCandidates: [RankedCandidate]
        let disagreement: Bool

        var winnerIsCorroborated: Bool {
            (rankedCandidates.first?.agreement ?? 0) > 0
        }

        var winnerIsStrongStandalone: Bool {
            guard let winner = rankedCandidates.first else { return false }
            return winner.candidate.garmentSampleCount >= 1_500 && winner.score >= 0.80
        }

        var hasConfidenceEvidence: Bool {
            metQualityBar && !disagreement && (winnerIsCorroborated || winnerIsStrongStandalone)
        }

        var corroboratedFamilies: Set<String> {
            guard let winner = rankedCandidates.first else { return [] }
            let winnerFamilies = GarmentPaletteSourceSelector.credibleFamilies(winner.candidate)
            return rankedCandidates.dropFirst().reduce(into: Set<String>()) { result, peer in
                result.formUnion(winnerFamilies.intersection(GarmentPaletteSourceSelector.credibleFamilies(peer.candidate)))
            }
        }

        var confidenceReason: String {
            if disagreement { return "credible sources disagree" }
            if !metQualityBar { return "no source cleared 500 effective garment samples" }
            if winnerIsCorroborated { return "winning families corroborated by another source" }
            if winnerIsStrongStandalone { return "strong standalone source (samples>=1500, score>=0.80)" }
            return "winner lacked corroboration and strong standalone evidence"
        }
    }

    static func select(
        _ candidates: [GarmentPaletteSampleCandidate],
        minimumReliableSamples: Int = minimumReliableGarmentSamples
    ) -> Selection {
        let qualified = candidates.filter { $0.garmentSampleCount >= minimumReliableSamples }
        guard !qualified.isEmpty else {
            return Selection(
                candidate: candidates.max { $0.garmentSampleCount < $1.garmentSampleCount },
                metQualityBar: false,
                rankedCandidates: [],
                disagreement: false
            )
        }

        let maximumSamples = Double(qualified.map(\.garmentSampleCount).max() ?? 1)
        let ranked = qualified.map { candidate -> RankedCandidate in
            let agreement = averageAgreement(for: candidate, among: qualified)
            let sampleScore = Double(candidate.garmentSampleCount) / maximumSamples
            let reliabilityScore = Double(candidate.source.reliability) / 3.0
            let score = sampleScore * 0.55 + reliabilityScore * 0.25 + agreement * 0.20
            return RankedCandidate(candidate: candidate, score: score, agreement: agreement)
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.candidate.garmentSampleCount > rhs.candidate.garmentSampleCount
            }
            return lhs.score > rhs.score
        }

        return Selection(
            candidate: ranked.first?.candidate,
            metQualityBar: true,
            rankedCandidates: ranked,
            disagreement: containsDisagreement(qualified)
        )
    }

    private static func credibleFamilies(_ candidate: GarmentPaletteSampleCandidate) -> Set<String> {
        credibleFamilies(from: candidate.familyShares)
    }

    static func credibleFamilies(from familyShares: [String: Double]) -> Set<String> {
        Set(familyShares.filter { $0.value >= GarmentColorPaletteEngine.minimumRetainedClusterShare }.map(\.key))
    }

    private static func averageAgreement(
        for candidate: GarmentPaletteSampleCandidate,
        among candidates: [GarmentPaletteSampleCandidate]
    ) -> Double {
        let candidateFamilies = credibleFamilies(candidate)
        let peers = candidates.filter { $0.source != candidate.source || $0.tier != candidate.tier }
        guard !candidateFamilies.isEmpty, !peers.isEmpty else { return 0 }
        let scores = peers.map { peer -> Double in
            let peerFamilies = credibleFamilies(peer)
            let union = candidateFamilies.union(peerFamilies)
            guard !union.isEmpty else { return 0 }
            return Double(candidateFamilies.intersection(peerFamilies).count) / Double(union.count)
        }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private static func containsDisagreement(_ candidates: [GarmentPaletteSampleCandidate]) -> Bool {
        for leftIndex in candidates.indices {
            let left = credibleFamilies(candidates[leftIndex])
            guard !left.isEmpty else { continue }
            for rightIndex in candidates.indices where rightIndex > leftIndex {
                let right = credibleFamilies(candidates[rightIndex])
                if !right.isEmpty && left.isDisjoint(with: right) {
                    return true
                }
            }
        }
        return false
    }
}

enum GarmentPaletteConfidence: String, Codable, Equatable {
    case confident
    case low
}

enum GarmentPaletteSource: String, Codable, Equatable {
    case garmentCrop
    case foregroundSubject
    case personSegmentation
    case saliencyCrop
    case unavailable

    var reliability: Int {
        switch self {
        case .garmentCrop: return 3
        case .personSegmentation, .foregroundSubject: return 2
        case .saliencyCrop: return 1
        case .unavailable: return 0
        }
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

    func adaptivelyErodedStrongMask(
        preferredRadius: Int = 3,
        minimumRetainedFraction: Double = 0.08
    ) -> GarmentRegionMask? {
        guard maskingApplied, includedCount > 0 else { return nil }
        let coverageFloor = max(
            GarmentColorPaletteEngine.minimumGarmentPixelCount,
            Int((Double(includedCount) * minimumRetainedFraction).rounded(.up))
        )
        for radius in stride(from: max(0, preferredRadius), through: 0, by: -1) {
            let candidate = radius == 0 ? self : eroded(radius: radius)
            if candidate.includedCount >= coverageFloor {
                return candidate
            }
        }
        return nil
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
                    StyleMatchDebugLogEmitter.emit("[StyleMatch Color Debug] maskTier=\(tier.rawValue) succeeded with \(mask.includedCount) included pixels.")
                    #endif
                    return mask
                }
            } catch {
                #if DEBUG
                StyleMatchDebugLogEmitter.emit("[StyleMatch Color Debug] maskTier=\(tier.rawValue) failed: \(error.localizedDescription)")
                #endif
                continue
            }
        }

        #if DEBUG
        StyleMatchDebugLogEmitter.emit("[StyleMatch Color Debug] all garment mask tiers failed; returning couldNotIsolateGarment.")
        #endif
        return GarmentRegionMask.couldNotIsolate(width: width, height: height)
    }
}

enum GarmentColorPaletteEngine {
    static let minimumGarmentPixelCount = 42
    static let minimumRetainedClusterShare = 0.15

    private struct WeightedColorSummary {
        let colorWeights: [String: Double]
        let effectiveSampleCount: Double
        let downWeightedSamples: Int
        let clusterWeightDecisions: [(name: String, foregroundConcentration: Double, downWeighted: Bool)]
        let familyForegroundConcentrations: [String: Double]
        let namingCalibrationDecisions: [String]
    }

    final class CandidateFamilyMemo {
        fileprivate var cachedContributions: [UInt32: [FashionColorCatalog.FamilyContribution]] = [:]
        private(set) var evaluationCount = 0

        fileprivate func contributions(
            red: UInt8,
            green: UInt8,
            blue: UInt8,
            originalRed: UInt8,
            originalGreen: UInt8,
            originalBlue: UInt8,
            hasSpatialEvidence: Bool,
            allowsHueTieBreak: Bool
        ) -> [FashionColorCatalog.FamilyContribution] {
            let preCorrectionSaturation = FashionColorCatalog.saturation(
                red: originalRed,
                green: originalGreen,
                blue: originalBlue
            )
            let key = GarmentColorPaletteEngine.memoizedFamilyKey(
                red: red,
                green: green,
                blue: blue,
                wasPreCorrectionNeutral: preCorrectionSaturation < 0.08
            )
            if let cached = cachedContributions[key] {
                return cached
            }

            let preferredChromaticFamily = FashionColorCatalog.chromaticFamily(
                red: originalRed,
                green: originalGreen,
                blue: originalBlue
            )
            let evaluated = FashionColorCatalog.familyContributions(
                red: red,
                green: green,
                blue: blue,
                hasSpatialEvidence: hasSpatialEvidence,
                allowsHueTieBreak: allowsHueTieBreak,
                preferredChromaticFamily: preferredChromaticFamily,
                preCorrectionSaturation: preCorrectionSaturation
            )
            cachedContributions[key] = evaluated
            evaluationCount += 1
            return evaluated
        }
    }

    static func extractPalette(
        from samples: [GarmentPalettePixel],
        minimumGarmentPixels: Int = minimumGarmentPixelCount,
        source: GarmentPaletteSource = .foregroundSubject,
        allowsSkinExclusion: Bool = true,
        forceLowConfidence: Bool = false,
        confidenceSampleCount: Int? = nil,
        backgroundFamilyShares: [String: Double] = [:],
        illuminantReferenceSamples: [GarmentPalettePixel] = [],
        confidenceEvidenceSatisfied: Bool = false,
        corroboratedFamilies: Set<String> = [],
        confidenceReason: String = "legacy source confidence rule",
        debugTiming: GarmentPaletteStageTiming? = nil
    ) -> (palette: [String], confidence: Int, confidenceLevel: GarmentPaletteConfidence, debug: GarmentPaletteDebugSnapshot) {
        let personSamples = samples.filter(\.isInsidePersonMask)
        let skinReference = allowsSkinExclusion
            ? coherentSkinReference(from: personSamples.filter(\.isLikelySkinZone))
            : nil

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
                familyShares: [],
                finalPalette: ["neutral"],
                whiteBalanceGains: (1, 1, 1),
                illuminantReference: "unavailable",
                namingCalibrationDecisions: [],
                backgroundReferences: backgroundFamilyShares.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
                downWeightedSamples: 0,
                clusterWeightDecisions: [],
                leadershipDecision: "no garment samples available for leadership",
                confidenceReason: "insufficient garment samples"
            )
            return (["neutral"], 30, .low, debug)
        }

        #if DEBUG
        let illuminantStart = ProcessInfo.processInfo.systemUptime
        #endif
        let correction = illuminantAwareCorrection(
            for: garmentSamples,
            brightReferenceSamples: illuminantReferenceSamples
        )
        #if DEBUG
        debugTiming?.add(ProcessInfo.processInfo.systemUptime - illuminantStart, to: .illuminant)
        let namingStart = ProcessInfo.processInfo.systemUptime
        #endif
        let correctedSamples = garmentSamples.map { correction.correct($0) }
        let weightedSummary = weightedColorSummary(
            correctedSamples,
            originalSamples: garmentSamples,
            source: source,
            backgroundFamilyShares: backgroundFamilyShares,
            illuminantIsCredible: correction.usesCredibleIlluminant,
            corroboratedFamilies: corroboratedFamilies,
            enforcesLightNeutralEvidence: true
        )
        let total = max(1, weightedSummary.effectiveSampleCount)
        let familyCounts = FashionColorFamilyCatalog.aggregatedWeights(
            weightedSummary.colorWeights.filter { $0.key != "background" }
        )
        let rawSortedFamilies = familyCounts.sorted { lhs, rhs in
            if lhs.value.weight == rhs.value.weight {
                return lhs.key < rhs.key
            }
            return lhs.value.weight > rhs.value.weight
        }
        #if DEBUG
        debugTiming?.add(ProcessInfo.processInfo.systemUptime - namingStart, to: .naming)
        #endif
        let hasLeadershipEvidence: (String) -> Bool = { family in
            family == "neutral" || family == "white" ||
                source == .garmentCrop ||
                (weightedSummary.familyForegroundConcentrations[family] ?? 0) > 0 ||
                corroboratedFamilies.contains(family)
        }
        let supportedFamilies = rawSortedFamilies.filter { hasLeadershipEvidence($0.key) }
        let unsupportedFamilies = rawSortedFamilies.filter { !hasLeadershipEvidence($0.key) }
        let sortedFamilies = supportedFamilies + unsupportedFamilies
        let rawLeader = rawSortedFamilies.first?.key
        let finalLeader = sortedFamilies.first?.key
        let leadershipEvidenceSatisfied = finalLeader.map(hasLeadershipEvidence) ?? false
        let leadershipDecision: String
        if let rawLeader, rawLeader != finalLeader {
            leadershipDecision = "demoted unsupported family \(rawLeader); leader=\(finalLeader ?? "none")"
        } else if let finalLeader {
            leadershipDecision = leadershipEvidenceSatisfied
                ? "leader=\(finalLeader) supported by foreground/crop/corroboration evidence"
                : "leader=\(finalLeader) lacks positive evidence; palette held low confidence"
        } else {
            leadershipDecision = "no retained family leader"
        }
        let familyShares = sortedFamilies.map { family, entry in
            (name: family, share: entry.weight / total)
        }
        let clusters: [(name: String, count: Int, share: Double)] = sortedFamilies.enumerated().compactMap { index, entry in
            let share = entry.value.weight / total
            let mayUseLeaderException = index == 0 && hasLeadershipEvidence(entry.key)
            guard mayUseLeaderException || share >= minimumRetainedClusterShare else { return nil }
            return (name: entry.value.representative, count: Int(entry.value.weight.rounded()), share: share)
        }

        let palette = validatedGarmentColors(clusters.map(\.name))
        let leadingShare = clusters.first?.share ?? 0
        let confidence = min(96, max(48, Int((leadingShare * 100).rounded()) + 32))
        let rawSampleCount = confidenceSampleCount ?? garmentSamples.count
        let hasEnoughSamples = rawSampleCount >= minimumGarmentPixels * 2
            && weightedSummary.effectiveSampleCount >= Double(GarmentPaletteSourceSelector.minimumReliableGarmentSamples)
        let sourceEvidenceIsCredible = confidenceEvidenceSatisfied || source.reliability >= 2
        #if DEBUG
        let confidenceStart = ProcessInfo.processInfo.systemUptime
        #endif
        let confidenceLevel: GarmentPaletteConfidence = !forceLowConfidence && sourceEvidenceIsCredible && leadershipEvidenceSatisfied && hasEnoughSamples && leadingShare >= 0.18
            ? .confident
            : .low
        #if DEBUG
        debugTiming?.add(ProcessInfo.processInfo.systemUptime - confidenceStart, to: .confidence)
        #endif
        let debug = GarmentPaletteDebugSnapshot(
            totalSamples: samples.count,
            personSamples: personSamples.count,
            skinReferenceSamples: skinReference?.count ?? 0,
            garmentSamples: garmentSamples.count,
            clusters: clusters,
            familyShares: familyShares,
            finalPalette: palette,
            whiteBalanceGains: (correction.redGain, correction.greenGain, correction.blueGain),
            illuminantReference: correction.reason,
            namingCalibrationDecisions: weightedSummary.namingCalibrationDecisions,
            backgroundReferences: backgroundFamilyShares.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
            downWeightedSamples: weightedSummary.downWeightedSamples,
            clusterWeightDecisions: weightedSummary.clusterWeightDecisions,
            leadershipDecision: leadershipDecision,
            confidenceReason: confidenceLevel == .confident ? confidenceReason : lowConfidenceReason(
                forced: forceLowConfidence,
                hasEnoughSamples: hasEnoughSamples,
                sourceEvidenceIsCredible: sourceEvidenceIsCredible,
                leadingShare: leadingShare,
                requestedReason: confidenceReason
            )
        )
        return (palette, confidence, confidenceLevel, debug)
    }

    static func garmentSampleCount(
        in samples: [GarmentPalettePixel],
        allowsSkinExclusion: Bool
    ) -> Int {
        let personSamples = samples.filter(\.isInsidePersonMask)
        guard allowsSkinExclusion,
              let skinReference = coherentSkinReference(from: personSamples.filter(\.isLikelySkinZone)) else {
            return personSamples.count
        }
        return personSamples.filter { normalizedDistance($0, skinReference) > skinReference.threshold }.count
    }

    static func colorFamilyShares(
        in samples: [GarmentPalettePixel],
        allowsSkinExclusion: Bool,
        source: GarmentPaletteSource = .foregroundSubject,
        backgroundFamilyShares: [String: Double] = [:],
        illuminantReferenceSamples: [GarmentPalettePixel] = [],
        debugTiming: GarmentPaletteStageTiming? = nil
    ) -> [String: Double] {
        let personSamples = samples.filter(\.isInsidePersonMask)
        let skinReference = allowsSkinExclusion
            ? coherentSkinReference(from: personSamples.filter(\.isLikelySkinZone))
            : nil
        let garmentSamples = personSamples.filter { sample in
            guard let skinReference else { return true }
            return normalizedDistance(sample, skinReference) > skinReference.threshold
        }
        guard !garmentSamples.isEmpty else { return [:] }

        #if DEBUG
        let illuminantStart = ProcessInfo.processInfo.systemUptime
        #endif
        let correction = illuminantAwareCorrection(
            for: garmentSamples,
            brightReferenceSamples: illuminantReferenceSamples
        )
        #if DEBUG
        debugTiming?.add(ProcessInfo.processInfo.systemUptime - illuminantStart, to: .illuminant)
        let namingStart = ProcessInfo.processInfo.systemUptime
        #endif
        let weightedSummary = weightedColorSummary(
            garmentSamples.map { correction.correct($0) },
            originalSamples: garmentSamples,
            source: source,
            backgroundFamilyShares: backgroundFamilyShares,
            illuminantIsCredible: correction.usesCredibleIlluminant
        )
        let familyCounts = FashionColorFamilyCatalog.aggregatedWeights(weightedSummary.colorWeights)
        let total = max(1, weightedSummary.effectiveSampleCount)
        let shares = familyCounts.mapValues { $0.weight / total }
        #if DEBUG
        debugTiming?.add(ProcessInfo.processInfo.systemUptime - namingStart, to: .naming)
        #endif
        return shares
    }

    static func fastCandidateFamilyShares(
        in samples: [GarmentPalettePixel],
        allowsSkinExclusion: Bool,
        backgroundFamilyShares: [String: Double] = [:],
        illuminantReferenceSamples: [GarmentPalettePixel] = [],
        memo: CandidateFamilyMemo? = nil
    ) -> [String: Double] {
        let personSamples = samples.filter(\.isInsidePersonMask)
        let skinReference = allowsSkinExclusion
            ? coherentSkinReference(from: personSamples.filter(\.isLikelySkinZone))
            : nil
        let garmentSamples = personSamples.filter { sample in
            guard let skinReference else { return true }
            return normalizedDistance(sample, skinReference) > skinReference.threshold
        }
        guard !garmentSamples.isEmpty else { return [:] }

        let correction = illuminantAwareCorrection(
            for: garmentSamples,
            brightReferenceSamples: illuminantReferenceSamples
        )
        let memo = memo ?? CandidateFamilyMemo()
        var familyTotals: [String: Double] = [:]
        var familyForegroundTotals: [String: Double] = [:]

        for sample in garmentSamples {
            let corrected = correction.correct(sample)
            let contributions = memo.contributions(
                red: corrected.red,
                green: corrected.green,
                blue: corrected.blue,
                originalRed: sample.red,
                originalGreen: sample.green,
                originalBlue: sample.blue,
                hasSpatialEvidence: sample.isStrongForegroundEvidence,
                allowsHueTieBreak: correction.usesCredibleIlluminant
            )
            for contribution in contributions {
                familyTotals[contribution.family, default: 0] += contribution.weight
                if sample.isStrongForegroundEvidence {
                    familyForegroundTotals[contribution.family, default: 0] += contribution.weight
                }
            }
        }

        var effectiveTotals: [String: Double] = [:]
        for (family, total) in familyTotals {
            let foregroundConcentration = familyForegroundTotals[family, default: 0] / max(0.0001, total)
            let backgroundShare = backgroundFamilyShares[family] ?? 0
            let shouldDownWeight = backgroundShare >= 0.18 && foregroundConcentration < 0.35
            effectiveTotals[family] = total * (shouldDownWeight ? 0.25 : 1.0)
        }

        let effectiveSampleCount = max(1, effectiveTotals.values.reduce(0, +))
        return effectiveTotals.mapValues { $0 / effectiveSampleCount }
    }

    static func fastCandidateFamily(red: UInt8, green: UInt8, blue: UInt8) -> String {
        let contributions = FashionColorCatalog.familyContributions(
            red: red,
            green: green,
            blue: blue,
            hasSpatialEvidence: false,
            preCorrectionSaturation: FashionColorCatalog.saturation(red: red, green: green, blue: blue)
        )
        let totals = contributions.reduce(into: [String: Double]()) { result, contribution in
            result[contribution.family, default: 0] += contribution.weight
        }
        return totals.max {
            if $0.value == $1.value { return $0.key > $1.key }
            return $0.value < $1.value
        }?.key ?? "neutral"
    }

    static func backgroundFamilyShares(from samples: [GarmentPalettePixel]) -> [String: Double] {
        let border = samples.filter { sample in
            sample.x <= 0.10 || sample.x >= 0.90 || sample.y <= 0.10 || sample.y >= 0.90
        }
        guard !border.isEmpty else { return [:] }
        var nameWeights: [String: Double] = [:]
        for sample in border {
            for contribution in FashionColorCatalog.nameContributions(
                red: sample.red,
                green: sample.green,
                blue: sample.blue,
                hasSpatialEvidence: false
            ) {
                nameWeights[contribution.name, default: 0] += contribution.weight
            }
        }
        let familyWeights = FashionColorFamilyCatalog.aggregatedWeights(nameWeights)
        let total = max(0.0001, familyWeights.values.reduce(0) { $0 + $1.weight })
        return familyWeights.mapValues { $0.weight / total }
    }

    private static func memoizedFamilyKey(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        wasPreCorrectionNeutral: Bool
    ) -> UInt32 {
        let redBin = UInt32(red >> 2)
        let greenBin = UInt32(green >> 2)
        let blueBin = UInt32(blue >> 2)
        let neutralBit = wasPreCorrectionNeutral ? UInt32(1) : UInt32(0)
        return (neutralBit << 18) | (redBin << 12) | (greenBin << 6) | blueBin
    }

    private static func weightedColorSummary(
        _ samples: [GarmentPalettePixel],
        originalSamples: [GarmentPalettePixel]? = nil,
        source: GarmentPaletteSource,
        backgroundFamilyShares: [String: Double],
        illuminantIsCredible: Bool = true,
        corroboratedFamilies: Set<String> = [],
        enforcesLightNeutralEvidence: Bool = false
    ) -> WeightedColorSummary {
        let originals = originalSamples?.count == samples.count ? originalSamples! : samples
        let namingEvaluations = samples.enumerated().map { index, sample in
            let original = originals[index]
            let preferredFamily = FashionColorCatalog.chromaticFamily(
                red: original.red,
                green: original.green,
                blue: original.blue
            )
            let evaluation = FashionColorCatalog.namingEvaluation(
                red: sample.red,
                green: sample.green,
                blue: sample.blue,
                hasSpatialEvidence: sample.isStrongForegroundEvidence,
                allowsHueTieBreak: illuminantIsCredible,
                preferredChromaticFamily: preferredFamily,
                corroboratedChromaticFamilies: corroboratedFamilies,
                enforcesLightNeutralEvidence: enforcesLightNeutralEvidence,
                preCorrectionSaturation: FashionColorCatalog.saturation(
                    red: original.red,
                    green: original.green,
                    blue: original.blue
                )
            )
            return (sample: sample, evaluation: evaluation)
        }
        let named = namingEvaluations.flatMap { item in
            item.evaluation.contributions.map {
                (sample: item.sample, name: $0.name, contribution: $0.weight)
            }
        }
        let namingCalibrationDecisions = Array(Set(namingEvaluations.compactMap {
            $0.evaluation.calibrationDecision
        })).sorted()
        let namedGroups = Dictionary(grouping: named, by: { $0.name })
        let foregroundConcentrations = namedGroups.mapValues { entries in
            let total = entries.reduce(0) { $0 + $1.contribution }
            let foreground = entries.filter { $0.sample.isStrongForegroundEvidence }.reduce(0) { $0 + $1.contribution }
            return foreground / max(0.0001, total)
        }
        let downWeightedNames = Set(namedGroups.compactMap { name, entries -> String? in
            let family = FashionColorFamilyCatalog.family(for: name)
            let backgroundShare = backgroundFamilyShares[family] ?? 0
            let foregroundConcentration = foregroundConcentrations[name] ?? 0
            return backgroundShare >= 0.18 && foregroundConcentration < 0.35 ? name : nil
        })
        var weights: [String: Double] = [:]
        var downWeighted = 0

        for entry in named {
            let shouldDownWeight = downWeightedNames.contains(entry.name)
            let weight = entry.contribution * (shouldDownWeight ? 0.25 : 1.0)
            weights[entry.name, default: 0] += weight
            if shouldDownWeight { downWeighted += Int(entry.contribution.rounded(.up)) }
        }

        let clusterWeightDecisions = namedGroups.keys.sorted().map { name in
            (
                name: name,
                foregroundConcentration: foregroundConcentrations[name] ?? 0,
                downWeighted: downWeightedNames.contains(name)
            )
        }

        var familyTotals: [String: Double] = [:]
        var familyForegroundTotals: [String: Double] = [:]
        for entry in named {
            let family = FashionColorFamilyCatalog.family(for: entry.name)
            familyTotals[family, default: 0] += entry.contribution
            if entry.sample.isStrongForegroundEvidence {
                familyForegroundTotals[family, default: 0] += entry.contribution
            }
        }

        return WeightedColorSummary(
            colorWeights: weights,
            effectiveSampleCount: weights.values.reduce(0, +),
            downWeightedSamples: downWeighted,
            clusterWeightDecisions: clusterWeightDecisions,
            familyForegroundConcentrations: Dictionary(uniqueKeysWithValues: familyTotals.map { family, total in
                (family, familyForegroundTotals[family, default: 0] / max(0.0001, total))
            }),
            namingCalibrationDecisions: namingCalibrationDecisions
        )
    }

    private static func lowConfidenceReason(
        forced: Bool,
        hasEnoughSamples: Bool,
        sourceEvidenceIsCredible: Bool,
        leadingShare: Double,
        requestedReason: String
    ) -> String {
        if forced { return requestedReason }
        if !hasEnoughSamples { return "background down-weighting left fewer than 500 effective samples" }
        if !sourceEvidenceIsCredible { return requestedReason }
        if leadingShare < 0.18 { return "no dominant color family" }
        return requestedReason
    }

    private struct GrayWorldCorrection {
        let redGain: Double
        let greenGain: Double
        let blueGain: Double
        let reason: String
        let usesCredibleIlluminant: Bool

        func correct(_ sample: GarmentPalettePixel) -> GarmentPalettePixel {
            GarmentPalettePixel(
                red: UInt8(clamping: Int((Double(sample.red) * redGain).rounded())),
                green: UInt8(clamping: Int((Double(sample.green) * greenGain).rounded())),
                blue: UInt8(clamping: Int((Double(sample.blue) * blueGain).rounded())),
                x: sample.x,
                y: sample.y,
                isInsidePersonMask: sample.isInsidePersonMask,
                isLikelySkinZone: sample.isLikelySkinZone,
                isStrongForegroundEvidence: sample.isStrongForegroundEvidence
            )
        }
    }

    private static func grayWorldCorrection(for samples: [GarmentPalettePixel]) -> GrayWorldCorrection {
        guard !samples.isEmpty else {
            return GrayWorldCorrection(
                redGain: 1,
                greenGain: 1,
                blueGain: 1,
                reason: "bright-region rejected reason=no garment samples; fallback=none",
                usesCredibleIlluminant: false
            )
        }
        let count = Double(samples.count)
        let redMean = samples.reduce(0.0) { $0 + Double($1.red) } / count
        let greenMean = samples.reduce(0.0) { $0 + Double($1.green) } / count
        let blueMean = samples.reduce(0.0) { $0 + Double($1.blue) } / count
        let target = (redMean + greenMean + blueMean) / 3.0
        let meanSpread = max(redMean, greenMean, blueMean) - min(redMean, greenMean, blueMean)
        // Gray-world is reliable for lighting casts, but full correction would erase a
        // genuinely tinted majority garment. Preserve most chroma when the sample mean
        // itself has a clear hue.
        let correctionStrength = meanSpread >= 12 ? 0.25 : 1.0
        func gain(for mean: Double) -> Double {
            guard mean > 0 else { return 1 }
            let fullGain = min(1.6, max(0.6, target / mean))
            return 1 + (fullGain - 1) * correctionStrength
        }
        return GrayWorldCorrection(
            redGain: gain(for: redMean),
            greenGain: gain(for: greenMean),
            blueGain: gain(for: blueMean),
            reason: "garment-gray-world strength=\(String(format: "%.2f", correctionStrength))",
            usesCredibleIlluminant: false
        )
    }

    private enum BorderRegion: String, CaseIterable {
        case top, right, bottom, left
    }

    private static func borderRegion(for sample: GarmentPalettePixel) -> BorderRegion {
        let distances: [(BorderRegion, Double)] = [
            (.top, sample.y),
            (.right, 1 - sample.x),
            (.bottom, 1 - sample.y),
            (.left, sample.x)
        ]
        return distances.min { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 < rhs.1
        }?.0 ?? .top
    }

    private static func credibleIlluminantSamples(
        from samples: [GarmentPalettePixel]
    ) -> (samples: [GarmentPalettePixel], accepted: Bool, reason: String) {
        let bright = samples.filter { sample in
            let red = Double(sample.red)
            let green = Double(sample.green)
            let blue = Double(sample.blue)
            let mean = (red + green + blue) / 3
            let spread = max(red, green, blue) - min(red, green, blue)
            return mean >= 160 && spread / max(1, max(red, green, blue)) <= 0.35
        }
        guard bright.count >= 24 else {
            return ([], false, "fewer than 24 bright border samples")
        }

        let grouped = Dictionary(grouping: bright, by: borderRegion(for:))
        let supportedRegions = grouped.filter { $0.value.count >= 6 }
        guard supportedRegions.count >= 2 else {
            return ([], false, "neutral evidence appears in fewer than 2 border regions")
        }

        let regionChromaticities = supportedRegions.map { region, regionSamples -> (BorderRegion, [Double]) in
            let count = Double(regionSamples.count)
            let red = regionSamples.reduce(0.0) { $0 + Double($1.red) } / count
            let green = regionSamples.reduce(0.0) { $0 + Double($1.green) } / count
            let blue = regionSamples.reduce(0.0) { $0 + Double($1.blue) } / count
            let total = max(1, red + green + blue)
            return (region, [red / total, green / total, blue / total])
        }
        var maximumRegionDelta = 0.0
        for leftIndex in regionChromaticities.indices {
            for rightIndex in regionChromaticities.indices where rightIndex > leftIndex {
                let delta = zip(
                    regionChromaticities[leftIndex].1,
                    regionChromaticities[rightIndex].1
                ).map { abs($0 - $1) }.max() ?? 0
                maximumRegionDelta = max(maximumRegionDelta, delta)
            }
        }
        guard maximumRegionDelta <= 0.05 else {
            return ([], false, "border regions disagree (chromaticity delta=\(String(format: "%.3f", maximumRegionDelta)))")
        }

        let corroborated = supportedRegions.values.flatMap { $0 }
        let count = Double(corroborated.count)
        let redMean = corroborated.reduce(0.0) { $0 + Double($1.red) } / count
        let greenMean = corroborated.reduce(0.0) { $0 + Double($1.green) } / count
        let blueMean = corroborated.reduce(0.0) { $0 + Double($1.blue) } / count
        let greenReferenceLimit = max(redMean, blueMean) * 1.04
        guard greenMean <= greenReferenceLimit else {
            return ([], false, "green-dominant reference is not a credible neutral")
        }

        return (
            corroborated,
            true,
            "corroborated across \(supportedRegions.count) border regions"
        )
    }

    private static func illuminantAwareCorrection(
        for garmentSamples: [GarmentPalettePixel],
        brightReferenceSamples: [GarmentPalettePixel]
    ) -> GrayWorldCorrection {
        let credibility = credibleIlluminantSamples(from: brightReferenceSamples)
        guard credibility.accepted else {
            let fallback = grayWorldCorrection(for: garmentSamples)
            return GrayWorldCorrection(
                redGain: fallback.redGain,
                greenGain: fallback.greenGain,
                blueGain: fallback.blueGain,
                reason: "bright-region rejected reason=\(credibility.reason); fallback=\(fallback.reason)",
                usesCredibleIlluminant: false
            )
        }

        let sorted = credibility.samples.sorted {
            (Int($0.red) + Int($0.green) + Int($0.blue)) >
                (Int($1.red) + Int($1.green) + Int($1.blue))
        }
        let selected = Array(sorted.prefix(max(24, sorted.count / 2)))
        let count = Double(selected.count)
        let redMean = selected.reduce(0.0) { $0 + Double($1.red) } / count
        let greenMean = selected.reduce(0.0) { $0 + Double($1.green) } / count
        let blueMean = selected.reduce(0.0) { $0 + Double($1.blue) } / count
        let target = (redMean + greenMean + blueMean) / 3
        func gain(for mean: Double) -> Double {
            guard mean > 0 else { return 1 }
            let fullGain = min(1.45, max(0.65, target / mean))
            return 1 + (fullGain - 1) * 0.90
        }
        return GrayWorldCorrection(
            redGain: gain(for: redMean),
            greenGain: gain(for: greenMean),
            blueGain: gain(for: blueMean),
            reason: "bright-region accepted reason=\(credibility.reason) count=\(selected.count) mean=\(Int(redMean))/\(Int(greenMean))/\(Int(blueMean))",
            usesCredibleIlluminant: true
        )
    }

    static func validatedGarmentColors(_ colors: [String]) -> [String] {
        let validColors = FashionColorCatalog.anchors.map(\.name) + ["grey", "khaki"]
        let filtered = colors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { color in
                validColors.contains { valid in color.contains(valid) }
            }
            .removingDuplicates()

        return filtered.isEmpty ? ["neutral"] : filtered
    }

    static func everydayGarmentColorName(for sample: GarmentPalettePixel) -> String {
        FashionColorCatalog.nameContributions(
            red: sample.red,
            green: sample.green,
            blue: sample.blue,
            hasSpatialEvidence: sample.isStrongForegroundEvidence
        ).max { $0.weight < $1.weight }?.name ?? "black"
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
