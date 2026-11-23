import SwiftUI

@main
struct MyGuardiansApp: App {
    @StateObject private var store = GuardianStore()

    init() {
        #if DEBUG
        OGType.verifyFontRegistration()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .font(OGType.body)
                .preferredColorScheme(.light)
        }
    }
}
