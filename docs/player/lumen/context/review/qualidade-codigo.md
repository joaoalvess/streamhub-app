# Auditoria de qualidade de código — fork KSPlayer

Escopo: `Sources/` (leitura integral dos arquivos maiores e amostragem dirigida dos demais). Dimensão: código ruim/ilegível que dificulta manutenção — funções gigantes, duplicação grosseira, nomes enganosos, dead code, APIs públicas confusas. Não cobre bugs de concorrência/memória/ciclo-de-vida (ver os outros arquivos em `context/review/`).

Cada finding foi confirmado lendo o código-fonte e, quando relevante, com `rg` para garantir que não há outro call site.

---

## 1. Quatro funções quase idênticas para montar `UIAlertController` (duplicação grosseira)

**Arquivo:** `Sources/KSPlayer/Video/VideoPlayerView.swift:538-633`
**Severidade:** média

`changeAudioVideo`, `changeDefinitions`, `changeSrt` e `changePlaybackRate` repetem o mesmo esqueleto: criar `UIAlertController`, iterar uma lista, criar uma `UIAlertAction` por item, marcar a `preferredAction`, adicionar "cancel" e chamar `viewController?.present(...)`. Só o conteúdo da lista e o texto do título mudam.

Efeito concreto já observável: a lista de velocidades de reprodução `[0.75, 1.0, 1.25, 1.5, 2.0]` está copiada literalmente em **dois lugares** (linha 510, dentro de `buildMenusForButtons`, e linha 617, dentro de `changePlaybackRate`), e o Control Center via `MPRemoteCommandCenter` usa uma **terceira lista diferente** (`[0.5, 1, 1.5, 2]` em `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:602`). Resultado: hoje já existem três fontes de verdade divergentes para "quais velocidades de reprodução o player oferece" — adicionar/remover uma opção exige lembrar de editar os três pontos, e um deles (Control Center) já ficou dessincronizado dos outros dois.

Sugestão de escopo (sem implementar agora): extrair um único helper `presentPicker(title:current:list:titleFunc:onSelect:)` reutilizável pelas 4 funções, e centralizar a lista de rates numa constante única compartilhada pelos três consumidores.

---

## 2. Duplicação verbatim do parser de texto entre VTT e SRT

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:361-371` e `:407-416`
**Severidade:** média

`VTTParse.parsePart` e `SrtParse.parsePart` só diferem na forma de reconhecer a linha de timestamp; o laço que acumula as linhas de texto até a linha em branco é copiado caractere por caractere entre as duas classes:

```swift
var text = ""
var newLine: String? = nil
repeat {
    if let str = scanner.scanUpToCharacters(from: .newlines) {
        text += str
    }
    newLine = scanner.scanCharacters(from: .newlines)
    if newLine == "\n" || newLine == "\r\n" {
        text += "\n"
    }
} while newLine == "\n" || newLine == "\r\n"
```

Cenário de falha concreto: um bug em quebra de linha (ex.: suportar `\r` sozinho, ou tratar linhas com espaços à direita) precisa ser corrigido nos dois lugares; é fácil corrigir um e esquecer o outro, fazendo VTT e SRT divergirem silenciosamente em como renderizam legendas multilinha.

---

## 3. `Utility.swift` é um dumping-ground sem coesão

**Arquivo:** `Sources/KSPlayer/Core/Utility.swift` (850 linhas)
**Severidade:** média

O arquivo mistura, sem nenhuma relação temática: parsing de M3U/playlist (`Scanner.parseM3U`, `Data.parsePlaylist`), geração de GIF (`GIFCreator`, `AVAsset.generateGIF`), exportação de MP4 (`exportMp4`), helpers de cor ASS (`UIColor(assColor:)`), download de URL, conformâncias `RawRepresentable`/`Identifiable` para tipos do SwiftUI (`TextAlignment`, `HorizontalAlignment`, `VerticalAlignment`, `Color`, `Date`, `Array`), manipulação de `CGImage` bruta, um algoritmo de merge sort genérico (`mergeSortBottomUp`) e um tipo `Either`/`Box` de uso genérico. Nenhuma dessas responsabilidades tem relação com as outras.

Isso dificulta manutenção de forma concreta: para achar onde `parsePlaylist` está implementado, ou lembrar se `md5()` é de `String` ou de `Data`, é preciso abrir um arquivo de 850 linhas sem nenhuma estrutura de navegação — e o nome genérico "Utility" convida a continuar despejando código novo não relacionado ali, agravando o problema a cada PR.

---

## 4. Dead code confirmado em `KSAVPlayer.swift`

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:511` e `:569`
**Severidade:** baixa

```swift
extension AVAssetTrack {
    func toMediaPlayerTrack() {}   // linha 511 — nunca chamada
}
...
class AVMediaPlayerTrack: MediaPlayerTrack {
    ...
    func load() {}                 // linha 569 — nunca chamada
}
```

Confirmado via `rg` que nenhum dos dois métodos é chamado em `Sources/` ou `Demo/`, e `load()` não é requisito do protocolo `MediaPlayerTrack` (`Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:117-131`). São stubs vazios que sugerem uma funcionalidade (carregar/converter track) que não existe — quem for implementar carregamento assíncrono de metadata de track (padrão exigido em `xrOS`, ver o bloco `Task { isPlayable = await ... }` logo abaixo) pode ser levado a pensar que `load()` já é o hook certo para isso.

---

## 5. Nome de API pública com erro de digitação

**Arquivo:** `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:585`
**Severidade:** baixa

```swift
public extension KSMEPlayer {
    func startRecord(url: URL) { playerItem.startRecord(url: url) }
    func stoptRecord() { playerItem.stopRecord() }   // "stopt", não "stop"
}
```

