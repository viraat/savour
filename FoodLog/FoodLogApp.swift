import SwiftUI

@main
struct FoodLogApp: App {
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            AppLockView {
                ContentView()
            }
            .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
