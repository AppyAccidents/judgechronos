import SwiftUI

@main
struct Judge_ChronosApp: App {
    @StateObject private var dataStore: LocalDataStore
    @StateObject private var viewModel: ActivityViewModel

    init() {
        let store = LocalDataStore()
        _dataStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: ActivityViewModel(dataStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(viewModel)
        }
    }
}
