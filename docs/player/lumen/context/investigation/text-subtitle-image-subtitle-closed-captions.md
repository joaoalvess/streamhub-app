# Text subtitle / Image subtitle / Closed Captions

## Status

Presente. O fork GPL implementa a pipeline completa: legendas de texto (SRT, WebVTT, ASS/SSA embutidas em contêiner via FFmpeg), legendas de imagem (bitmap, ex.: DVD/DVB subtitles via `SUBTITLE_BITMAP`) e Closed Captions CEA-608 extraídas de side data H.264/HEVC. Decodificação, parsing e renderização (texto e imagem) existem de ponta a ponta.

## Evidência

- `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:37-75` — `decodeFrame` chama `avcodec_decode_subtitle2` (FFmpeg) e monta `SubtitleFrame`/`SubtitlePart` a partir do `AVSubtitle` retornado.
- `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:89-135` — função `text(subtitle:)` trata três casos por `rect`: `rect.text` (texto puro), `rect.ass` (linha ASS, parseada via `AssParse`), e `rect.type == SUBTITLE_BITMAP` (legenda de imagem, convertida com `VideoSwresample`/`scale.transfer` e combinada em `CGImage.combine(images:)` → `UIImage`).
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:39-247` — `AssParse`: parser completo de ASS/SSA (estilos, cores, fontes, posição, tags inline `{\...}`).
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:332-377` — `VTTParse`: parser WebVTT.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:379-422` — `SrtParse`: parser SRT.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:20` — `KSOptions.subtitleParses = [AssParse(), VTTParse(), SrtParse()]` (lista extensível de parsers).
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:14-19` — `SubtitlePart` tem tanto `attributedString` (texto) quanto `image: UIImage?` (bitmap), confirmando suporte a ambos os tipos no modelo.
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:43-86` — extração de Closed Captions: detecta `FF_CODEC_PROPERTY_CLOSED_CAPTIONS` no `AVCodecContext`, cria uma `FFmpegAssetTrack` sintética com `codec_id = AV_CODEC_ID_EIA_608`, extrai o side data `AV_PKT_DATA_A53_CC` do pacote de vídeo e o encaminha como pacote de legenda (`subtitle.putPacket`) para a track de CC.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:460` — exposição de `closedCaptionsTrack` como uma track selecionável de legenda pelo player.
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:40` — campo `closedCaptionsTrack` no modelo de track.
- `Sources/KSPlayer/Video/VideoPlayerView.swift:64,266-270` — renderização real: `subtitleBackView.image = part.image` (legenda de imagem/bitmap) e (via `subtitleLabel`, linhas 685-688) o texto/atributos com fonte, cor e fundo configuráveis por `SubtitleModel.textFont/textColor/textBackgroundColor`.
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift` (404 linhas) — fontes de dados de legenda (arquivos externos, embutidas), suportando adicionar legendas fora do contêiner.
- `Sources/KSPlayer/MEPlayer/EmbedDataSouce.swift` — fonte de dados para legendas embutidas no próprio arquivo/stream.

## Como funciona

1. Durante a demuxagem, o FFmpeg identifica uma subtitle stream (texto ou bitmap, ex.: SRT/ASS/mov_text/DVB/DVD subs) ou, para vídeo H.264/HEVC com side data A53 CC, `FFmpegDecode.swift` sintetiza uma track adicional de CC (`AV_CODEC_ID_EIA_608`).
2. `SubtitleDecode` roda `avcodec_decode_subtitle2` por pacote e converte o `AVSubtitle` resultante em um ou mais `SubtitlePart`: texto simples é envolvido em `NSAttributedString`; texto ASS é reparseado por `AssParse` (aplica estilos/posições); bitmap é convertido via swresample para `CGImage`/`UIImage`.
3. Para legendas externas em arquivo (SRT/VTT/ASS soltos), `KSParseProtocol`/`SubtitleDataSouce` fazem o parse de forma independente do FFmpeg, usando os mesmos parsers (`AssParse`, `VTTParse`, `SrtParse`), plugáveis via `KSOptions.subtitleParses`.
4. Na camada de exibição (`VideoPlayerView`), cada frame de legenda ativo é aplicado: se tiver `image`, mostra num `UIImageView` (`subtitleBackView`); se tiver `attributedString`, mostra num `UILabel` com fonte/cor/fundo configuráveis via `SubtitleModel`.
5. Closed captions aparecem ao usuário como mais uma "track" de legenda selecionável (mesma UI de seleção de legendas), pois `closedCaptionsTrack` é exposto ao lado das demais subtitle tracks em `KSMEPlayer`.

## O que falta

Não aplicável — a feature está presente. Não foram encontradas lacunas estruturais nesta pesquisa (não foi feito teste de reprodução real/end-to-end em dispositivo, apenas verificação estática de código).
