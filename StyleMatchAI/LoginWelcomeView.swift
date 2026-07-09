import AuthenticationServices
import SwiftUI

struct LoginWelcomeView: View {
    @AppStorage("hasChosenAccessMode") private var hasChosenAccessMode = false
    @AppStorage("customerAccountMode") private var customerAccountMode = CustomerAccountMode.guest.rawValue
    @AppStorage("customerAccountEmail") private var customerAccountEmail = ""
    @AppStorage("customerAppleUserID") private var customerAppleUserID = ""
    @AppStorage("customerAccountSyncEnabled") private var accountSyncEnabled = false
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("favoriteOutfits") private var favoriteOutfits = ""
    @AppStorage("stylePreferences") private var stylePreferences = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("guestDataLinkedToApple") private var guestDataLinkedToApple = false
    @AppStorage("guestDataTransferSummary") private var guestDataTransferSummary = ""

    @State private var signInMessage: String?
    @State private var showGuestTransferOffer = false

    private let background = Color(hex: 0x080812)
    private let panel = Color(hex: 0x151523)
    private let gold = Color(hex: 0xEED9B5)
    private let muted = Color(hex: 0xA7A5B6)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [background, Color(hex: 0x11101E), Color(hex: 0x2B2459).opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 60)

                    brandHeader
                    separatorLine
                    simplifiedAccessPanel
                    separatorLine

                    Text("Try StyleMatch Pro instantly.\nSign in later to save your profile,\ncloset, and scan history.")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 24)

                    separatorLine

                    if let signInMessage {
                        Text(signInMessage)
                            .font(.footnote)
                            .foregroundStyle(gold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 44)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Transfer Guest Data?",
            isPresented: $showGuestTransferOffer,
            titleVisibility: .visible
        ) {
            Button("Transfer My Guest Data") {
                transferGuestDataToApple()
            }

            Button("Continue Without Transfer") {
                guestDataTransferSummary = "Apple sign-in is active. Local guest data was kept on this iPhone."
                hasChosenAccessMode = true
            }
        } message: {
            Text("StyleMatch Pro can keep your local scan history, favorites, closet, style preferences, and profile information with your Apple sign-in.")
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(gold)
                    .frame(width: 82, height: 82)
                    .shadow(color: gold.opacity(0.34), radius: 22, x: 0, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(background)
            }

            VStack(spacing: 8) {
                Text("StyleMatch Pro")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Your Personal AI Fashion Stylist")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(gold)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(gold.opacity(0.28))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private var simplifiedAccessPanel: some View {
        VStack(spacing: 18) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Rectangle()
                .fill(gold.opacity(0.18))
                .frame(height: 1)
                .padding(.horizontal, 22)

            Button {
                continueAsGuest()
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                    Text("Continue as Guest")
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(gold)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(gold.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(panel.opacity(0.68))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(gold.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func continueAsGuest() {
        customerAccountMode = CustomerAccountMode.guest.rawValue
        customerAccountEmail = ""
        customerAppleUserID = ""
        profileName = ""
        accountSyncEnabled = false
        hasChosenAccessMode = true
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInMessage = "Apple sign-in did not finish. You can continue as guest and sign in later."
                return
            }

            let signedInUserID = credential.user
            customerAccountMode = CustomerAccountMode.apple.rawValue
            customerAppleUserID = signedInUserID
            accountSyncEnabled = true

            if let email = credential.email {
                customerAccountEmail = email
            }

            let givenName = StyleMatchGreetingBuilder.firstName(from: credential.fullName?.givenName)
            if let givenName {
                ProfileStore(userId: signedInUserID).updateGivenName(givenName)
            }

            let fullName = [givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            if !fullName.isEmpty {
                profileName = fullName
            } else {
                profileName = ProfileStore(userId: signedInUserID).currentProfile.givenName ?? ""
            }

            if hasTransferableGuestData {
                showGuestTransferOffer = true
            } else {
                guestDataLinkedToApple = true
                guestDataTransferSummary = "Apple sign-in is active. New style data will be saved to this account when sync is available."
                hasChosenAccessMode = true
            }
        case .failure(let error):
            signInMessage = "Apple sign-in was not completed: \(error.localizedDescription)"
        }
    }

    private var hasTransferableGuestData: Bool {
        !outfitScanHistoryData.isEmpty
        || !closetItemsData.isEmpty
        || LoginWelcomeProfileData.hasIntentionalProfileValues(
            favoriteOutfits: favoriteOutfits,
            stylePreferences: stylePreferences,
            favoriteColors: favoriteColors,
            profileName: profileName
        )
    }

    private func transferGuestDataToApple() {
        var transferred: [String] = []

        if !outfitScanHistoryData.isEmpty {
            transferred.append("scan history")
        }

        let hasIntentionalProfileSave = FounderProfileDefaultsMigration.hasIntentionalProfileSave()

        if hasIntentionalProfileSave,
           LoginWelcomeProfileData.hasValue(favoriteOutfits) {
            transferred.append("favorites")
        }

        if !closetItemsData.isEmpty {
            transferred.append("closet")
        }

        if hasIntentionalProfileSave,
           LoginWelcomeProfileData.hasValue(stylePreferences) || LoginWelcomeProfileData.hasValue(favoriteColors) {
            transferred.append("style preferences")
        }

        if hasIntentionalProfileSave,
           StyleMatchGreetingBuilder.firstName(from: profileName) != nil {
            transferred.append("profile")
        }

        guestDataLinkedToApple = true
        guestDataTransferSummary = transferred.isEmpty
            ? "Apple sign-in is active. New style data will be saved to this account when sync is available."
            : "Transferred guest \(transferred.joined(separator: ", ")) to Apple sign-in on this device."
        hasChosenAccessMode = true
    }
}
