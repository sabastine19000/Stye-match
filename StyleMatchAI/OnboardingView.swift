import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("stylePreferences") private var stylePreferences = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("occasions") private var occasions = ""
    @State private var selectedPage = 0
    @State private var selectedStyles: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedOccasions: Set<String> = []

    private let slides = [
        OnboardingSlide(
            title: "Scan Your Outfit",
            subtitle: "Take or choose a clothing photo and get fast style feedback.",
            icon: "camera.viewfinder"
        ),
        OnboardingSlide(
            title: "Get Smart Matches",
            subtitle: "See color harmony, outfit notes, and simple improvements.",
            icon: "sparkles"
        ),
        OnboardingSlide(
            title: "Build Your Style",
            subtitle: "Save closet pieces and personalize recommendations around what you own.",
            icon: "tshirt"
        )
    ]

    private let styleChoices = ["Casual", "Formal", "Streetwear", "Minimalist", "Bohemian", "Sporty", "Vintage", "Classic"]
    private let colorChoices = ["Black", "White", "Navy", "Gray", "Tan", "Brown", "Blue", "Green", "Red"]
    private let occasionChoices = ["Work", "Weekend", "Date Night", "Workout", "Travel", "Church", "Dinner", "Formal"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Style Match Pro")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.top, 12)

            TabView(selection: $selectedPage) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index])
                        .tag(index)
                }

                preferencesView
                    .tag(slides.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack(spacing: 12) {
                Button {
                    finishOnboarding()
                } label: {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    if selectedPage < slides.count {
                        withAnimation {
                            selectedPage += 1
                        }
                    } else {
                        finishOnboarding()
                    }
                } label: {
                    Text(selectedPage < slides.count ? "Next" : "Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .appScreenBackground(.home)
        .tint(AppTab.home.palette.accent)
    }

    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: slide.icon)
                .font(.system(size: 74))
                .foregroundStyle(AppTab.home.palette.accent)
                .frame(width: 132, height: 132)
                .background(AppTab.home.palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 28))

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(slide.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private var preferencesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Personalize Your Style")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Pick a few starting preferences. You can edit these later in Profile.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                chipSection(title: "Style", options: styleChoices, selection: $selectedStyles)
                chipSection(title: "Colors", options: colorChoices, selection: $selectedColors)
                chipSection(title: "Occasions", options: occasionChoices, selection: $selectedOccasions)
            }
            .padding()
            .padding(.top, 24)
        }
    }

    private func chipSection(title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.wrappedValue.contains(option)

                    Button {
                        if isSelected {
                            selection.wrappedValue.remove(option)
                        } else {
                            selection.wrappedValue.insert(option)
                        }
                    } label: {
                        HStack {
                            Text(option)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? AppTab.home.palette.accent : AppTab.home.palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func finishOnboarding() {
        if !selectedStyles.isEmpty {
            stylePreferences = selectedStyles.sorted().joined(separator: ", ")
        }

        if !selectedColors.isEmpty {
            favoriteColors = selectedColors.sorted().joined(separator: ", ")
        }

        if !selectedOccasions.isEmpty {
            occasions = selectedOccasions.sorted().joined(separator: ", ")
        }

        hasCompletedOnboarding = true
    }
}

private struct OnboardingSlide {
    let title: String
    let subtitle: String
    let icon: String
}
