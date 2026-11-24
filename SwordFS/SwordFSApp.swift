import SwiftUI

@main
struct SwordFSApp: App {
    @StateObject private var controller = ExploitController()

    var body: some Scene {
        WindowGroup {
            ExploitView()
                .environmentObject(controller)
        }
    }
}
