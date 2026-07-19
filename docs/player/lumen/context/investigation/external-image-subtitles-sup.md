## Status

Ausente (para o caso específico de legendas de imagem **externas**, ex.: um arquivo `.sup` solto ao lado do vídeo). O que existe no fork é o decode de legendas de imagem **embutidas** no container (PGS/DVB/DVD sub dentro do MKV/MP4), que é uma feature diferente e já funciona ponta a ponta.

## Evidência

- `Sources/KSPlayer/Core/Utility.swift:380-382` — `URL.isSubtitle` só reconhece `["ass", "srt", "ssa", "vtt"]`. Um `.sup` ao lado do vídeo nunca é descoberto pelo `DirectorySubtitleDataSouce`.
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:143-158` — `DirectorySubtitleDataSouce.searchSubtitle` lista o diretório do vídeo e filtra por `.isSubtitle`; não há tratamento especial para `.sup`/PGS.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:19-21` — `KSOptions.subtitleParses = [AssParse(), VTTParse(), SrtParse()]`: os três parsers são textuais (scanner de string). Não existe um parser binário para o formato SUP (PGS) nem qualquer `ImageSubtitleParse`.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:170-215` (parse via `KSOptions.subtitleParses.first { $0.canParse(...) }`) — o pipeline de legenda externa (`KSSubtitle`/`URLSubtitleInfo`) assume texto (`Scanner(string:)`), incompatível com um arquivo binário SUP.
- Em contraste, o caminho **interno** (embutido no container) existe e funciona:
  - `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:257` — `isImageSubtitle` reconhece `AV_CODEC_ID_DVD_SUBTITLE`, `AV_CODEC_ID_DVB_SUBTITLE`, `AV_CODEC_ID_DVB_TELETEXT`, `AV_CODEC_ID_HDMV_PGS_SUBTITLE` a partir da track do container.
  - `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:144-154` — seleção de track de legenda de imagem é condicionada a `options.isSeekImageSubtitle`.
  - `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:16-107` — decodifica via `avcodec_decode_subtitle2` (linha 42), converte os `AVSubtitleRect` em `CGImage` (bitmap) e monta `SubtitlePart` com a imagem (função `text(subtitle:)`, linha 89 em diante).
  - Isso cobre apenas trilhas de legenda **dentro do arquivo de mídia sendo reproduzido** (ex.: PGS de um MKV), nunca um arquivo `.sup` externo carregado ao lado do vídeo como se faz com `.srt`/`.ass`.

## Como funciona (caminho existente, mas não é a feature pedida)

Quando o container do vídeo já traz uma trilha de legenda de imagem (PGS/DVD/DVB), o FFmpeg demuxer expõe essa trilha, `FFmpegAssetTrack` marca `isImageSubtitle = true`, e `SubtitleDecode` chama `avcodec_decode_subtitle2` a cada pacote, convertendo os retângulos bitmap (`AVSubtitleRect`) em `CGImage` via `VideoSwresample`/scale para `AV_PIX_FMT_ARGB`, empacotando em `SubtitlePart`/`SubtitleFrame` que seguem o mesmo pipeline de exibição das legendas de texto.

## O que falta

Para suportar SUP externo (arquivo `.sup` PGS solto, do jeito que o Infuse/KSPlayer pago fazem), seria necessário:

1. **Descoberta do arquivo**: estender `URL.isSubtitle` (`Sources/KSPlayer/Core/Utility.swift:380`) para incluir `"sup"`, e ajustar `DirectorySubtitleDataSouce`/`URLSubtitleInfo` para não tentarem tratá-lo como texto.
2. **Parser binário**: criar algo como `SupParse: KSParseProtocol` — ou um protocolo irmão específico para legendas de imagem, já que `KSParseProtocol.parsePart` opera sobre `Scanner` (texto) e não serve para o formato binário PGS. Precisaria implementar o parsing do formato Presentation Graphic Stream (PCS/WDS/PDS/ODS segments, RLE de bitmap) — não há nada reaproveitável hoje além da lógica de decodificação de `AVSubtitleRect → CGImage` já existente em `SubtitleDecode.swift:89-130`, que poderia ser reusada se o `.sup` for demuxado via FFmpeg (abrindo o arquivo `.sup` como um "input" próprio com `avformat_open_input`, decodificando com `AV_CODEC_ID_HDMV_PGS_SUBTITLE`) em vez de escrever um parser do zero em Swift.
3. **Sincronização com o modelo de legenda externa**: `URLSubtitleInfo`/`KSSubtitle` (`Sources/KSPlayer/Subtitle/KSSubtitle.swift:150-231`) assumem hoje que o `parts` vem de texto lido do arquivo inteiro; seria preciso um subtipo que abra um `AVFormatContext` próprio para o `.sup` e alimente `SubtitlePart` com imagens, reaproveitando a infraestrutura de exibição de imagem que já existe para o caso embutido.
4. Nenhum destes três pontos tem hoje sequer um stub, TODO ou flag em `KSOptions` apontando para essa direção — a única flag relacionada (`isSeekImageSubtitle`) é sobre seek em trilhas de imagem já embutidas no container, não sobre carregar arquivos externos.
