import XCTest
@testable import OpenGlasses

/// Send feedback (FB-1) signs in with ForIT Sign-in, whose redirect comes back as a link on
/// the app's own scheme. If the scheme is missing from CFBundleURLTypes the browser has
/// nowhere to return to, and if the link reached the Meta SDK's callback handler instead of
/// the sign-in, the attempt would wait forever. These pin both.
final class FeedbackAccountTests: XCTestCase {

    func testTheRedirectSchemeIsDeclaredByTheApp() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(try XCTUnwrap(FeedbackAccount.redirectURI.scheme)), "\(schemes)")
    }

    func testTheRedirectIsTheForITForm() {
        XCTAssertEqual(FeedbackAccount.redirectURI.absoluteString, "io.forit.glasses://oauth/callback")
    }

    func testOnlySignInLinksAreTakenFromTheMetaSDK() throws {
        XCTAssertTrue(FeedbackAccount.isSignInLink(try XCTUnwrap(URL(string: "io.forit.glasses://oauth/callback?code=c&state=s"))))
        XCTAssertFalse(FeedbackAccount.isSignInLink(try XCTUnwrap(URL(string: "mwdat-688603774243722://auth?x=1"))))
        XCTAssertFalse(FeedbackAccount.isSignInLink(try XCTUnwrap(URL(string: "https://www.forit.io/"))))
    }

    func testTheEpicIsATaskId() {
        XCTAssertNotNil(UUID(uuidString: FeedbackAccount.epicId))
    }
}
