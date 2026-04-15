import SwiftUI

@main
struct timeattckApp: App {
    @StateObject private var dataModel = DataModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataModel)
        }
    }
}
