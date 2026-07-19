## Status

Presente.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:42` — flag pública `outputURL: URL?` (comentário "record stream") em `KSOptions`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:260-262` — ao abrir o stream, se `options.outputURL` estiver setado, chama `startRecord(url:)` automaticamente.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:271-326` — `startRecord(url:)`: cria `outputFormatCtx` via `avformat_alloc_output_context2`, mapeia streams de áudio/vídeo/legenda do `formatCtx` de entrada para o de saída (`streamMapping`), copia `codecpar`, ajusta `codec_tag` para HEVC, abre `avio_open` e escreve o header (`avformat_write_header`).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:20-22` — estado privado: `outputFormatCtx`, `outputPacket`, `streamMapping`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:531-542` — no loop de leitura de pacotes, cada pacote de entrada é remapeado (`av_packet_ref`, `av_packet_rescale_ts`) e escrito no arquivo de saída via `av_interleaved_write_frame`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:672-676` (`stopRecord()`) — escreve o trailer (`av_write_trailer`) e libera `outputPacket`/`outputFormatCtx`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:631-632` — `stopRecord()` também é chamado no `deinit`/encerramento do item.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:579-587` — API pública exposta: `KSMEPlayer.startRecord(url:)` e `KSMEPlayer.stoptRecord()` (nome com typo "stopt"), delegando para `playerItem`.
- `Demo/SwiftUI/Shared/MovieModel.swift:289` e `Demo/demo-iOS/demo-iOS/AppDelegate.swift:120` — uso real no app de demonstração: `options.outputURL = moviesDirectory?.appendingPathComponent("recording.mov")`.

## Como funciona

A feature grava (remuxa) o stream de entrada em um arquivo de saída (ex.: `.mov`/`.mp4`) enquanto ele é reproduzido, usando o backend FFmpeg do `KSMEPlayer` (não se aplica ao backend `KSAVPlayer`/AVPlayer nativo, que não tem equivalente).

Fluxo:
1. O app seta `KSOptions.outputURL` antes de tocar o stream (visto no demo), ou chama diretamente `KSMEPlayer.startRecord(url:)` durante a reprodução.
2. `MEPlayerItem.startRecord(url:)` cria um `AVFormatContext` de saída com `avformat_alloc_output_context2`, percorre os streams do `AVFormatContext` de entrada, cria streams espelhados de áudio/vídeo/legenda no contexto de saída via `avformat_new_stream` + `avcodec_parameters_copy`, ajusta `codec_tag` (tratamento especial para HEVC/mp4/mov) e escreve o header do arquivo de saída.
3. Durante o loop principal de leitura de pacotes (`av_read_frame` em outro ponto do arquivo), cada pacote lido é também referenciado num `outputPacket`, tem seu índice de stream remapeado, tem seu timestamp reescalado (`av_packet_rescale_ts`) para o timebase do stream de saída, e é escrito com `av_interleaved_write_frame` — ou seja, é um remux em tempo real, pacote a pacote, sem re-encode.
4. Ao parar (`stopRecord()`, chamado explicitamente via `KSMEPlayer.stoptRecord()` ou implicitamente ao fechar o item), o trailer é escrito (`av_write_trailer`) e os recursos FFmpeg liberados.

Fim-a-fim: existe um caminho completo — opção pública → início automático ou manual → escrita de pacotes durante playback → finalização/trailer — e é exercitado nos dois apps de demo do próprio repositório (iOS SwiftUI e AppDelegate), o que indica que a funcionalidade é usada e não apenas um esqueleto morto.

## O que falta

Nada estrutural: o pipeline de remux existe e é usado em produção pelo próprio demo. Pontos de atenção (não bloqueiam o status "presente", mas relevantes para quem for expor isso no StreamHub):

- API assimétrica: `startRecord`/`stopRecord` só existem em `KSMEPlayer` (FFmpeg), não em `KSAVPlayer` nem no protocolo comum `MediaPlayerProtocol` — não há um método unificado de gravação no protocolo público do player.
- Não há tratamento de erro synchronous devolvido ao chamador (`startRecord` apenas loga via `KSLog` em caso de falha, sem propagar `Result`/`throws`); quem integrar precisa monitorar logs.
- Typo na API pública (`stoptRecord`), herdado do upstream — não é um bug funcional, apenas nomenclatura.
- Não há suporte a pausar/retomar gravação, nem a múltiplos formatos de saída além do que `avformat_alloc_output_context2` infere pela extensão do arquivo.
