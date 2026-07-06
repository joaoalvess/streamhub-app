//
//  StreamHubApp.swift
//  StreamHub
//
//  Created by João Alves on 19/06/26.
//

import SwiftUI

@main
struct StreamHubApp: App {
    @State private var coordinator: PlaybackCoordinator

    init() {
        SecretsStore.shared.bootstrapIfNeeded()
        _coordinator = State(initialValue: PlaybackCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(coordinator.progressStore)
                .onOpenURL { coordinator.handleIncomingURL($0) }
        }
    }
}
