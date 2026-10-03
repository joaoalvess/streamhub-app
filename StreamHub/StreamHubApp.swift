//
//  StreamHubApp.swift
//  StreamHub
//
//  Created by João Alves on 19/06/26.
//

import SwiftUI
import Lumen

@main
struct StreamHubApp: App {
    @State private var coordinator: PlaybackCoordinator
    @State private var metaProvider: MetaProvider
    @State private var profileStore: ProfileStore
    @State private var recentSearches: RecentSearchesStore
    @State private var myList: MyListStore
    @State private var toasts: ToastCenter

    init() {
        SecretsStore.shared.bootstrapIfNeeded()
        KSOptions.firstPlayerType = ProAVPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.audioPlayerType = AudioRendererPlayer.self
        _coordinator = State(initialValue: PlaybackCoordinator())
        _metaProvider = State(initialValue: MetaProvider())
        _profileStore = State(initialValue: ProfileStore())
        _recentSearches = State(initialValue: RecentSearchesStore())
        _myList = State(initialValue: MyListStore())
        _toasts = State(initialValue: ToastCenter())
    }

    var body: some Scene {
        WindowGroup {
            AppRootGate()
                .environment(profileStore)
                .environment(coordinator)
                .environment(coordinator.progressStore)
                .environment(metaProvider)
                .environment(recentSearches)
                .environment(myList)
                .environment(toasts)
        }
    }
}
