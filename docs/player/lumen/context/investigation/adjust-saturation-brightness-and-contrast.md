## Status

Ausente.

## Evidência

- `Sources/KSPlayer/Video/VideoPlayerView.swift:958` — `KSOptions.enableBrightnessGestures`: apenas habilita o gesto de arrastar que ajusta o **brilho da tela do dispositivo** (`UIScreen.main.brightness`), não um filtro de imagem do vídeo.
- `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:39-43` — propriedade `brightness` que faz `didSet { UIScreen.main.brightness = brightness }`, confirmando que é controle de hardware/tela, não do frame decodificado.
- `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:264-267` — uso do gesto de pan para alterar `brightness` (tela), análogo ao gesto de volume.
- `Sources/KSPlayer/Video/BrightnessVolume.swift:1-209` — todo o arquivo implementa apenas o HUD/overlay de feedback visual para os gestos de brilho de tela e volume do sistema (ícones `sun.max`/`speaker.wave.3.fill`, `UIScreen.main.observe(\.brightness, ...)`), sem qualquer relação com pós-processamento de imagem do vídeo.
- Busca em todo o repositório por `saturation`, `contrast`, `CIFilter`, `CIColorControls`, `colorMatrix`, `colorAdjust`: nenhuma ocorrência em arquivos `.swift`.

## Como funciona

Não se aplica — não há nenhuma implementação de ajuste de saturação, brilho de imagem (do conteúdo do vídeo) ou contraste. O único conceito de "brightness" existente no código é o brilho da tela do dispositivo (iOS/tvOS `UIScreen.main.brightness`), controlado por gesto de arrastar na tela, com um HUD (`BrightnessVolume.swift`) mostrando o valor — funcionalidade completamente distinta de aplicar um filtro de cor sobre os pixels do vídeo decodificado.

## O que falta

Uma implementação real precisaria atuar no pipeline de renderização do frame decodificado, não na camada de UI de gestos. Pontos de partida prováveis, dado o pipeline do KSPlayer (baseado em Metal para renderização):

- Camada de renderização Metal do player (buscar por `MetalPlayView`/`KSVideoPlayer` no Metal render path, ex. em `Sources/KSPlayer/Metal/` — não explorado nesta investigação, mas é onde os frames YUV/RGB são convertidos e desenhados). Ajuste de saturação/contraste/brilho de imagem tipicamente é feito via matriz de cor ou shader Metal (fragment shader) aplicado no frame antes do `MTKView.draw`.
- Alternativa: um `CIFilter` (`CIColorControls`, que expõe exatamente `inputSaturation`/`inputBrightness`/`inputContrast`) aplicado sobre uma `CIImage` derivada do `CVPixelBuffer` do frame, caso o pipeline permita interceptar o buffer antes da apresentação.
- Seria necessário adicionar propriedades em `KSOptions` (ex. `videoSaturation`, `videoBrightness`, `videoContrast`) análogas a `enableBrightnessGestures`, mais UI de controle (slider) na camada de `VideoPlayerView`/`IOSVideoPlayerView`, distintas da atual `BrightnessVolume` (que é HUD de tela, não deve ser reaproveitada para isso).
- Nenhum hook, flag ou esboço parcial dessa funcionalidade existe hoje no código — a adição partiria do zero na camada de renderização de vídeo.
