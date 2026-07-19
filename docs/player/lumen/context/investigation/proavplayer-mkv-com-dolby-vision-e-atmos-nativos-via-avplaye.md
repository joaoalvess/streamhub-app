# ProAVPlayer: MKV com Dolby Vision e Atmos nativos via AVPlayer

## Status

**Ausente**

## Evidência

- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:81` — `urlAsset` é um `AVURLAsset` puro.
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:216` e `:451` — `urlAsset = AVURLAsset(url: url, options: options.avOptions)`: a URL do arquivo/stream (incluindo `.mkv`) é passada diretamente ao `AVURLAsset`, sem qualquer etapa de remux, transcodificação ou geração de HLS local.
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:421` — `AVPlayerItem(asset: self.urlAsset)` monta o item direto sobre o asset original.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:144-157` — `avOptions` só contém chaves de HTTP headers (`AVURLAssetHTTPHeaderFieldsKey`) e cookies (`AVURLAssetHTTPCookiesKey`); nenhuma opção de remux/output.
- Busca em todo o repositório (`rg -il "dolby|atmos|remux|hls|m3u8|avassetwriter|avassetexportsession"` em arquivos `.swift`) não retornou nenhum resultado — não existe nenhuma menção a Dolby Vision, Atmos, remux, HLS, `.m3u8`, `AVAssetWriter` ou `AVAssetExportSession` em nenhum arquivo Swift do projeto.
- `KSAVPlayer` (motor "nativo" baseado em `AVPlayer`) coexiste no repo com o motor `MEPlayer` (FFmpeg), mas os dois são exclusivos entre si (seleção por `KSOptions`/`KSPlayerLayer`) — não há nenhuma ponte que pegue um MKV, remuxe para um contêiner HLS/fMP4 local e sirva ao `AVPlayer` para aproveitar decodificação nativa de Dolby Vision/Atmos por hardware.

## O que falta

Toda a "joia da coroa" descrita — pipeline de remux local MKV → HLS (ou fMP4/CMAF) consumido pelo `AVPlayer` — inexiste. Para implementar do zero seria necessário construir, essencialmente, um subsistema novo:

1. **Camada de remux**: um componente que leia o MKV via demuxer (o próprio FFmpeg já embarcado em `Sources/KSPlayer/MEPlayer` poderia ser reaproveitado só para demux, sem decodificar) e escreva os streams de vídeo/áudio (copy, sem reencode) num contêiner que o `AVPlayer` entenda nativamente — tipicamente segmentos `.ts`/`.mp4` + playlist `.m3u8`, ou um único `.mp4`/`.mov` com `AVAssetWriter`.
2. **Servidor/loop local**: algo como um mini HTTP server (ou geração incremental de arquivos em disco) para servir o `.m3u8`/segmentos ao `AVURLAsset` conforme o remux avança (streaming progressivo), já que o remux de um arquivo grande não pode bloquear até o fim antes de iniciar playback.
3. **Passagem de metadados de trilha**: preservar track de vídeo Dolby Vision (perfis 5/7/8, incluindo RPU) e de áudio Atmos (E-AC-3 JOC) durante o remux sem reencode, o que exige mapeamento cuidadoso de caixas/atoms (`dvcC`/`dvvC`, `ec-3`) — não há nenhum código no repo que trate esses formatos (nenhuma menção a `dvcC`, `dvvC`, `dvhe`, `dvh1`, `eac3`, `ec-3`, `joc` em arquivos Swift).
4. **Integração em `KSOptions`/`KSAVPlayer`**: um novo flag (ex. `KSOptions.enableMKVRemux` ou similar) que, ao detectar contêiner MKV, desviasse o fluxo de `AVURLAsset(url:)` direto para passar primeiro pelo remuxer e só então montar o `AVPlayerItem` sobre a saída remuxada.
5. **Gestão de arquivos temporários**: limpeza de cache de segmentos/arquivos gerados, e lógica de "seek" que force regeração ou pulo de segmentos ainda não remuxados.

Nenhum desses componentes (remuxer, servidor local, mapeamento de metadados DV/Atmos, flag de opção, cache de segmentos) existe hoje no código-fonte GPL do fork.
