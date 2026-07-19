## Status

ausente

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:20-22` — `preferredForwardBufferDuration` (padrão 3s) e `maxBufferDuration` (padrão 30s, linha 464/466), únicos parâmetros de "buffer".
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:705-708` — controle de leitura de pacotes baseado em `loadingState.loadedTime` vs `maxBufferDuration`, tudo mantido em filas de pacotes/frames em memória (não em arquivo).
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:73-75,281` — repassa `preferredForwardBufferDuration` para `AVPlayerItem.preferredForwardBufferDuration` (buffer nativo do AVPlayer, também em memória/gerido pelo SO, não persistido em disco pela app).
- `Sources/KSPlayer/Core/Utility.swift:419-427` — único uso de `URLSession.downloadTask` no repo; comentário no código diz "下载的临时文件要马上就用。不然可能会马上被清空" (o arquivo temporário baixado deve ser usado imediatamente, senão pode ser limpo), usado para baixar um arquivo único (ex.: playlist/legenda), não para pré-cache de stream de vídeo em disco.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift` — único arquivo fora do trio acima com match para termos de cache/preload, mas trata de cache de parsing/render de legendas, não de dados de mídia.
- Busca ampla por `cache`, `diskcache`, `cachePolicy`, `urlcache`, `cachePath`, `readAhead`, `preload` em todo `Sources/KSPlayer` não retornou nenhuma estrutura de persistência de dados de stream em disco (SSD/HD) — apenas o cache de contexto do FFmpeg `sws_getCachedContext` em `Sources/KSPlayer/MEPlayer/Resample.swift:44,115`, que é cache de conversão de pixel format/scaling, não relacionado a I/O em disco.

## O que falta

Não há nenhuma base ou esboço de "precache para disco". Para implementar do zero seria necessário:

1. Um componente novo de disk cache (ex.: `KSPlayer/Cache/DiskPacketCache.swift` ou similar) que escreva segmentos/pacotes decodificados ou o stream bruto em arquivos temporários no filesystem, com política de tamanho máximo e expiração — nada disso existe hoje.
2. Extender `KSOptions` (`Sources/KSPlayer/AVPlayer/KSOptions.swift`) com flags como `precacheDataToDisk: Bool` e `precacheSizeLimit`, análogas às já existentes `preferredForwardBufferDuration`/`maxBufferDuration`, mas essas hoje só controlam buffer em memória.
3. No pipeline do MEPlayer (`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`, responsável por ler pacotes via FFmpeg e gerenciar `loadingState`), inserir um estágio de gravação em disco em paralelo à fila de pacotes em memória, e leitura desse cache em vez da rede quando disponível (ex.: para permitir seek instantâneo em conteúdo já baixado ou reprodução após perda de rede).
4. Para o caminho `KSAVPlayer` (AVPlayer nativo, `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift`), a Apple não expõe cache em disco configurável diretamente — seria necessário um `AVAssetResourceLoaderDelegate` customizado que intercepte requisições HTTP e sirva de um cache local em disco (esse delegate não existe no repo).
5. Nenhum branch de plataforma (iOS/tvOS/macOS) trata isso de forma diferenciada, porque a feature simplesmente não está implementada em nenhum lugar.
