## Status

parcial

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:49` — `public var nobuffer = false` (flag manual, default desligada).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:50` — `public var codecLowDelay = false` (flag manual, default desligada).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:233-235` — `videoFrameMaxCount(fps:naturalSize:isLive:)` retorna `4` frames para live vs `16` para VOD (única adaptação automática ligada a "live").
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:466` — `static var maxBufferDuration = 30.0` (buffer alvo genérico de 30s, sem override para live/baixa latência).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:215-217` — seta `AVFMT_FLAG_GENPTS` sempre, e `AVFMT_FLAG_NOBUFFER` somente `if options.nobuffer` (dependente da flag manual acima).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:378` — `duration == 0` é usado como heurística de "é live" para reduzir `videoFrameMaxCount`.
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:97-99` — `if options?.codecLowDelay == true { codecContext.pointee.flags |= AV_CODEC_FLAG_LOW_DELAY }` (também dependente da flag manual).
- `Sources/KSPlayer/Core/PlayerToolBar.swift:90` — `isLiveStream` (getter de UI, controla exibição de controles, não afeta pipeline de decode/buffer).
- Nenhuma ocorrência de `rtsp_transport`, `flush_packets`, `max_delay`, `fflags`/`nobuffer` como string de opção FFmpeg, WebRTC, SRT, ou qualquer transporte otimizado para LAN. `probesize`/`maxAnalyzeDuration` (`KSOptions.swift:46-47`) existem mas são `nil` por padrão e não têm nenhum preset "low latency".
- Nenhuma referência a "200ms", medição de latência, ou modo dedicado "low latency" / "4K live" em todo o pacote (`rg -ni "latency|4k" Sources/KSPlayer` não retornou lógica de feature, apenas os nomes de flags citados acima).

## Como funciona

Existem apenas ganchos genéricos de baixa latência herdados do ffplay/KSPlayer original:

1. `KSOptions.nobuffer` (default `false`) — se o app consumidor setar `true`, propaga `AVFMT_FLAG_NOBUFFER` para o `AVFormatContext` em `MEPlayerItem.swift:216-217`, reduzindo buffering de demux.
2. `KSOptions.codecLowDelay` (default `false`) — se setado, aplica `AV_CODEC_FLAG_LOW_DELAY` no codec context (`AVFFmpegExtension.swift:98-99`), reduzindo delay de decode em codecs que suportam.
3. Detecção heurística de stream live (`duration == 0`) reduz o tamanho do buffer de frames de vídeo de 16 para 4 (`KSOptions.swift:234`), o que ajuda a diminuir a fila de frames decodificados, mas não é um "modo" de latência dedicado — é só usado por quem chama `videoFrameMaxCount`.

Nenhum desses três pontos é acionado automaticamente por um modo "low latency" ou por detecção de LAN/4K; cada um depende de o app anfitrião (StreamHub) configurar manualmente `KSOptions` antes de tocar. Não há orquestração entre eles nem meta de latência (<200ms) codificada em nenhum lugar.

## O que falta

Para existir de fato uma feature "low latency 4K live streaming <200ms LAN" seria necessário:

- Um modo/preset dedicado em `KSOptions` (ex.: `public var lowLatencyLiveMode = false` ou similar) que ligasse `nobuffer`, `codecLowDelay`, reduzisse `maxBufferDuration`/`videoFrameMaxCount` e ajustasse `probesize`/`maxAnalyzeDuration` para valores pequenos automaticamente ao detectar stream live — hoje isso exige configuração manual e não existe nenhum preset.
- Tuning de opções de demuxer específicas de baixa latência (`fflags=nobuffer+discardcorrupt`, `flush_packets=1`, `max_delay=0`, `rtsp_transport=udp` para RTSP) — nenhuma dessas chaves aparece em `Sources/KSPlayer/AVPlayer/KSOptions.swift` (`formatContextOptions`/`decoderOptions` são dicionários abertos que o app pode preencher, mas não há preset embutido).
- Redução do jitter buffer de áudio/vídeo em sincronização (`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`, clock sync) — não há lógica específica para minimizar delay de sincronismo A/V em modo live além do buffer de frames citado.
- Medição/telemetria de latência ponta-a-ponta (glass-to-glass) para validar a meta de <200ms — inexistente; não há instrumentação de timestamps de captura vs. apresentação.
- Suporte a decode 4K acelerado por hardware já existe de forma genérica (`options?.hardwareDecode`, `AVFFmpegExtension.swift:90`), mas não há nada que combine isso com o caminho de baixa latência — são preocupações ortogonais no código atual.
- Documentação/API pública explicando como configurar esse modo (hoje as flags `nobuffer`/`codecLowDelay` não têm comentários nem exemplo de uso combinado).

Em resumo: o repositório contém os blocos de construção brutos do ffplay/FFmpeg (flags de nobuffer e low-delay, mais heurística de buffer reduzido para live), mas não uma feature integrada, testada ou documentada de "low latency 4K live streaming <200ms na LAN". Trata-se de infraestrutura parcial que uma implementação completa usaria como ponto de partida, concentrando o trabalho em `Sources/KSPlayer/AVPlayer/KSOptions.swift` e `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`.

## Verificação

**Veredito: CONFIRMADO — status "parcial" mantido, contradizendo a tabela oficial (`README.md:76`, `|Low latency 4K live video streaming (less than 200ms on LAN)|✅|✅|`).**

Tentativa ativa de refutação (nomes alternativos, código condicional por plataforma, Demo/, Tests/, termos em chinês do upstream como 低延迟/直播/秒开, dependência de binário FFmpeg) não encontrou nenhum modo integrado de baixa latência. O que a busca adversarial acrescentou à investigação original:

- **`liveAdaptivePlaybackRate` está de fato plugado no pipeline** (não citado na investigação original): `KSMEPlayer.swift:279-282` chama `options.liveAdaptivePlaybackRate(loadingState:)` apenas quando `duration == 0` (live) e o stream está tocando. É um mecanismo real de catch-up de latência via ajuste de velocidade — porém a implementação default em `KSOptions.swift:434-446` retorna `nil` com a lógica inteira comentada. Mais um bloco de infraestrutura bruta desligada por padrão; reforça o "parcial", não o refuta.
- **A própria tabela oficial nega parte do pipeline live ao GPL**: a linha `Annex-B async hardware decoding(Live Stream)` está marcada `✅` LGPL / `❌` GPL (`README.md:59`), ou seja, o decode assíncrono de hardware otimizado para live é explicitamente ausente da versão GPL segundo a mesma tabela que marca a feature de low latency como presente.
- **Defaults trabalham contra <200ms**: `preferredForwardBufferDuration = 3.0` (`KSOptions.swift:464`) e `playable()` exige `loadedTime >= preferredForwardBufferDuration` (`KSOptions.swift:192`) — out-of-the-box a latência é de segundos, não de milissegundos. As opções de format context setadas por padrão (`KSOptions.swift:110-131`) são de reconexão HTTP/IPTV (`reconnect`, `reconnect_streamed`, `scan_all_pmts`), e o tuning de abertura rápida (`fps_probe_size`, `max_analyze_duration`) está literalmente comentado (`KSOptions.swift:117-121`).
- **Nenhum consumidor liga as flags**: `nobuffer`/`codecLowDelay` nunca são setadas como `true` em `Sources/`, `Demo/` ou `Tests/` (o demo SwiftUI só expõe "Fast Open Video" = `isSecondOpen`, que é tempo de startup, não latência de regime).
- **Transporte vem de binário pré-compilado sem tuning**: FFmpeg chega via `kingslay/FFmpegKit` 6.1.4 (`Package.swift:45`); nenhum código Swift configura `rtsp_transport`, `max_delay`, `fflags` ou similar — a capacidade de protocolo do binário não constitui a feature no player.
- **Sync de clock é genérico**: `videoClockSync` (`KSOptions.swift:359-401`) dropa frames/GOP, flusha ou seeka quando o vídeo atrasa — recuperação de A/V sync comum, sem meta de latência.

Conclusão: a linha da tabela é uma alegação de capacidade herdada do marketing do upstream — os knobs manuais permitem que um integrador monte uma configuração de baixa latência por conta própria, mas não existe preset, orquestração automática, medição de latência nem acoplamento com decode 4K. O status correto permanece **parcial**.
