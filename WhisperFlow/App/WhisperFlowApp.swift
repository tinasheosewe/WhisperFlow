import SwiftUI

@main
struct WhisperFlowApp: App {
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            SessionView()
                .environment(sessionManager)
        }
    }
}
