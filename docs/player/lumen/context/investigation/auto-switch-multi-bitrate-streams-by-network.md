# Auto switch multi-bitrate streams by network

## Status
Presente.

## Evidência
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:82` — `public var videoAdaptable = true` (flag de configuração, ligado por padrão).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:199-217` — `open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)?`: decide se deve subir/descer de bitrate.
- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:148-160` — `struct VideoAdaptationState` com `bitRates`, `bitRateStates`, `loadedCount`, `isPlayable`, `fps`, `duration`, `currentPlaybackTime`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:386-391` — ao abrir o stream, coleta todas as tracks de vídeo com `bitRate > 0`; se houver mais de uma e `options.videoAdaptable` estiver ligado, monta o `videoAdaptation` inicial.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:737-756` — a cada atualização de estado de carregamento, popula `loadedCount`/`isPlayable`/`currentPlaybackTime`, chama `options.adaptable(state:)`, e se houver troca de bitrate desabilita a track antiga (`isEnabled = false`) e habilita a nova (implícito via re-seleção de track), registra o novo `BitRateState` e notifica `delegate?.sourceDidChange(oldBitRate:newBitrate:)`.
- `Sources/KSPlayer/MEPlayer/Model.swift:47` — protocolo `sourceDidChange(oldBitRate:newBitrate:)`.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:286-287` — implementação do delegate, apenas loga a troca (`KSLog("oldBitRate ... change to newBitrate ...")`).
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:20,62-77,129` — `bitRate` populado a partir de `codecpar.bit_rate` ou metadata `variant_bitrate`/`BPS`, usado para identificar as variantes disponíveis (tipicamente streams HLS/DASH multi-bitrate ou containers com múltiplas tracks de vídeo).

## Como funciona
Quando o `MEPlayerItem` abre o `AVFormatContext` e enumera as streams de vídeo, se existir mais de uma variante com bitrate distinto (`bitRates.count > 1`) e a opção `videoAdaptable` estiver habilitada (default `true` em `KSOptions`), é criado um `VideoAdaptationState` guardando a lista ordenada de bitrates disponíveis e o estado inicial.

A cada ciclo de atualização do estado de buffer/loading (`MEPlayerItem.swift:737` em diante), o código atualiza `loadedCount` (pacotes + frames em buffer) e `isPlayable`, e chama `options.adaptable(state:)`. Essa função (`KSOptions.swift:199`) implementa a lógica de decisão:
- Só reavalia após passar metade do `maxBufferDuration` desde a última troca.
- Calcula `isUp` comparando `loadedCount` com `fps * maxBufferDuration / 2` — ou seja, decide subir/descer bitrate com base em quão cheio está o buffer de pacotes decodificados, não em uma medição direta de largura de banda de rede.
- Se `isUp` bate com `isPlayable` atual, sobe um degrau na lista de bitrates ordenada; caso contrário desce um degrau.

Se a função retorna um par `(oldBitRate, newBitrate)` diferente, `MEPlayerItem` desabilita a track do bitrate antigo, ativa a track do novo, registra o novo estado e notifica o delegate via `sourceDidChange`, que no `KSMEPlayer` apenas loga a mudança (não há callback público de app para UI reagir além do log).

Ou seja: existe implementação completa e funcional de troca automática de stream multi-bitrate baseada em condição de rede *inferida indiretamente pelo estado do buffer de download/decodificação* (técnica clássica de ABR "buffer-based", equivalente em efeito ao ABR por bandwidth em players como HLS.js/AVPlayer nativo), cobrindo path FFmpeg/MEPlayer (não se aplica ao path KSAVPlayer/AVFoundation nativo, que delega adaptação de bitrate ao próprio `AVPlayer` do sistema quando a URL é HLS).

## O que falta
Nada bloqueante para o funcionamento básico. Pontos de possível evolução, caso se queira paridade ainda maior com Infuse/versão paga:
- Não há medição direta de bandwidth de rede (ex.: taxa de download em bytes/segundo via `IOTransportStatistics`/`AVPlayerItemAccessLog` ou cálculo próprio) — a heurística é só buffer occupancy. Um ABR mais preciso tocaria `MEPlayerItem.swift` (perto de `updateLoadingState`/linha ~737) para injetar uma métrica de throughput medido.
- `sourceDidChange` (`KSMEPlayer.swift:286`) só loga; não há evento exposto ao app (StreamHub) para mostrar ao usuário que houve troca de qualidade — para UI, seria necessário estender `MediaPlayerProtocol`/notificações do player.
- Não há teste automatizado localizado cobrindo esse fluxo (não encontrado em buscas por "adaptable" em Tests/).
