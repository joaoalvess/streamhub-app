## Status

Parcial

## Evidência

- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:271-326` — `startRecord(url:)`: cria `outputFormatCtx` via `avformat_alloc_output_context2`, mapeia streams de entrada (áudio/vídeo/legenda) para streams de saída, copia `codecpar` (remux, sem reencode), abre `avio_open` e escreve o header (`avformat_write_header`).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:527-544` — no loop de leitura de pacotes (dentro de `read()`), a cada pacote lido, se `outputFormatCtx` existir e o stream tiver mapeamento em `streamMapping`, o pacote é referenciado, reescalado (`av_packet_rescale_ts`) e escrito via `av_interleaved_write_frame`. Ou seja, a gravação é feita continuamente enquanto o player está lendo, não só no início.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:672-676` — `stopRecord()`: chama `av_write_trailer` para fechar o arquivo de saída corretamente.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:631-632` e `:648` — `shutdown()` chama `stopRecord()` e fecha `outputFormatCtx` (`avformat_close_input`), garantindo que a gravação é finalizada ao encerrar o item.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:580-588` — API pública `KSMEPlayer.startRecord(url:)` / `KSMEPlayer.stoptRecord()` (sic, typo no nome) que apenas repassam para `playerItem.startRecord`/`stopRecord`. Podem ser chamadas a qualquer momento durante a reprodução (não dependem de estado específico), o que tecnicamente permite iniciar/parar gravação "a qualquer momento".
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:260-262` — no fluxo de abertura (`openThread`/`createCodec`), se `options.outputURL` estiver setado antes da abertura, `startRecord` já é chamado automaticamente ao abrir o item.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:42` — `public var outputURL: URL?`, único ponto de configuração declarativa (recording a partir do início da reprodução).
- `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift` — busca por `startRecord`/`stopRecord` não retorna nada: a função **não faz parte** do protocolo `MediaPlayerProtocol`, ou seja, só existe no backend FFmpeg/MEPlayer (`KSMEPlayer`), não no backend `KSAVPlayer` (AVFoundation).
- Nenhuma ocorrência de `startRecord`/`stoptRecord`/`outputURL` em `Sources/KSPlayer/Video/VideoPlayerView.swift`, `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift`, `Sources/KSPlayer/Video/SeekView.swift` nem em nenhum outro componente de UI/controles do player — não há botão, gesto, menu ou control state exposto para o usuário disparar a gravação.
- `Demo/demo-iOS/demo-iOS/AppDelegate.swift:120` e `Demo/SwiftUI/Shared/MovieModel.swift:284-290` — único uso real de `options.outputURL` no repositório, e é um hack de debug amarrado a um nome de arquivo de teste específico (`bipbopall.m3u8`), só em macOS, sem qualquer UI associada — não é uma feature de produto, é um teste manual do autor original do KSPlayer.
- `Sources/KSPlayer/Core/Utility.swift:225-256` — existe também um `exportMp4(beginTime:endTime:outputURL:progress:completion:)` baseado em `AVAssetExportSession`, mas isso é recorte/exportação de um intervalo de um asset já existente (edição pós-hoc via AVFoundation), não gravação ao vivo de um clipe durante a reprodução; não tem nenhuma chamada em código de produto (não aparece referenciado fora de `Utility.swift`).

## Como funciona (mecanismo interno existente)

O `MEPlayerItem` (backend FFmpeg puro, usado por `KSMEPlayer`) já implementa remux "ao vivo": enquanto os pacotes demuxados do stream de entrada passam pelo loop principal de leitura, se houver um `outputFormatCtx` aberto, cada pacote correspondente a uma stream mapeada é copiado (sem reencode) para o arquivo de saída via `av_interleaved_write_frame`. Isso significa que, tecnicamente, é possível chamar `KSMEPlayer.startRecord(url:)` a qualquer momento durante a reprodução para começar a gravar a partir daquele ponto em diante, e `stoptRecord()` para fechar o arquivo com trailer válido. O fluxo write-header → remux por pacote → write-trailer está completo e funcional no nível de engine.

## O que falta

Para virar de fato a feature "Record video clips at any time" (paridade com o pago/Infuse), falta a camada de produto/UI em cima do mecanismo já existente:

1. **Exposição no protocolo comum**: `startRecord`/`stopRecord` não estão em `MediaPlayerProtocol` (`Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift`), então só funcionam quando o backend ativo é `KSMEPlayer` — seria preciso decidir o comportamento (no-op, erro, ou fallback via `AVAssetExportSession`) quando o backend for `KSAVPlayer`.
2. **Controle de UI**: nenhum botão/gesto em `Sources/KSPlayer/Video/VideoPlayerView.swift`, `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift` ou nos overlays de controle do tvOS para iniciar/parar gravação, indicar estado "gravando" (ex.: badge vermelho), escolher destino do arquivo, ou notificar sucesso/erro.
3. **Concessão de "clipe"**: hoje só existe start/stop manual (gravação de duração indefinida a partir do ponto atual). Um recurso de "clip" como o do Infuse tipicamente grava os últimos N segundos de buffer (replay buffer) ou permite marcar início/fim e exportar — isso exigiria um buffer circular de pacotes recentes (não existe hoje) ou reaproveitar `exportMp4` (`Sources/KSPlayer/Core/Utility.swift:225`) sobre um arquivo já demuxado/cacheado, o que também não existe para streams ao vivo/HLS.
4. **Gestão de arquivo/permissões em tvOS**: não há código de destino de arquivo (photo library, `Documents`, compartilhamento) nem tratamento de erros de disco/permissão — os erros de `startRecord` hoje só passam por `KSLog` (`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:276,321`), sem callback/estado observável pela UI.
5. **Testes/validação**: o único uso do fluxo é o hack de debug em `Demo/SwiftUI/Shared/MovieModel.swift:289`, condicionado a `#if os(macOS)` e a um nome de arquivo fixo — não há evidência de que o caminho tenha sido exercitado com playback ao vivo real, seek durante gravação, ou troca de faixas.

Uma implementação começaria por: (a) adicionar `startRecord(url:)`/`stopRecord()`/estado `isRecording` ao `MediaPlayerProtocol` com um fallback no `KSAVPlayer` (provavelmente via `AVAssetWriter` alimentado por `AVPlayerItemVideoOutput`, já que o AVPlayer não expõe pacotes brutos); (b) adicionar um botão/gesto na camada de controles SwiftUI/tvOS que chame o método e mostre indicador de gravação; (c) decidir se "clip" significa remux contínuo (o que já existe) ou snapshot de buffer/replay (que exigiria novo componente de buffer circular).
