## Status

**Ausente.** Existe apenas um ponto de extensão vazio (protocolo + array estático nunca populado). Não há nenhuma implementação de reconhecimento de fala, geração de legendas via IA nem tradução em tempo real no código GPL.

## Evidência

- `Sources/KSPlayer/Subtitle/AudioRecognize.swift:10-12` — protocolo `AudioRecognize: SubtitleInfo` com um único método `func append(frame: AudioFrame)`. Nenhum tipo do repositório conforma a esse protocolo (`rg -n "AudioRecognize"` só retorna a própria definição e o uso em `KSSubtitle.swift`).
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:290` — `public static var audioRecognizes = [any AudioRecognize]()`: array estático de `SubtitleModel`, inicializado vazio e nunca preenchido em nenhum lugar do código (`rg` não encontra `audioRecognizes.append` nem atribuições).
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:302` — `subtitleInfos.append(contentsOf: SubtitleModel.audioRecognizes)`: como o array está sempre vazio, essa linha nunca adiciona nada em runtime.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:850-856` — único ponto de consumo real: em `getAudioOutputRender()`, para cada frame de áudio decodificado, o código busca `SubtitleModel.audioRecognizes.first { $0.isEnabled }?.append(frame: frame)`. Ou seja, a arquitetura já prevê "encaminhar cada `AudioFrame` decodificado para um reconhecedor", mas como não existe nenhum objeto no array, essa chamada é sempre um no-op (`first` retorna `nil`).
- Busca por `SFSpeech`, `Speech.`, `CoreML`, `MLModel`, `Whisper`, `Translation`/`translate` (case-insensitive) em `Sources/KSPlayer` não retorna nenhum hit relevante — apenas ocorrências não relacionadas de `translatesAutoresizingMaskIntoConstraints` e `CGAffineTransform.translate`.

## O que falta

Tudo. O que existe é só o "cabo" de entrada de áudio (`append(frame:)` recebendo `AudioFrame` já decodificado pelo FFmpeg) e o slot de ativação (`audioRecognizes`, `isEnabled` vindo de `SubtitleInfo`). Para chegar a uma feature real de "legenda gerada por IA em tempo real, offline", seria necessário:

1. **Um tipo concreto conformando `AudioRecognize`**, ex. `SpeechRecognizeSubtitleInfo` ou similar, que:
   - Acumula os `AudioFrame` recebidos em `append(frame:)` (buffers de PCM) em um buffer/janela deslizante.
   - Alimenta um motor de reconhecimento de fala offline — no ecossistema Apple isso seria `SFSpeechRecognizer` com `requiresOnDeviceRecognition = true` (Speech framework, disponível em tvOS a partir de certa versão) ou um modelo Core ML (ex. Whisper convertido via whisper.cpp/coreml, ggml, ou llama.cpp bindings) — nenhuma dessas dependências existe hoje no `Package.swift`.
   - Produz `SubtitlePart`/cues com timestamp derivado do `AudioFrame.position`/`timebase` (o pipeline de legendas já usa esse tipo, ver `KSSubtitle.swift`).
2. **Registro do reconhecedor** em `SubtitleModel.audioRecognizes` (hoje nunca populado) e uma opção em `KSOptions` para habilitar/desabilitar (não existe nenhuma flag como `isAudioRecognizeEnabled` — `rg -n "isEnabled" AudioRecognize` mostra que a propriedade vem de `SubtitleInfo`, que já existe genericamente, mas nada no `KSOptions.swift` liga isso à UI).
3. **Tradução**: nada no código trata de tradução de texto (nem de legendas externas .srt já existentes nem das hipotéticas geradas por IA). Precisaria de uma segunda etapa (on-device translation, ex. `Translation` framework do iOS 17+/tvOS 17+, ou um modelo local) consumindo o texto gerado pelo reconhecedor.
4. **UI/seleção**: os componentes de UI de legenda (`PlayerToolBar.swift`, `VideoPlayerView.swift` — `srtButton`, `subtitleLabel`) tratam apenas de trilhas de legenda já existentes (embutidas ou baixadas); não há affordance para "gerar legenda com IA" nem para escolher idioma de tradução.
5. **Custo de processamento em tempo real**: como o hook já entrega cada `AudioFrame` individualmente no caminho crítico de `getAudioOutputRender()` (`MEPlayerItem.swift:850-856`), qualquer implementação futura precisaria rodar o reconhecimento em background/thread separada para não bloquear o pipeline de áudio.

Em resumo: a arquitetura tem um ponto de extensão pensado para isso (provavelmente copiado da estrutura da versão paga, com a implementação removida), mas nenhuma lógica de IA, reconhecimento de fala ou tradução está presente.
