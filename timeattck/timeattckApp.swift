import SwiftUI
import SwiftData
import FirebaseCore

@main
struct timeattckApp: App {
    init() {
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    requestNotificationPermission()
                    importFromBundleBackup(context: sharedModelContainer.mainContext)
                    migrateFromUserDefaults(context: sharedModelContainer.mainContext)
                    migrateIconsToSFSymbols(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
