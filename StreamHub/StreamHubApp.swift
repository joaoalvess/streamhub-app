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
    @State private var metaProvider: MetaProvider
    @State private var profileStore: ProfileStore

    init() {
        SecretsStore.shared.bootstrapIfNeeded()
        _coordinator = State(initialValue: PlaybackCoordinator())
        _metaProvider = State(initialValue: MetaProvider())
        _profileStore = State(initialValue: ProfileStore())
    }

    var body: some Scene {
        WindowGroup {
            AppRootGate()
                .environment(profileStore)
                .environment(coordinator)
                .environment(coordinator.progressStore)
                .environment(metaProvider)
                .onOpenURL { coordinator.handleIncomingURL($0) }
        }
    }
}