`stoptRecord()` é público e é o único método da dupla com erro de digitação — o método que ele encapsula (`MEPlayerItem.stopRecord()`) está escrito corretamente. Qualquer consumidor da API (o app StreamHub incluso) que digite `stopRecord()` por autocomplete não vai encontrar o método; e como é API pública, corrigir o nome depois é uma breaking change.

---

## 6. Condicional morta/enganosa em `canPerformAction`

**Arquivo:** `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:376-381`
**Severidade:** baixa

```swift
override open func canPerformAction(_ action: Selector, withSender _: Any?) -> Bool {
    if action == #selector(IOSVideoPlayerView.openFileAction) {
        return true
    }
    return true
}
```

Os dois ramos retornam `true`; o `if` não tem nenhum efeito e o método equivale a `return true` incondicional. Isso é enganoso: parece implementar uma checagem de permissão por ação (padrão comum em overrides de `canPerformAction`), mas na verdade libera qualquer ação para qualquer sender. Quem for adicionar uma segunda ação restrita a essa tabela vai presumir, incorretamente, que o padrão existente já filtra por `action`.

---

## 7. Ternário morto em `KSOptions.process(assetTrack:)`

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSOptions.swift:310-336`
**Severidade:** baixa

```swift
hardwareDecode = false
asynchronousDecompression = false
let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
```

`hardwareDecode` é zerado na linha imediatamente anterior à leitura, então o ramo `"yadif_videotoolbox"` é inalcançável — `yadif` é sempre `"yadif"`. O comentário acima (`// todo 先不要用yadif_videotoolbox，不然会crash`) mostra que isso foi proposital em algum momento, mas o ternário sobrevivente sugere, para quem lê o código hoje, uma decisão condicional que não existe mais de fato — é ruído que deveria virar `let yadif = "yadif"` com o TODO explicando por quê.

---

## 8. `MEPlayerItem` acumula duas responsabilidades: demux/decode e gravação/mux para arquivo

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` (881 linhas; gravação em `:271-326` e `:672-676`)
**Severidade:** média

`MEPlayerItem` é a classe central de leitura/decodificação via FFmpeg (abrir input, ler pacotes, gerenciar tracks, seek, clock). Além disso, ela também implementa um pipeline completo de **gravação/transcodificação para arquivo** (`startRecord`, `streamMapping`, `outputFormatCtx`, `outputPacket`, remux de pacotes em `reading()` linhas 530-547, `stopRecord`) — uma responsabilidade ortogonal (escrever um novo container de saída) que nada tem a ver com tocar o vídeo na tela. Isso deixa a classe (já a segunda maior do módulo) misturando "estado do player" com "estado do gravador", e qualquer leitura de `reading()` ou `shutdown()` precisa entender os dois fluxos simultaneamente para saber o que é relevante.

Sugestão de escopo: extrair a gravação para um tipo dedicado (`StreamRecorder`/`FormatMuxer`) que receba pacotes lidos, ao invés de viver dentro do próprio item de playback.

---

## 9. Bloco de código morto comentado no fim do arquivo

**Arquivo:** `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:767-783`
**Severidade:** baixa

```swift
// struct AVContentView: View {
//    var body: some View {
//        StructAVPlayerView().frame(width: UIScene.main.bounds.width, height: 400, alignment: .center)
//    }
// }
//
// struct StructAVPlayerView: UIViewRepresentable {
//    ...
// }
```

Uma struct inteira comentada, sem TODO ou explicação, sobrevivendo no arquivo principal da API SwiftUI pública. Deveria ser removida (o histórico do git já preserva o código, se algum dia for preciso recuperá-lo).

---

## 10. Extensão pública vazia

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:23`
**Severidade:** baixa

```swift
public extension String {}
```

Não adiciona nada; é resíduo de alguma refatoração anterior. Deveria ser removida.

---

## 11. Seis blocos idênticos de setup de botão em `PlayerToolBar.initUI`

**Arquivo:** `Sources/KSPlayer/Core/PlayerToolBar.swift:140-163`
**Severidade:** baixa

`playbackRateButton`, `definitionButton`, `audioSwitchButton`, `videoSwitchButton` e `srtButton` repetem, na mesma ordem, o mesmo padrão de 4 linhas:

```swift
xButton.tag = PlayerButtonType.x.rawValue
xButton.titleFont = .systemFont(ofSize: 14, weight: .medium)
xButton.setTitleColor(focusColor, for: .focused)
xButton.setTitleColor(tintColor, for: .normal)
```

Candidato natural a um laço sobre `[(button, tag)]` — hoje qualquer mudança de estilo (ex.: trocar o peso da fonte) precisa ser replicada manualmente em 5 lugares.

---

## Resumo

| # | Arquivo | Linha(s) | Severidade |
|---|---------|----------|------------|
| 1 | VideoPlayerView.swift | 538-633 | média |
| 2 | KSParseProtocol.swift | 361-371 / 407-416 | média |
| 3 | Utility.swift | arquivo inteiro | média |
| 4 | KSAVPlayer.swift | 511 / 569 | baixa |
| 5 | KSMEPlayer.swift | 585 | baixa |
| 6 | IOSVideoPlayerView.swift | 376-381 | baixa |
| 7 | KSOptions.swift | 310-336 | baixa |
| 8 | MEPlayerItem.swift | 271-326 / 672-676 | média |
| 9 | KSVideoPlayerView.swift | 767-783 | baixa |
| 10 | KSParseProtocol.swift | 23 | baixa |
| 11 | PlayerToolBar.swift | 140-163 | baixa |
