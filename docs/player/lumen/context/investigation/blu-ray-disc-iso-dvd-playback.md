## Status

Ausente.

## Evidência

Buscas por termos relacionados a disco óptico não encontraram nenhuma implementação real:

- `rg -il 'bluray|blu-ray|\bdvd\b|\biso\b|libdvdread|libbluray|BDMV|disc'` retornou apenas 3 arquivos, e em todos os 3 os únicos "hits" são falsos positivos da substring `disc` dentro da palavra `discard` (nada relacionado a disco óptico):
  - Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:267-274 (`AVDISCARD_DEFAULT`/`AVDISCARD_ALL`, controla habilitação de streams no demuxer)
  - Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:234-337 (`AVFMT_TS_DISCONT`, `AVDISCARD_ALL`)
  - Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:68 (`AV_PKT_FLAG_DISCARD`)
- Busca por estruturas específicas de disco (`VIDEO_TS`, `AUDIO_TS`, `MPLS`, `M2TS`, `VOB`, `iso9660`, `udf`) não retornou nenhuma ocorrência em todo o projeto.
- Não existem tipos, protocolos ou opções em `KSOptions` (Sources/KSPlayer/Core) para seleção de título/playlist de disco, menus de DVD/Blu-ray, ou parsing de estrutura de diretórios `BDMV`/`VIDEO_TS`.
- Não há dependência do libbluray ou libdvdread/libdvdnav no projeto (ausentes do FFmpeg vendorizado e dos módulos Swift).

## O que falta

Uma implementação do zero exigiria, no mínimo:

1. **Parsing da estrutura de disco/ISO**: montar/ler um `.iso` (via loopback ou parser UDF/ISO9660 embutido) ou uma pasta `VIDEO_TS`/`BDMV` para localizar os títulos (`VOB`/`M2TS`) e a ordem de reprodução (para DVD: IFO; para Blu-ray: `.mpls`/clip info). Isso não existe hoje em nenhum arquivo do pacote `KSPlayer`.
2. **Integração com libdvdnav/libdvdread e libbluray**: essas libs (que tratam navegação de menu, seleção de ângulo/título, criptografia CSS/AACS) não estão vendorizadas nem referenciadas em nenhum `Package.swift`/script de build do FFmpeg deste fork.
3. **Um novo `AssetTrack`/demuxer path** em `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` e `FFmpegAssetTrack.swift` capaz de abrir múltiplos arquivos concatenados (VOB/M2TS) como uma única timeline lógica, hoje o pipeline assume um único `AVFormatContext` aberto diretamente pelo `avformat_open_input` sobre uma URL/arquivo único.
4. **UI de seleção de título/capítulo/menu de disco**: os menus existentes em `Sources/KSPlayer/Video/KSMenu.swift` e `KSVideoPlayerView.swift` cobrem apenas trilhas de áudio/legenda/velocidade, não títulos de DVD/BD nem navegação de menu interativo.
5. Nenhuma flag em `KSOptions` (Sources/KSPlayer/Core/KSOptions.swift) sinaliza ou prepara este caminho — a opção mais próxima é a leitura de arquivos comuns via FFmpeg (mp4/mkv/etc.), sem noção de "disco".

Em resumo: não há esboço, hook ou flag parcial — a feature está totalmente ausente do código GPL deste fork, consistente com ser exclusiva da versão paga do KSPlayer.
