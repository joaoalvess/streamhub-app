# FFmpeg version bundled

## Status
Presente (revisado na verificação — era "Parcial")

O fork GPL de fato empacota e compila FFmpeg (via dependência externa FFmpegKit), então a feature "existe" ponta a ponta — mas a versão travada é 6.1.x, abaixo da 8.1.1 usada na versão paga, exatamente como a tabela do README já documenta. Não há nenhum mecanismo no código para trocar/atualizar essa versão automaticamente; é um pin de dependência externo.

## Evidência
- `Package.swift:46` — `.package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.4")`
- `Package.swift:24` — `.product(name: "FFmpegKit", package: "FFmpegKit")` (dependência real do target KSPlayer)
- `KSPlayer.podspec:44` — `ss.dependency 'FFmpegKit'` (CocoaPods também depende do mesmo pod, sem versão fixada no podspec, mas resolvida via Podfile.lock)
- `Demo/Podfile.lock:3-5` — `FFmpegKit (6.1.0)` / `FFmpegKit/FFmpegKit (= 6.1.0)` (versão efetivamente resolvida/instalada no projeto Demo)
- `Demo/Podfile:7-9` — pods `Libass`, `OpenSSL`, `FFmpegKit` apontando para `../FFmpegKit` local (com alternativas comentadas apontando para o branch `main` do repo kingslay/FFmpegKit)
- `README.md:64` — tabela oficial já cita `FFmpeg version | 8.1.1 | 6.1.0` (pago vs GPL), confirmando que o mantenedor está ciente do gap de versão

## Como funciona
- O player em si (KSPlayer/KSMEPlayer) não embute o código-fonte do FFmpeg neste repositório; ele consome um pacote irmão, `kingslay/FFmpegKit` (Swift Package / CocoaPods pod), que compila os binários FFmpeg/Libass/OpenSSL.
- Via SPM (`Package.swift`), a versão mínima requisitada é `6.1.4`, resolvida pelo `Package.resolved` (não inspecionado aqui, mas normalmente trava numa tag específica ≥6.1.4).
- Via CocoaPods (usado no projeto Demo), o `Podfile.lock` mostra a versão efetivamente baixada: `6.1.0`.
- Isso é consistente com a tabela do README: a build GPL roda sobre binários FFmpeg 6.1.x, enquanto a versão paga do KSPlayer usa 8.1.1.

## O que falta
Para fechar o gap com a versão paga (chegar a FFmpeg 8.x):
- Atualizar a dependência em `Package.swift:46` para uma tag/branch do `kingslay/FFmpegKit` que já compile FFmpeg 8.x (se existir upstream) ou apontar para um fork próprio que faça esse bump.
- Atualizar `Demo/Podfile` (ou o `Podfile.lock` regenerado) para a mesma versão nova do pod `FFmpegKit`.
- Verificar compatibilidade de API: mudanças entre FFmpeg 6.x e 8.x podem exigir ajustes nos wrappers Swift/C que chamam a libav* (não investigado neste escopo — ficaria em `Sources/KSPlayer/MEPlayer/*` e possivelmente em headers bridging do próprio pacote FFmpegKit, que é um repositório externo, não parte deste checkout).
- Como o código-fonte do FFmpeg/FFmpegKit não está neste repositório (é uma dependência externa via SPM/CocoaPods), qualquer trabalho de "subir a versão" acontece no repositório `kingslay/FFmpegKit`, não em `StreamHub/Player`.

## Verificação

Veredito: **Presente** — o status "Parcial" da investigação original foi refutado por erro de interpretação da tabela, não por erro factual.

Todos os fatos da investigação original foram reconfirmados de forma independente, e a varredura adversarial não encontrou nada que os contradiga:
- `Package.resolved` (não inspecionado na investigação original) trava `kingslay/FFmpegKit` na tag `6.1.4`, revision `c32be9bfb628042737ad3ef622e930c5c7b15954` — confirma o pin 6.1.x via SPM.
- `Sources/KSPlayer/MEPlayer/*.swift` (ex.: `AVFFmpegExtension.swift:3-5` com `import Libavcodec` / `import Libavformat`, além de `FFmpegDecode.swift`, `MEPlayerItem.swift` etc.) consome os módulos do FFmpegKit em ~10 arquivos — o FFmpeg está integrado e funcional ponta a ponta no core MEPlayer, não é dependência declarada e não usada.
- `Demo/Podfile.lock:3-5` confirma `FFmpegKit (6.1.0)` no fluxo CocoaPods; o subspec `KSPlayer/MEPlayer` depende dele.
- Busca por fontes FFmpeg embutidas, `binaryTarget`, `.xcframework`, `.a`/`.dylib`, git submodules e diretórios `ffmpeg`/`libav` no repo: nada encontrado além dos scripts de Pods (`Demo/Pods/Target Support Files/FFmpegKit-*/`), que apenas copiam xcframeworks baixados pelo pod. Não existe FFmpeg 8.x oculto nem mecanismo de bump automático.
- Observação adicional: `Demo/Podfile:7-9` aponta para um checkout local `../FFmpegKit` que **não existe** neste clone — o Demo via CocoaPods não instala sem clonar `kingslay/FFmpegKit` ao lado do repo (ou reativar as linhas comentadas com `:git`).

Por que o status muda para Presente:
- A linha da tabela oficial (`README.md:64`) é `|FFmpeg version|8.1.1|6.1.0|` — uma linha de comparação de versões, não uma linha de feature ✅/❌. A afirmação da tabela para a coluna GPL é "FFmpeg 6.1.0", e a realidade do repo (6.1.4 via SPM, 6.1.0 via CocoaPods) corresponde exatamente ao documentado.
- A tabela nunca prometeu 8.1.1 para a versão GPL; o "Parcial" original nasceu de comparar o fork contra a coluna paga, que é a **meta de paridade** do projeto, não a claim da tabela sobre o GPL. Não há, portanto, contradição entre o repo e a tabela.
- A feature "FFmpeg bundled" está integralmente presente: dependência declarada (SPM e CocoaPods), resolvida, e consumida pelo pipeline de demux/decode do MEPlayer.
- O gap 6.1.x → 8.1.1 permanece real e é trabalho de evolução do fork (bump no repositório `kingslay/FFmpegKit` ou fork próprio, conforme seção "O que falta"), mas é item de roadmap de paridade com a versão paga — não torna a presença da feature parcial.
