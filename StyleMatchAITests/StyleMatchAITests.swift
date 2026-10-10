import XCTest
import SwiftUI
import UIKit
@testable import StyleMatchAI

final class StyleMatchAITests: XCTestCase {
    @MainActor
    func testScanRenderingSectionDefersConstructionUntilItsBodyIsEvaluated() {
        var constructions = 0
        let section = ScanRenderSection {
            constructions += 1
            return AnyView(Text("Scan"))
        }
        XCTAssertEqual(constructions, 0, "Parent construction must not eagerly expand a Scan section.")
        _ = section.body
        XCTAssertEqual(constructions, 1)
        XCTAssertLessThan(MemoryLayout<ScanRenderSection>.size, 128)
    }

    @MainActor
    func testCameraAndGalleryControlsRenderWithoutStartingCapture() {
        var cameraStarts = 0
        for disabled in [false, true] {
            for width in [320.0, 430.0, 1024.0] {
                let controls = ScanSourceControl(
                    selectedItem: .constant(nil),
                    background: .black, cream: .white, border: .gray,
                    isDisabled: disabled, onStartCamera: { cameraStarts += 1 }
                )
                let host = UIHostingController(rootView: controls.environment(\.dynamicTypeSize, .accessibility3))
                let size = host.sizeThatFits(in: CGSize(width: width, height: 1366))
                XCTAssertTrue(size.width.isFinite && size.height.isFinite)
                XCTAssertGreaterThanOrEqual(size.height, 54)
            }
        }
        XCTAssertEqual(cameraStarts, 0)
        XCTAssertLessThan(MemoryLayout<ScanSourceControl.Body>.size, 4096,
                          "Source controls must keep small concrete children instead of expanding both labels.")
    }

    @MainActor
    func testScanStartCardRendersAtLargeTextSizesWithoutStartingCamera() {
        var cameraStarts = 0
        for isDisabled in [false, true] {
            let card = ScanStartCard(
                cream: .white, muted: .gray, isDisabled: isDisabled,
                onStartCamera: { cameraStarts += 1 }
            )
            let host = UIHostingController(rootView: card.environment(\.dynamicTypeSize, .accessibility3))
            let size = host.sizeThatFits(in: CGSize(width: 430, height: 932))
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThanOrEqual(size.height, 92)
        }
        XCTAssertEqual(cameraStarts, 0, "Rendering a Scan entry point must not invoke camera capture.")
    }

    @MainActor
    func testEmptyScanScreenRendersAtPhoneAndTabletSizes() throws {
        let suiteName = "ScanRenderingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for bounds in [CGSize(width: 430, height: 932), CGSize(width: 1024, height: 1366)] {
            let scan = ScanView(selectedTab: .constant(.scan))
                .defaultAppStorage(defaults)
            let host = UIHostingController(rootView: scan)
            let window = UIWindow(frame: CGRect(origin: .zero, size: bounds))
            window.rootViewController = host
            window.isHidden = false
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let size = host.sizeThatFits(in: bounds)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            window.isHidden = true
            window.rootViewController = nil
        }
    }


    @MainActor
    func testStyleFriendsHeroFitsPhoneAndTabletAtAccessibleTextSizesWithoutSending() {
        var actions = 0
        for width in [320.0, 430.0, 1024.0] {
            for typeSize in [DynamicTypeSize.large, .accessibility3] {
                let view = StyleFriendsEditorialHero(onShareLook: { actions += 1 }, onMessages: { actions += 1 })
                    .environment(\.dynamicTypeSize, typeSize)
                let host = UIHostingController(rootView: view)
                let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                XCTAssertTrue(size.width.isFinite && size.height.isFinite)
                XCTAssertLessThanOrEqual(size.width, width + 1, "Hero actions must wrap rather than overflow narrow phones.")
                XCTAssertGreaterThan(size.height, 200)
            }
        }
        XCTAssertEqual(actions, 0, "Rendering must not publish a look, open a conversation, or send anything.")
    }

    @MainActor
    func testStyleFriendsConversationRowsFitLongNamesAndAccessibilityText() {
        let conversation = StyleFriendsConversationPresentation(
            conversationReference: StyleFriendsOpaqueRouteReference("fixture_visual_long_name")!,
            friendSocialReference: nil,
            friendDisplayName: "Alexandra Montgomery-Washington",
            avatarReference: nil,
            lastMessagePreview: "I shared my outfit photo and saved score. What do you think?",
            lastActivity: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for width in [320.0, 430.0, 1024.0] {
            let view = StyleFriendsConversationRow(conversation: conversation)
                .environment(\.dynamicTypeSize, .accessibility3)
            let host = UIHostingController(rootView: view)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertLessThanOrEqual(size.width, width + 1)
            XCTAssertGreaterThanOrEqual(size.height, 88)
        }
    }

    @MainActor
    func testExportStyleFriendsVisualPreviewsWithoutLiveServices() throws {
        for scheme in [ColorScheme.light, .dark] {
            let preview = VStack(alignment: .leading, spacing: 20) {
                Text("KigoStylist · Style Friends").font(.headline)
                StyleFriendsEditorialHero(onShareLook: {}, onMessages: {})
                StyleFriendsInboxHeading()
                StyleFriendsConversationRow(conversation: StyleFriendsChatPresentationFixtures.jordan)
                Text("Design preview • sample conversation")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 390)
            .background(scheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.09) : Color(red: 0.97, green: 0.96, blue: 0.94))
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: preview)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let name = scheme == .dark ? "kigo-style-friends-dark" : "kigo-style-friends-light"
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("KIGO_PREVIEW_PATH=" + url.path)
        }
    }

    func testAppModuleLoads() {
        XCTAssertNotNil(OutfitAnalysisResult.self)
    }

    func testAppleSignInDiagnosticBufferSurvivesReloadWithoutCredentials() {
        StyleMatchAppleSignInDiagnosticBuffer.begin()
        StyleMatchAppleSignInDiagnosticBuffer.record(.appleAuthorizationResult)
        StyleMatchAppleSignInDiagnosticBuffer.record(.requestDispatched)

        // A fresh load models the post-relaunch reader. The buffer retains
        // only opaque lifecycle stages; no credential-bearing field exists.
        let restored = StyleMatchAppleSignInDiagnosticBuffer.load()
        XCTAssertEqual(restored.last?.stages, [.attemptCreated, .appleAuthorizationResult, .requestDispatched])
        XCTAssertLessThanOrEqual(restored.count, 3)
    }

    func testSharedSessionRecoveryRoutesToProfileWithoutFeatureSpecificAppleSignIn() {
        XCTAssertEqual(StyleMatchSessionRecoveryCopy.title, "KigoStylist session required")
        XCTAssertEqual(StyleMatchSessionRecoveryCopy.actionTitle, "Open Profile")
        XCTAssertEqual(
            StyleMatchSessionRecoveryCopy.detail(for: "AI Stylist"),
            "AI Stylist uses your KigoStylist account. Reconnect once in Profile to continue."
        )
        XCTAssertEqual(
            StyleMatchSessionRecoveryCopy.detail(for: "Style Friends"),
            "Style Friends uses your KigoStylist account. Reconnect once in Profile to continue."
        )

        let expectation = expectation(description: "Profile reconnect route")
        let observer = NotificationCenter.default.addObserver(
            forName: StyleMatchAccountSessionStore.profileReconnectRequestedNotification,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }
        NotificationCenter.default.post(name: StyleMatchAccountSessionStore.profileReconnectRequestedNotification, object: nil)
        wait(for: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }
}
