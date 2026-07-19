## Status

Ausente.

## Evidência

- `rg -n "UIScreen|screens\b|didConnectNotification|externalDisplay|NSScreen.screens|secondaryWindow|externalWindow" --glob '*.swift' Sources` só retorna:
  - `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:39-41` — uso de `UIScreen.main.brightness` (controle de brilho, não relacionado a telas externas).
  - `Sources/KSPlayer/Video/BrightnessVolume.swift:17` — observer de `UIScreen.main.brightness` (mesmo propósito, brilho local).
- Nenhuma ocorrência de `UIScreen.screens`, `UIScreen.didConnectNotification`, `NSScreen.screens`, `CADisplayLink` associado a tela externa, ou qualquer criação de `UIWindow`/`NSWindow` secundário para espelhar/estender o conteúdo de vídeo em outra tela.
- `Sources/KSPlayer/SwiftUI/AirPlayView.swift:1-35` — única funcionalidade relacionada a "outra tela" existente no código: um wrapper de `AVRoutePickerView` (AirPlay/casting via AVKit). Isso expõe a UI padrão do sistema para o usuário escolher uma rota de saída (AirPlay, HDMI via Apple TV, etc.), mas é a feature nativa da Apple, não uma implementação própria de renderização em múltiplas telas.
- `Sources/KSPlayer/Metal/MetalRender.swift` e demais arquivos em `Sources/KSPlayer/Metal/` — o pipeline de renderização (Metal) está acoplado a uma única `CAMetalLayer`/view (`MetalPlayView.swift`), sem abstração para múltiplos destinos de render simultâneos.
- Nenhum branch de plataforma (`#if os(tvOS)`, `#if os(macOS)`) trata sessão de múltiplas telas; `Sources/KSPlayer/Core/AppKitExtend.swift` (macOS) não contém lógica de `NSScreen`.

## O que falta

Não há nenhuma base/esboço para implementar "video output to another screen" (ex.: extended display no macOS, ou dual-screen no tvOS/iPadOS). Uma implementação real começaria por:

1. Detectar telas conectadas: `NotificationCenter` para `UIScreen.didConnectNotification`/`didDisconnectNotification` (iOS/tvOS) ou observar `NSApplication.didChangeScreenParametersNotification` (macOS).
2. Criar uma `UIWindow`/`NSWindow` secundária atribuída à tela externa (`window.screen = externalScreen`), com uma segunda instância de `MetalPlayView` (ou reuso da mesma `CAMetalLayer` associada a outro `CADisplayLink`) — hoje `MetalPlayView.swift` só suporta uma view "dona" da renderização.
3. Decidir se a saída decodifica um único stream para dois destinos (duplicar o `CVPixelBuffer`/`MTLTexture` final para duas layers) ou se a saída secundária deve rodar plena resolução separada — teria que tocar `KSMEPlayer.swift`/`FFmpegDecode.swift` para saber se o pipeline suporta múltiplos consumidores do mesmo frame decodificado.
4. Expor uma opção em `KSOptions.swift` (nenhuma flag hoje relacionada a isso) para habilitar/configurar a saída para tela secundária.
5. Ajustar `KSVideoPlayerView.swift`/`VideoPlayerView.swift` para orquestrar UI própria (controles) na tela principal enquanto a tela secundária mostra somente o vídeo puro — hoje essas views não têm esse conceito de "vídeo apenas" desacoplado dos controles.

Nada disso existe hoje, nem como stub, TODO ou comentário no código.
