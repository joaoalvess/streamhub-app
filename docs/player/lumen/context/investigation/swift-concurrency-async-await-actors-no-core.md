## Status

Parcial.

## Evidência

- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:17` — `private let operationQueue = OperationQueue()` (demuxing/leitura do pacote FFmpeg roda em `OperationQueue`, não em `Task`/actor).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:164,426,435,619` — `openThread()`/`readThread()` disparados via `operationQueue.addOperation`, padrão thread-based clássico (GCD), sem `async`/`await`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:505,665` — uso de `DispatchQueue.main.async` / `DispatchQueue.global().async` para saltar de thread, em vez de `await MainActor.run` ou isolamento por actor.
- `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift:180,226,233` — outro `OperationQueue()` dedicado por track, com `decodeThread()` — mesmo padrão thread-based no pipeline de decode de áudio/vídeo.
- `Sources/KSPlayer/MEPlayer/AudioRendererPlayer.swift:42` — `DispatchQueue(label: "ks.player.serialization.queue")` para serializar acesso ao renderer de áudio.
- Nenhuma declaração `actor` (nem `final actor`) existe em todo `Sources/KSPlayer` — busca por `\bactor\b` (excluindo `@MainActor`) não retornou nenhum tipo `actor` no projeto.
- `@MainActor` aparece só na camada de UI/API pública: `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:59,669`; `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:66,73,108,186,289`; `Sources/KSPlayer/AVPlayer/KSOptions.swift:338`; `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:107`; `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:308,428`; `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:68,530`; `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:15,20,139`. Isso isola chamadas de API (play/pause/seek, propriedades observáveis) na main thread, mas não envolve o pipeline de decodificação em si.
- `async`/`await` reais só existem em torno de AVFoundation/AVAsset (`Sources/KSPlayer/Core/Utility.swift:198,201,216,227-230,354-360,389,409` — `loadTracks`, `createExportSession`, `URLSession.shared.data`) e em pequenos wrappers (`Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:392,563-564` — `withCheckedContinuation`, `track.assetTrack?.load`), todos consumindo APIs assíncronas nativas da Apple, não construídos pelo core FFmpeg do KSPlayer.
- `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:32` — `try await Task { ... }` usado para gerar thumbnails, outro ponto isolado de uso de `Task`, fora do pipeline principal de demux/decode.

## Como funciona (o que já existe)

A superfície pública SwiftUI/AVFoundation (`KSVideoPlayer`, `KSPlayerLayer`, `KSAVPlayer`, `KSMEPlayer`, `KSOptions`) adota `@MainActor` para garantir que estado observável e chamadas de controle rodem na main thread — isso é Swift Concurrency real, mas é isolamento declarativo de camada de API, não reescrita do motor de reprodução. Pontos isolados usam `async`/`await` para interagir com APIs assíncronas da própria Apple (`AVAsset.loadTracks`, `AVAssetExportSession`, `URLSession`), e há um uso pontual de `Task { }` para geração de thumbnail.

## O que falta

O núcleo de demuxing e decode em `MEPlayerItem.swift` e `MEPlayerItemTrack.swift` — que é o coração de performance do player (leitura de pacotes FFmpeg, decode de áudio/vídeo, sincronização de clock) — continua 100% baseado em `OperationQueue`/`Thread`/`DispatchQueue`, sem nenhum `actor` isolando estado mutável compartilhado (buffers, filas de pacotes, clocks) nem `async`/`await` no fluxo de leitura/decodificação.

Uma implementação completa de "Swift Concurrency no core" tocaria:
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` — substituir `operationQueue`/`openThread()`/`readThread()` por um `actor` (ou `AsyncSequence`/`AsyncStream` de pacotes) que serialize acesso a estado (`allPlayerItemTracks`, clocks, flags de seek/EOF) sem locks manuais.
- `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift` — mesmo tratamento para `decodeThread()`/`operationQueue`, migrando a fila de frames decodificados para um actor ou `AsyncChannel`.
- `Sources/KSPlayer/MEPlayer/AudioRendererPlayer.swift` — substituir a `DispatchQueue` de serialização por um actor dedicado ao estado do renderer de áudio.
- Reavaliar os `DispatchQueue.main.async` espalhados em `MEPlayerItem.swift:505,665` e `KSMEPlayer.swift:509,525,552` para usar `await MainActor.run` ou propagação de `@MainActor` coerente com o resto da API pública.
- Definir se o modelo de threading do FFmpeg (que é fundamentalmente síncrono e bloqueante em C) permite migração real para actors sem perda de performance, ou se a "paridade" alegada pela versão paga é apenas nas camadas Swift acima do core C — isso não pôde ser confirmado sem acesso ao changelog/binário da versão paga.
