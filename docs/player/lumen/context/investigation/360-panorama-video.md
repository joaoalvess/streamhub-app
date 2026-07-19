## Status

Presente.

## Evidência

- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:140` — `public enum DisplayEnum { case plane; case vr; case vrBox }`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:77` — `public var display = DisplayEnum.plane` (flag de configuração exposta em `KSOptions`).
- `Sources/KSPlayer/Metal/DisplayModel.swift:15-52` — `extension DisplayEnum` faz dispatch de `.plane`/`.vr`/`.vrBox` para `PlaneDisplayModel`, `VRDisplayModel`, `VRBoxDisplayModel`.
- `Sources/KSPlayer/Metal/DisplayModel.swift:123-249` — `SphereDisplayModel` gera geometria de esfera (`genSphere`, 200 slices), aplica rotação por toque (`touchesMoved`) e por sensor de movimento.
- `Sources/KSPlayer/Metal/DisplayModel.swift:251-270` — `VRDisplayModel` (esfera mono, projeção perspectiva única) para vídeo 360 padrão.
- `Sources/KSPlayer/Metal/DisplayModel.swift:272-299` — `VRBoxDisplayModel` (side-by-side estéreo, dois viewports/matrizes) para VR box/cardboard.
- `Sources/KSPlayer/Metal/MetalRender.swift:138-141` — `makePipelineState(..., isSphere:)` seleciona o shader `mapSphereTexture` (vs `mapTexture` plano) por Metal shading function.
- `Sources/KSPlayer/Metal/MotionSensor.swift` — sensor de movimento (CoreMotion) que alimenta a matriz de rotação quando `KSOptions.enableSensor` está ativo (usado em `DisplayModel.swift:146-150,157-161`).
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:128-139` — gestos de toque (`touchesMoved`) só giram a câmera quando `options.display != .plane`, ligando input do usuário ao `DisplayModel`.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:203-218` — `draw(pixelBuffer:display:size:)` passa `options.display` para o pipeline Metal a cada frame.
- `Demo/SwiftUI/Shared/MovieModel.swift:277` — `options.display = .vr` setado manualmente para `vr.mp4` no app de demo (prova de uso real do flag).

## Como funciona

`KSOptions.display` (default `.plane`) é o flag central. Quando setado para `.vr` (monoscópico 360) ou `.vrBox` (estéreo side-by-side, tipo Cardboard), o pipeline de renderização Metal (`MetalPlayView`/`MetalRender`) troca a geometria de um quad plano para uma esfera UV-mapeada (`SphereDisplayModel.genSphere`), usa o fragment/vertex shader `mapSphereTexture` em vez de `mapTexture`, e projeta a textura do frame decodificado (YUV/NV12/BGRA, 8 ou 10 bits) sobre a esfera com uma matriz de view-projeção em perspectiva. A câmera dentro da esfera pode ser rotacionada por:
1. Gesto de arrastar na tela (`touchesMoved` acumula `fingerRotationX/Y` e monta `modelViewMatrix`).
2. Giroscópio via CoreMotion (`MotionSensor.shared.matrix()`), ativado por `KSOptions.enableSensor`.

`VRBoxDisplayModel` renderiza duas vezes por frame (viewport esquerdo/direito, matrizes de câmera levemente deslocadas), suportando visualização estéreo em headsets tipo cardboard.

A ativação hoje é manual (o chamador precisa setar `options.display = .vr` antes de tocar), como visto no demo app que faz isso por nome de arquivo (`vr.mp4`).

## O que falta

Não há detecção automática de vídeo 360/spherical a partir de metadados do próprio arquivo (ex.: tag `spherical-video`/`st3d`/`sv3d` do Google Spatial Media, ou side-by-side heurístico), diferente do que Infuse faz (detecta automaticamente e oferece toggle). Para paridade completa nesse ponto específico, seria necessário:
- Ler metadados de projeção do stream (via FFmpeg: `AVStreamSideData`/`AV_PKT_DATA_SPHERICAL` ou tags do container MP4/MKV) em `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift` ou `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`, e setar `KSOptions.display` automaticamente antes do primeiro frame.
- Expor esse toggle/detecção na camada de UI do StreamHub (o Player em si já suporta `.vr`/`.vrBox` de ponta a ponta).
