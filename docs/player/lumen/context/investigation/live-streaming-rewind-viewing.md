## Status

Ausente.

## Evidência

- `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:562-585` — em `VideoTimeShowView`, se `config.playerLayer?.player.seekable` for `false` a UI simplesmente mostra o texto `"Live Streaming"` e não renderiza nenhum slider/controle de scrub. Não há nenhum caminho de código para retroceder um live nessa view.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:602-610` — `seekable` é derivado só da flag nativa do protocolo/formato FFmpeg (`ioContext.pointee.seekable > 0`), não de um buffer de DVR/timeshift mantido pelo player. Não existe lógica que amplie a janela seekable de um live.
- `Sources/KSPlayer/Core/PlayerToolBar.swift:41-92` — no toolbar UIKit, `isLiveStream` é apenas `totalTime == 0`; quando true, o slider é preenchido com `todayInterval` (segundos desde meia-noite local) e `maximumValue = 60*60*24`. É puramente cosmético: o valor representa a hora do relógio, não uma posição real dentro de um buffer de conteúdo já transmitido. Arrastar esse slider não está ligado a nenhuma lógica de fetch/replay de segmentos passados (não há handler de `valueChanged` conectado a um seek de DVR nesse arquivo).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:22,466` — só existe `maxBufferDuration` (30s, forward buffering para reduzir stalls), sem parâmetro de buffer retroativo/"look-back window" para lives.
- Busca ampla por `rewind|timeshift|dvr|live.*seek` em todo o pacote (`rg -i` em `Sources/KSPlayer`) não retornou nenhuma correspondência fora dos arquivos acima — nenhum tipo, opção de `KSOptions`, ou branch de plataforma dedicado a isso.

## O que falta

Não há nenhum esboço de "assistir com atraso"/rewind ao vivo — apenas o mecanismo genérico de `seek()` do FFmpeg, que funciona para VOD e para os poucos protocolos live que reportam `seekable=1` nativamente (ex.: algumas fontes catch-up com range HTTP), mas isso é incidental, não uma feature de rewind de live.

Para implementar de fato, seria necessário:
- Um buffer circular retroativo (ex.: manter N minutos de pacotes/segmentos já demuxados em disco ou memória) em `MEPlayerItem`/`OutputRenderQueue`, já que hoje só existe buffering para frente (`loadingState.loadedTime`, `maxBufferDuration`).
- Uma opção nova em `KSOptions` (ex.: `liveBackwardBufferDuration`) para configurar o tamanho da janela de rewind.
- Trocar a checagem de `seekable` (hoje binária, vinda do protocolo) por uma noção de "seekable dentro da janela de buffer local", em `MEPlayerItem.seekable` e no `seek(time:)` de `KSMEPlayer.swift:355`.
- Atualizar a UI: `VideoTimeShowView` (`KSVideoPlayerView.swift:562`) precisaria mostrar um slider real com origem relativa ("N minutos atrás") ao invés do texto fixo "Live Streaming"; o `PlayerToolBar` (linha 84-92) precisaria trocar o slider cosmético de `todayInterval` por uma posição real dentro do buffer de rewind.
- Persistir/gerenciar timestamps de PTS absolutos por segmento para permitir mapear "posição do slider" → offset real no stream ao vivo.
