import Foundation
import Testing
@testable import StreamHub

@MainActor
struct ToastCenterTests {
    @Test func showPublishesCurrentToast() {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Adicionado à Minha lista", systemImage: "plus")
        #expect(center.current?.message == "Adicionado à Minha lista")
        #expect(center.current?.systemImage == "plus")
    }

    @Test func systemImageDefaultsToNil() {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Temporada desmarcada")
        #expect(center.current?.message == "Temporada desmarcada")
        #expect(center.current?.systemImage == nil)
    }

    @Test func newToastReplacesCurrent() throws {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Marcado como assistido")
        let first = try #require(center.current)
        center.show("Marcado como não assistido")
        let second = try #require(center.current)
        #expect(second.message == "Marcado como não assistido")
        #expect(second.id != first.id)
    }

    @Test func dismissIgnoresStaleToast() throws {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Adicionado à Minha lista")
        let stale = try #require(center.current)
        center.show("Removido da Minha lista")
        center.dismiss(id: stale.id)
        #expect(center.current?.message == "Removido da Minha lista")
    }

    @Test func dismissClearsCurrentToast() throws {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Temporada marcada como assistida")
        let toast = try #require(center.current)
        center.dismiss(id: toast.id)
        #expect(center.current == nil)
    }

    @Test func dismissesAutomaticallyAfterDuration() async throws {
        let center = ToastCenter(duration: .milliseconds(10))
        center.show("Marcado como assistido")
        var attempts = 0
        while center.current != nil, attempts < 100 {
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }
        #expect(center.current == nil)
    }

    @Test func staysVisibleBeforeDuration() async throws {
        let center = ToastCenter(duration: .seconds(60))
        center.show("Marcado como assistido")
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.current?.message == "Marcado como assistido")
    }
}
