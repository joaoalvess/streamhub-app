# Audio Passthrough Output by Wi-Fi

## Status
Ausente

## Evidência
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:345-354` — codecs AC3/EAC3 são reconhecidos apenas como `FourCharCode` para fins de identificação (`.ac3`, `.enhancedAC3`), sem qualquer caminho de bitstream/passthrough.
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift` — todo áudio passa pelo decoder FFmpeg (`avcodec_send_packet`/`avcodec_receive_frame`), produzindo PCM; não há branch que evite a decodificação para enviar o stream comprimido original ao hardware/rede.
- `Sources/KSPlayer/MEPlayer/AudioRendererPlayer.swift:53-59`, `AudioUnitPlayer.swift:53-71`, `AudioGraphPlayer.swift:151-161`, `AudioEnginePlayer.swift:158-168` — os quatro backends de saída de áudio (`AVSampleBufferAudioRenderer`, AudioUnit, AudioGraph/AVAudioEngine) todos operam sobre PCM (`setPreferredOutputNumberOfChannels`, `AVAudioFormat`), sem opção de format comprimido (não usam `kAudioFormatFlagIsNonInterleaved`+AC3/`kAudioFormatAC3` nem `AVAudioSession.setPreferredIOBufferDuration` para bitstream, nem `AudioStreamBasicDescription` com `mFormatID = kAudioFormatAC3/kAudioFormatEnhancedAC3`).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:496-551` — toda a configuração de `AVAudioSession` trata apenas de canais (`preferredOutputNumberOfChannels`), spatial audio e categoria/policy de reprodução; nenhuma menção a bitstream, SPDIF, HDMI ARC ou "compressed audio".
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:75-142` — `allowsExternalPlayback`/`usesExternalPlaybackWhileExternalScreenIsActive` e `isExternalPlaybackActive` (linha 313, hardcoded `false`) tratam apenas de espelhamento/AirPlay de vídeo (`AVPlayer`-like semantics), não de roteamento de áudio comprimido sobre a rede.
- `Sources/KSPlayer/SwiftUI/AirPlayView.swift` e `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:322-347` (`AirplayStatusView`) — apenas um botão de rota AirPlay (`AVRoutePickerView`) e um indicador visual "AirPlay 投放中"; nenhuma lógica de negociação de formato de áudio com o receptor.
- Busca ampla por `passthrough|spdif|bitstream|wifi|airplay.*audio` em todo `Sources/KSPlayer` não retornou nenhuma outra ocorrência relevante além das listadas acima.

## O que falta
Não há nenhuma base a apontar como "esboço parcial": a arquitetura atual do fork sempre decodifica áudio para PCM antes de qualquer saída (local ou AirPlay), e delega o roteamento de rede inteiramente ao `AVRoutePickerView`/`AVAudioSession`, que não expõe passthrough de bitstream comprimido para destinos Wi-Fi.

Uma implementação real precisaria, no mínimo:
- Um novo caminho no `MEPlayerItem`/`FFmpegDecode` (`Sources/KSPlayer/MEPlayer/FFmpegDecode.swift`, `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`) que, para codecs como AC3/EAC3/DTS/TrueHD, encapsule o pacote comprimido original (via bitstream filter FFmpeg, ex. `dca_core`/`eac3_core` ou empacotamento IEC61937) em vez de decodificar para PCM.
- Um backend de saída alternativo (paralelo a `AudioRendererPlayer`/`AudioUnitPlayer`/`AudioGraphPlayer`/`AudioEnginePlayer` em `Sources/KSPlayer/MEPlayer/`) configurando `AudioStreamBasicDescription` com `mFormatID` comprimido (`kAudioFormatAC3`, `kAudioFormat60958AC3` etc.) e uma `AVAudioSession` em modo bitstream.
- Descoberta/negociação com o destino de rede (AirPlay 2 speaker/receiver) sobre quais formatos comprimidos ele aceita — isto depende de APIs privadas/entitlements da Apple não expostas via `AVRoutePickerView`/`AVAudioSession` pública, e não há nenhum hook em `KSOptions.swift` ou `KSMEPlayer.swift` preparado para isso.
- Flags novas em `KSOptions` (inexistentes hoje) para habilitar/desabilitar passthrough por tipo de codec, análogas às que o Infuse/Plex expõem em suas configurações de áudio.

Não foi encontrada nenhuma flag, comentário "TODO", ou branch de plataforma relacionado a esse recurso em todo o pacote.

## Verificação
Conclusão confirmada por amostragem direta do código: status "Ausente" está correto. Os quatro backends de áudio (`AudioRendererPlayer`, `AudioUnitPlayer`, `AudioGraphPlayer`, `AudioEnginePlayer`) são de fato PCM-only (`AVAudioFormat`/`AudioStreamBasicDescription` sem `mFormatID` comprimido), `KSOptions.setAudioSession`/`isSpatialAudioEnabled`/`outputNumberOfChannels` (linhas 494-554) só tratam canais e spatial audio, `KSMEPlayer.isExternalPlaybackActive` (linha 313) é hardcoded `false`, e `AirPlayView.swift` é só um `AVRoutePickerView` sem negociação de formato. A busca ampla por `passthrough|spdif|bitstream|...` só retorna o hit não relacionado `AVFFmpegExtension.swift:499-500` (`bitstreamFilterNotFound`, um erro genérico de FFmpeg BSF, sem relação com áudio comprimido).

Duas correções pontuais de citação de linha (não afetam a conclusão):
- `AudioRendererPlayer.swift` — o método `prepare(audioFormat:)` com `setPreferredOutputNumberOfChannels` está nas linhas 57-62, não 53-59 (53-55 ainda é o `init`).
- `AudioUnitPlayer.swift` — `prepare(audioFormat:)` vai de 65 a 95 (não 53-71, que cobre majoritariamente o fim do `init`); a linha mais relevante como evidência (`AudioStreamBasicDescription` via `kAudioUnitProperty_StreamFormat`, sem format id comprimido) é 75-80.
