## Status

Ausente.

## Evidência

- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:14` — `MEPlayerItem` guarda uma única `url: URL` (linha 15) e um único `formatCtx: UnsafeMutablePointer<AVFormatContext>?` (linha 19). A abertura do stream é feita com uma só chamada `avformat_open_input(&self.formatCtx, urlString, nil, &avOptions)` (linha 202) — não há segundo `formatCtx`/segunda URL para áudio.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:328` — `createCodec(formatCtx:)` itera `formatCtx.pointee.nb_streams` de um único container para extrair todas as tracks (áudio/vídeo/legenda); todas as tracks vêm da mesma origem demuxada.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:189` e `:268` — existe um array `urls = [URL]()` e `set(urls:options:)`, mas isso é lista de reprodução sequencial (troca de item ao avançar), não fontes simultâneas: `set(urls:)` apenas guarda o array e usa `urls.first` como `url` atual (linhas 268-277); o player em si (`init(url:...)`, linha 195) continua recebendo somente um `url` por vez.
- `Sources/KSPlayer/Core/Utility.swift:192` — único uso de `AVMutableComposition` combinando tracks de áudio e vídeo é `createComposition(beginTime:endTime:)`, uma função privada de corte/exportação (usada para gerar GIF/clipe), que insere tracks de áudio e vídeo do MESMO `AVAsset` de origem (`self` como asset) em um intervalo de tempo — não combina dois assets/URLs diferentes.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift` — nenhuma propriedade relacionada a URL de áudio externo (`rg` por `audioUrl`, `externalAudio`, `secondAudio`, `separate.*audio` não retornou nada em todo o pacote, exceto o próprio arquivo de `KSOptions` sem tais campos).
- Busca ampla por termos como `externalAudio`, `secondAudio`, `audioUrl`, `videoUrl`, `combine.*asset` em todos os `.swift` do projeto não encontrou nenhuma referência a carregar/sincronizar duas URLs (uma de vídeo, outra de áudio) para reprodução simultânea.

## O que falta

Não há nenhum esboço da feature. Uma implementação real precisaria, no mínimo:

1. **Modelo de entrada**: `KSPlayerItem` (`Sources/KSPlayer/Video/KSPlayerItem.swift:32`) e `KSOptions` teriam que ganhar um campo opcional tipo `secondaryURL: URL?` (ou `audioURL`/`videoURL` separados) para representar a segunda fonte.
2. **Camada FFmpeg (MEPlayer)**: `MEPlayerItem` (`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`) precisaria manter dois `AVFormatContext` (um por URL), dois `avformat_open_input`, demuxar cada um em paralelo, e sincronizar os `AVPacket`/PTS de ambos os contextos antes de entregar aos decoders de áudio e vídeo — hoje o pipeline inteiro (`createCodec`, leitura de pacotes, clock) assume um único `formatCtx`/uma única timeline.
3. **Camada AVPlayer (fallback)**: para o backend `KSAVPlayer` (`Sources/KSPlayer/AVPlayer/KSAVPlayer.swift`), o caminho natural seria montar um `AVMutableComposition` combinando a track de vídeo de um `AVURLAsset` com a track de áudio de outro `AVURLAsset` (usando o mesmo padrão de `insertTimeRange` já existente em `Utility.swift:192`, mas com dois assets de origem em vez de um) e alimentar isso a um `AVPlayerItem`.
4. **Sincronização de clock**: o clock mestre do player (buffer/PTS sync entre decodificadores de áudio e vídeo) precisaria ser estendido para tolerar drift entre dois streams de origens/containers diferentes, o que hoje não existe pois pressupõe origem única.

Nenhum desses pontos tem esboço, flag desligada ou TODO no código atual — é greenfield.
