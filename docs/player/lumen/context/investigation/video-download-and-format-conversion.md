## Status

Parcial

Existe uma feature real de **gravação/remux em tempo real** (grava o que está sendo reproduzido para um arquivo local, remuxando streams sem re-encode), mas não existe nenhum "download" de mídia remota independente da reprodução, nem "conversão de formato" no sentido de transcodificação de codec (mudar H.265→H.264, mudar bitrate, etc.). O que existe cobre só um subconjunto bem mais restrito do que a feature paga "Video download and format conversion" do KSPlayer/Infuse.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:42` — `public var outputURL: URL?` (flag de configuração que liga a gravação).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:260-262` — ao abrir o item, se `options.outputURL` estiver setado, chama `startRecord(url:)`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:271-326` (`startRecord`) — usa FFmpeg puro: `avformat_alloc_output_context2`, cria `AVStream` de saída por `avcodec_parameters_copy` (copia os parâmetros do codec de entrada, ou seja, **sem re-encode**), ajusta `codec_tag` para HEVC e força `AV_CODEC_ID_MOV_TEXT` para legendas em containers mp4/mov, abre `avio_open` e escreve o header (`avformat_write_header`).
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:520-544` (dentro de `reading()`) — a cada pacote lido do stream de entrada (`av_read_frame`), se há `outputFormatCtx` ativo, o pacote é copiado (`av_packet_ref`), tem o timestamp reescalado (`av_packet_rescale_ts`) e é escrito via `av_interleaved_write_frame` — isso é o laço de gravação em paralelo à decodificação/exibição.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:632`, `672` (`stopRecord`) — fecha o output ao fechar o player.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:581-586` — expõe `startRecord(url:)` / `stopRecord()` publicamente no player de alto nível.
- `Demo/demo-iOS/demo-iOS/AppDelegate.swift:120` e `Demo/SwiftUI/Shared/MovieModel.swift:289` — único uso real no repo: seta `options.outputURL` para `recording.mov` no diretório de Movies, confirmando que a feature é pensada como "gravar a sessão de playback atual", não "baixar um título remoto para offline".
- `Sources/KSPlayer/Core/Utility.swift:215-256` — funcionalidade separada e não relacionada a "download": `createExportSession`/`exportMp4` usa `AVAssetExportSession` da AVFoundation para **cortar um trecho (trim)** de um `AVAsset` e exportar para `.mp4`. Só funciona com assets do AVFoundation (não com o pipeline FFmpeg/MEPlayer que toca a maior parte dos formatos que o KSPlayer GPL suporta), e não há chamador desse código em nenhum lugar do repo (nem no Demo, nem no restante de `Sources/`) — código morto/utilitário não integrado.
- Não há nenhuma referência a filas de download em background, gerenciamento de downloads persistentes, seleção de qualidade/formato de saída pelo usuário, nem a transcodificação de codec (`avcodec_encode_*`, `swscale`/re-encode de vídeo, `swr_convert` para re-encode de áudio) usada como saída — busca confirmada por `rg -n "avcodec_send_frame|avcodec_encode"` não retornou nenhum uso de encoder no MEPlayer (apenas decoders).

## Como funciona (o que existe)

1. O app define `options.outputURL` antes de tocar a mídia.
2. Ao abrir o formato de entrada, `MEPlayerItem.startRecord(url:)` cria um `AVFormatContext` de saída cujo container é inferido pela extensão do arquivo (`avformat_alloc_output_context2`), e para cada stream de áudio/vídeo/legenda do input cria um stream espelho na saída copiando os `codecpar` (mesmo codec, sem recodificar).
3. Durante a leitura normal do playback (`reading()`), cada pacote demuxado do input é também escrito no `outputFormatCtx` via `av_interleaved_write_frame`, com o timestamp reescalado para o timebase de saída.
4. `stopRecord()` fecha o contexto de saída quando o player fecha o item.

Isto é essencialmente um **remux ao vivo** (grava o stream bruto tocado, no mesmo codec, para um arquivo local) — equivalente a "gravar a sessão" — não um "baixar título e converter formato" desacoplado da reprodução.

## O que falta

Para chegar à feature completa "video download and format conversion" (como no KSPlayer pago / Infuse: baixar um arquivo remoto para uso offline, com opção de conversão real de formato/codec/bitrate), faltaria:

- **Download desacoplado da reprodução**: hoje a gravação só ocorre enquanto o item está sendo lido/tocado (`reading()` chama `av_read_frame` no loop de playback). Não existe um modo "baixar em background sem decodificar/exibir" — precisaria de um path que abra o formatCtx de entrada e faça só o loop de leitura+remux sem alimentar as filas de decodificação (`videoTrack?.putPacket`, `audioTrack?.putPacket`), possivelmente rodando em uma `Task`/fila dedicada independente da UI de playback.
- **Gerenciamento de downloads**: fila, progresso, pausa/retomada, persistência entre sessões do app — nada disso existe; `startRecord`/`stopRecord` são chamadas diretas e síncronas ao ciclo de vida do `MEPlayerItem`, sem noção de "job" de download.
- **Conversão real de formato/codec**: hoje `startRecord` só faz `avcodec_parameters_copy` (remux, mesmo codec). Uma transcodificação real precisaria adicionar um pipeline de encode: decodificar (já existe via `FFmpegDecode.swift`/`VideoToolboxDecode.swift`) e então codificar para o codec/formato alvo (chamadas a `avcodec_find_encoder`, `avcodec_open2` em modo encode, `avcodec_send_frame`/`avcodec_receive_packet`), que não existem em nenhum lugar do código atual (nenhum uso de encoder, apenas decoders em todo `Sources/KSPlayer/MEPlayer/`).
- **Seleção de qualidade/formato pelo usuário e UI de progresso**: `KSOptions.outputURL` é a única flag de configuração; não há tipos como `DownloadTask`, `ConversionProfile`/`ExportPreset` ou APIs de progresso de download expostas em `MediaPlayerProtocol.swift`/`KSMEPlayer.swift`.
- O código de `Utility.swift` (`exportMp4`/`createExportSession`) seria o candidato mais próximo de um "export com transcodificação" pois delega para `AVAssetExportSession`, mas está desconectado do pipeline principal (FFmpeg/MEPlayer) e sem nenhum chamador — seria necessário decidir se a estratégia de conversão usa AVFoundation (limitado a formatos que o `AVAsset` entende nativamente) ou construir um encoder FFmpeg equivalente ao decoder já existente.
