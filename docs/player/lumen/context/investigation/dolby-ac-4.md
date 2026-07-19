## Status

Ausente.

## Evidência

- Busca por `ac4|ac-4` em todo o repositório (`rg -i "ac4|ac-4|dolby"`) não retorna nenhuma ocorrência real em código Swift — apenas hashes hexadecimais de `project.pbxproj` (falsos positivos, ex.: `AC458DE6...`, `95EAAC4D...`) e as referências a Dolby Vision (vídeo).
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:343-368` — switch que mapeia `AV_CODEC_ID_*` do FFmpeg para `CMFormatDescription.MediaSubType` (usado no caminho de decodificação/passthrough de áudio). Trata explicitamente:
  - `AV_CODEC_ID_AC3` → `.ac3` (linha 345-346)
  - `AV_CODEC_ID_EAC3` → `.enhancedAC3` (linha 353-354)
  - Não existe `case AV_CODEC_ID_AC4`. O FFmpeg tem esse codec ID desde 4.x; se um stream vier com AC-4, cai no `default` do switch (não mapeado para nenhum `MediaSubType` conhecido).
- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:49-133` e `Sources/KSPlayer/Core/Utility.swift:278-279` — todo o suporte "Dolby" existente no código é para **Dolby Vision** (metadado de vídeo HDR), sem qualquer relação com o codec de áudio AC-4.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:409` — comentário menciona TrueHD (outro codec de áudio Dolby) apenas como observação sobre FPS de sincronização de faixas, não como suporte funcional.

## O que falta

Não há nenhuma base/esboço para AC-4. Uma implementação começaria em:

1. **Mapeamento de codec**: adicionar `case AV_CODEC_ID_AC4:` em `AVFFmpegExtension.swift` (função que mapeia para `CMFormatDescription.MediaSubType`), definindo o subtype correto (`kAudioFormatAC4`/equivalente CoreAudio, se existir na versão do SDK usada) ou mantendo decodificação via FFmpeg software caso não haja suporte de hardware/AVFoundation.
2. **Decodificação**: verificar se a build do FFmpeg vendorizada (FFmpegKit/pods) foi compilada com `--enable-decoder=ac4` — sem isso, mesmo adicionando o case acima, o pacote nunca chegaria decodificado.
3. **Passthrough/bitstream**: caso o objetivo seja passthrough para um AVR via HDMI (como no Infuse), seria necessário expor a track AC-4 em `MediaPlayerProtocol.swift`/`KSOptions.swift` como opção de trilha de áudio selecionável, além de tratar compatibilidade com `AVSampleBufferAudioRenderer`/`AudioToolbox` para bitstreaming.
4. **KSOptions**: nenhuma flag relacionada a AC-4 existe em `KSOptions.swift` hoje — precisaria de uma opção de habilitar/priorizar essa trilha, similar ao que já existe para Dolby Vision em `KSOptions.swift:351`.
