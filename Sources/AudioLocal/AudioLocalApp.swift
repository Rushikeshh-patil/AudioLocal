import SwiftUI

@main
struct AudioLocalApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 720)
        }
    }
}
