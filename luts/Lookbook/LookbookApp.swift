import SwiftUI

@main
struct LookbookApp: App {
    @State private var pipeline = EditingPipeline()

    var body: some Scene {
        WindowGroup {
            ContentView(pipeline: pipeline)
        }
        .defaultSize(width: 1400, height: 900)
    }
}
