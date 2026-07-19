# Auditoria de legendas — KSPlayer (fork StreamHub)

Escopo: `Sources/` do fork GPL do KSPlayer. Foco: parsing de legendas (SRT/ASS/VTT),
encoding, timing/offset, seleção de track, render. Investigadas também as issues
conhecidas do upstream: #885 (stutter/judder com frame rate matching + DV/HDR quando
legendas ativas) e #403 (legendas não carregam em m3u8 live com AVPlayer por baixo).

Cada finding foi confirmado lendo o código (arquivo/linha citados); os dois primeiros
foram além disso reproduzidos com um script Swift isolado (mesma API do Foundation
usada pelo player) para eliminar qualquer dúvida sobre o comportamento do `Scanner`/
`String(data:encoding:)`.

---

## 1. [CRÍTICA] Loop infinito em `SrtParse.parsePart` quando o arquivo não tem mais uma linha de índice numérico antes do EOF

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:393-398`

```swift
public func parsePart(scanner: Scanner) -> SubtitlePart? {
    var decimal: String?
    repeat {
        decimal = scanner.scanUpToCharacters(from: .newlines)
        _ = scanner.scanCharacters(from: .newlines)
    } while decimal.flatMap(Int.init) == nil
    ...
```

Esse `repeat/while` varre linha a linha procurando o número de índice do próximo cue SRT
("1", "2", "3"...). A condição de parada só verifica se a linha lida converte para `Int`
— **nunca verifica `scanner.isAtEnd`**. Quando o scanner chega ao fim da string,
`scanUpToCharacters(from:)` e `scanCharacters(from:)` passam a retornar `nil`
indefinidamente, então `decimal` fica `nil` para sempre e o loop nunca termina.

Reproduzi exatamente essa API isoladamente:

```swift
let remainder = "garbage without number\nmore garbage\n"
let scanner = Scanner(string: remainder)
scanner.charactersToBeSkipped = nil
var decimal: String?
repeat {
    decimal = scanner.scanUpToCharacters(from: .newlines)
    _ = scanner.scanCharacters(from: .newlines)
} while decimal.flatMap(Int.init) == nil
// nunca sai do loop: após 1000 iterações, scanner.isAtEnd já é `true` e decimal
// continua nil — a condição do while nunca vira false.
```

Compare com `VTTParse.parsePart` (mesmo arquivo, linhas 347-352), que resolve exatamente
esse mesmo problema corretamente:

```swift
repeat {
    timeStrs = scanner.scanUpToCharacters(from: .newlines)
    _ = scanner.scanCharacters(from: .newlines)
} while !(timeStrs?.contains("-->") ?? false) && !scanner.isAtEnd
```

O `VTTParse` inclui `&& !scanner.isAtEnd`; o `SrtParse` não. É uma assimetria clara —
a proteção existe num parser irmão e foi esquecida no outro.

**Cenário concreto de falha:** `parse(scanner:)` (KSParseProtocol.swift:26-37) só chama
`parsePart` de novo se `!scanner.isAtEnd`. Isso é inofensivo enquanto o arquivo SRT
termina exatamente após o texto do último cue. Mas basta que sobre **qualquer conteúdo
residual não vazio** depois do último cue válido — uma linha em branco extra com espaço/
tab, uma linha de crédito tipo "Sincronizado por ..." ou um anúncio que sites de legenda
costumam colar no fim do arquivo, um download truncado (`ShooterSubtitleDataSouce`,
`OpenSubtitleDataSouce` e `AssrtSubtitleDataSouce` em `SubtitleDataSouce.swift` baixam
arquivos arbitrários da internet, sem qualquer validação de integridade) — para que o
`while !scanner.isAtEnd` externo dispare mais uma chamada a `parsePart`, que entra no
`repeat` e nunca mais encontra um índice numérico antes do fim real da string.

O resultado é uma trava definitiva: a `Task` que chama `parse(url:)`
(`URLSubtitleInfo.isEnabled.didSet` em `SubtitleDataSouce.swift:20-27`, ou
`KSSubtitle.parse(data:)` chamado a partir daí) fica presa consumindo 100% de um core de
CPU para sempre — nunca lança erro, nunca completa, nunca libera a thread/queue em que
está rodando. Em tvOS isso é especialmente grave (thermal throttling, dreno de bateria
em Apple TV, sem qualquer mensagem de erro para o usuário).

**Correção sugerida:** replicar a mesma guarda do `VTTParse`:
`} while decimal.flatMap(Int.init) == nil && !scanner.isAtEnd`, e tratar o caso de EOF
retornando `nil`.

---

## 2. [ALTA] Auto-detecção de encoding produz mojibake silencioso em vez de decodificar ou falhar — legendas Latin-1/Windows-1252 (francês, espanhol, português, italiano, alemão)

**Arquivo:** `Sources/KSPlayer/Subtitle/KSSubtitle.swift:176-202`

```swift
func parse(data: Data, encoding: String.Encoding? = nil) throws {
    var string: String?
    let encodes = [encoding ?? String.Encoding.utf8,
                   String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
                   String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
                   String.Encoding.unicode]
    for encode in encodes {
        string = String(data: data, encoding: encode)
        if string != nil {
            break
        }
    }
    guard let subtitle = string else {
        throw NSError(errorCode: .subtitleUnEncoding)
    }
    ...
```

A cadeia de fallback tenta, nessa ordem: UTF-8 → Big5 → GB18030 → `.unicode` (UTF-16).
Não existe nenhuma tentativa de Latin-1/ISO-8859-1/Windows-1252 — os encodings mais
comuns para legendas europeias (fr/es/pt/it/de) que não foram salvas em UTF-8, o que é
extremamente comum em arquivos `.srt` baixados de sites de legenda antigos.

Reproduzi o problema com bytes reais de um SRT em Windows-1252 contendo "Café à Paris":

```
encode[0] utf8      -> nil
encode[1] Big5      -> nil
encode[2] GB18030   -> nil
encode[3] .unicode  -> "ㄊ〰㨰〺〱ⰰ〰‭ⴾ‰〺〰㨰㈬〰《䍡曩⃠⁐慲楳"   <- "sucesso"!

Decodificação correta (Latin-1 ou CP1252, nunca tentadas):
"1
00:00:01,000 --> 00:00:02,000
Café à Paris"
```

`.unicode` (UTF-16) quase nunca retorna `nil` para uma sequência arbitrária de bytes de
tamanho par — ele simplesmente reagrupa os bytes em unidades UTF-16 erradas e "decodifica
com sucesso" para lixo. Como esse é o **último** item do array, o `guard let subtitle`
nunca dispara `subtitleUnEncoding` para esse tipo de arquivo: o parser recebe uma string
totalmente corrompida e tenta parseá-la como se fosse um SRT válido (o que normalmente
falha depois, gerando `subtitleUnParse`/`subtitleFormatUnSupport`, ou pior, se o lixo por
coincidência contiver `-->`, tenta exibir texto ilegível para o usuário sem qualquer
aviso de "encoding errado, escolha manualmente").

**Cenário concreto de falha:** usuário baixa uma legenda em francês/português/espanhol
salva em Windows-1252 (ainda muito comum) para tocar no fork. Nenhum dos 4 encodings
tentados decodifica corretamente; o resultado exibido é lixo ou uma falha genérica de
parse, sem qualquer indicação de que bastava tentar Latin-1/CP1252.

**Correção sugerida:** adicionar `.isoLatin1`/`.windowsCP1252` à cadeia de fallback
(antes de `.unicode`, que deveria ser o *último* recurso justamente por quase nunca
falhar) e mover encodings CJK/Unicode para depois de exaurir os latinos, ou detectar a
partir do BOM/heurística de bytes em vez de tentar decodificações "gulosas" como último
passo.

---

## 3. [ALTA] `KSAVPlayer.subtitleDataSouce` sempre retorna `nil` — o motor de playback padrão nunca expõe legendas embutidas (explica a issue #403, mas o alcance é maior que só m3u8 live)

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:363`

```swift
public var subtitleDataSouce: SubtitleDataSouce? { nil }
```

`KSAVPlayer` é o motor baseado em `AVPlayer`/AVFoundation nativo. Diferente de
`KSMEPlayer` (que ganha `SubtitleDataSouce` via
`extension KSMEPlayer: SubtitleDataSouce` em `Sources/KSPlayer/MEPlayer/EmbedDataSouce.swift:25-28`,
expondo as tracks de legenda demuxadas pelo FFmpeg), `KSAVPlayer` hard-codifica `nil`.
Não há em nenhum lugar de `KSAVPlayer.swift` uma implementação de
`AVPlayerItemLegibleOutputPushDelegate` (ou qualquer outro mecanismo de
`AVMediaSelectionGroup`/legible track) para extrair cues nativas do AVPlayer (WebVTT de
HLS, CEA-608/708) — busquei `LegibleOutput`/`legibleOutput` em todo `Sources/` e não há
nenhuma ocorrência.

O ponto onde isso é consumido, `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:225-233`:

```swift
if let subtitleDataSouce = layer.player.subtitleDataSouce {
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) { [weak self] in
        guard let self else { return }
        self.subtitleModel.addSubtitle(dataSouce: subtitleDataSouce)
        ...
```

nunca executa para `KSAVPlayer`, então `SubtitleModel.subtitleInfos` nunca ganha as
legendas embutidas do arquivo/stream quando esse é o motor em uso.

**Isso não é caso isolado de HLS/live**: `KSAVPlayer` é o motor **padrão** —
`Sources/KSPlayer/AVPlayer/KSOptions.swift:461`: `static var firstPlayerType:
MediaPlayerProtocol.Type = KSAVPlayer.self` — e `Sources/KSPlayer/AVPlayer/
KSPlayerLayer.swift:128-141` mostra que, fora dos casos especiais (AirPlay, modo AR),
`firstPlayerType` é sempre `KSOptions.firstPlayerType` (= `KSAVPlayer`), e só cai para
`KSOptions.secondPlayerType` (`KSMEPlayer`, linha 446-447) se o `KSAVPlayer` **falhar
completamente** ao abrir a mídia. Ou seja: qualquer arquivo/stream que o AVPlayer nativo
consiga tocar (o que inclui a maioria de MP4/MOV e praticamente todo HLS/m3u8, live ou
VOD) nunca cai para o `KSMEPlayer`, e portanto nunca expõe legendas embutidas — mesmo que
o arquivo tenha faixas de legenda válidas.

**Cenário concreto de falha:** tocar um m3u8 (live ou VOD) com faixa de legenda WebVTT
embutida no manifest, ou um MP4 com `mov_text`/`tx3g` — ambos abrem normalmente via
`KSAVPlayer` (não há erro de playback), mas o botão/menu de legendas do player fica
sempre vazio, porque `subtitleDataSouce` nunca retorna nada para esse motor.

**Correção sugerida:** implementar `AVPlayerItemLegibleOutputPushDelegate` (ou
`AVMediaSelectionGroup(for: .legible)`) em `KSAVPlayer` para expor de fato as tracks de
legenda nativas do AVPlayer, ou documentar explicitamente que legendas embutidas só
funcionam via `KSMEPlayer` e forçar esse motor quando o usuário pede exibição de legenda
embutida.

---

## 4. [MÉDIA-ALTA] `FFmpegAssetTrack.isEnabled` ignora o valor passado para qualquer legenda de texto — `.isEnabled = false` nunca desabilita o demux dessas tracks

**Arquivo:** `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:265-276`

```swift
public var isEnabled: Bool {
    get {
        stream?.pointee.discard == AVDISCARD_DEFAULT
    }
    set {
        var discard = newValue ? AVDISCARD_DEFAULT : AVDISCARD_ALL
        if mediaType == .subtitle, !isImageSubtitle {
            discard = AVDISCARD_DEFAULT
        }
        stream?.pointee.discard = discard
    }
}
```

Para qualquer track de legenda que **não** seja bitmap (`!isImageSubtitle`, ou seja,
SRT/ASS/`mov_text` embutidos — a imensa maioria das legendas de texto em MKV/MP4), o
`discard` é forçado para `AVDISCARD_DEFAULT` **independente do `newValue` recebido**. Ou
seja, chamar `track.isEnabled = false` nessas tracks é um no-op: o `discard` nunca vira
`AVDISCARD_ALL` e o getter (`stream?.pointee.discard == AVDISCARD_DEFAULT`) sempre
reporta `true`.

Esse setter é chamado exatamente com essa intenção em
`Sources/KSPlayer/Subtitle/KSSubtitle.swift:316-319`:

```swift
public var selectedSubtitleInfo: (any SubtitleInfo)? {
    didSet {
        oldValue?.isEnabled = false
        selectedSubtitleInfo?.isEnabled = true
        ...
```

e `FFmpegAssetTrack` é exposto como `SubtitleInfo` justamente para legendas embutidas
(`extension FFmpegAssetTrack: SubtitleInfo` em `EmbedDataSouce.swift:11`). Como o
`discard` nunca é setado para `AVDISCARD_ALL` nesse caminho, **todas** as tracks de
legenda de texto de um arquivo continuam sendo demuxadas e decodificadas continuamente
pelo FFmpeg (cada uma com seu próprio `SyncPlayerItemTrack<SubtitleFrame>`, capacidade
255 frames — `MEPlayerItem.swift:339-343`), independente de qual (ou nenhuma) o usuário
selecionou.

**Cenário concreto de falha:** um MKV com múltiplas faixas de legenda de texto (comum em
rips de anime: japonês forçado + português + inglês + comentários, por exemplo)
mantém **todas** elas sendo decodificadas em paralelo o tempo todo, mesmo que o usuário
selecione só uma ou desligue legendas — desperdício de CPU/memória constante durante
toda a reprodução, sem qualquer ganho (a track "desligada" nunca é de fato descartada no
nível do demuxer).

Esse mesmo defeito também explica por que `MEPlayerItem.select(track:)`
(`MEPlayer/MEPlayerItem.swift:134-158`) sempre retorna `false` logo na primeira linha
(`if track.isEnabled { return false }`) para qualquer `FFmpegAssetTrack` de legenda de
texto — `isEnabled` já é sempre `true` por causa desse bug, então a troca de track nunca
prossegue por esse caminho (a UI atual contorna isso via
`srtControl.selectedSubtitleInfo`, então o sintoma visível hoje é só o desperdício de
CPU, não uma falha de seleção — mas o método público `select(track:)` fica quebrado para
esse caso).

**Correção sugerida:** remover a sobrescrita incondicional de `discard` para legendas de
texto, ou pelo menos respeitar `newValue` (`discard = newValue ? AVDISCARD_DEFAULT :
AVDISCARD_ALL` sem a exceção), e se o objetivo é manter todas as tracks de texto sempre
demuxadas para permitir troca instantânea sem seek, documentar isso e não expor
`isEnabled` como se fizesse o que o nome sugere.

---

## 5. [MÉDIA] `PlayResX`/`PlayResY` do ASS são parseados e nunca usados — margens/posições ficam erradas quando o vídeo não está na resolução de referência do arquivo

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:42-52`

```swift
private var playResX = Float(0.0)
private var playResY = Float(0.0)
public func canParse(scanner: Scanner) -> Bool {
    ...
    while scanner.scanString("Format:") == nil {
        if scanner.scanString("PlayResX:") != nil {
            playResX = scanner.scanFloat() ?? 0
        } else if scanner.scanString("PlayResY:") != nil {
            playResY = scanner.scanFloat() ?? 0
        } else {
            _ = scanner.scanUpToCharacters(from: .newlines)
        }
    }
    ...
```

`playResX`/`playResY` são lidos do cabeçalho `[Script Info]` mas — busquei em todo
`Sources/` — nunca são referenciados em nenhum outro lugar (nem em `parsePart`, nem em
`String.build`/`parseStyle`, nem em `parseASSStyle()`). `MarginL`/`MarginR`/`MarginV`
(tanto do `Style:` quanto de overrides por linha, linhas 117-125 e 318-326) são aplicados
diretamente como pontos absolutos em `TextPosition.leftMargin/rightMargin/
verticalMargin`, que por sua vez viram `EdgeInsets` (linhas 45-59) renderizados
diretamente na view do player.

O formato ASS especifica que todo valor de posição/margem é expresso em unidades da
resolução de referência (`PlayResX`x`PlayResY`) declarada no cabeçalho — um renderer
correto escala esses valores pela razão entre a resolução real de exibição e
`PlayResX`/`PlayResY`. Como esse fork ignora completamente esse fator de escala, uma
legenda ASS autorada para, por exemplo, `PlayResX: 640`/`PlayResY: 480` (comum em fansubs
mais antigos) exibida sobre um vídeo 1920x1080 ou 4K terá suas margens/posições
finais **muito menores do que deveriam**, deslocando texto posicionado para fora do
lugar pretendido.

**Cenário concreto de falha:** uma legenda ASS de fansub com "signs" (texto de tradução
posicionado, não apenas diálogo) autorada em resolução de referência menor que a do
vídeo real mostra as legendas de posição customizada (via `MarginL/R/V`) coladas nas
bordas ou fora da área correta da tela, em vez de escaladas proporcionalmente.

**Correção sugerida:** aplicar o fator de escala `videoWidth/playResX`,
`videoHeight/playResY` (quando ambos > 0) aos valores de margem antes de armazená-los em
`TextPosition`.

---

## 6. [MÉDIA] Tags de posicionamento absoluto do ASS (`\pos`, `\move`, `\org`, `\clip`) não são reconhecidas — legendas "sign"/posicionadas caem sempre na posição default do Style

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:175-245` (`parseStyle`)

O `switch` que interpreta os override tags ASS (`{\...}`) só trata `a` (alinhamento),
`b` (bold/expansion), `c`/`1c`/`2c`/`3c`/`4c` (cores), `f` (fonte), `i` (itálico), `s`
(strikeout/shadow), `u` (underline) — qualquer outra letra cai no `default: break`
(linha 236-238), silenciosamente ignorada. Isso inclui `\pos(x,y)`, `\move(...)`,
`\org(x,y)` e `\clip(...)`, que são as tags padrão do ASS para posicionar texto em
coordenadas absolutas da tela — usadas extensivamente em faixas de "signs" (tradução de
letreiros/texto na tela) e karaokê estilizado, muito comuns em fansubs de anime.

**Cenário concreto de falha:** uma legenda ASS com uma linha
`{\pos(960,100)}Aviso na parede` é renderizada usando apenas o alinhamento/margem do
`Style` nomeado na linha `Dialogue` (tipicamente `\an2`/bottom-center), e não na posição
`(960,100)` pedida pela tag — o texto aparece embaixo, centralizado, em vez de no local
pretendido pelo autor da legenda.

**Correção sugerida:** se suporte a posicionamento absoluto for prioridade para atingir
paridade com Infuse/KSPlayer PRO, adicionar interpretação de `\pos`/`\move`/`\org` em
`parseStyle`, propagando coordenadas absolutas para `SubtitlePart.origin`/`textPosition`
em vez de depender só do alinhamento do Style.

---

## 7. [MÉDIA] `AssParse` é um singleton estático mutável — estilos (`styleMap`) de uma legenda ASS anterior vazam para a próxima

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:20` e `:39-40`

```swift
public extension KSOptions {
    static var subtitleParses: [KSParseProtocol] = [AssParse(), VTTParse(), SrtParse()]
}

public class AssParse: KSParseProtocol {
    private var styleMap = [String: ASSStyle]()
    private var eventKeys = [...]
    ...
```

`KSOptions.subtitleParses` é um array **estático**, criado uma única vez; a mesma
instância de `AssParse` (com seu `styleMap` de instância) é reutilizada para **todo**
arquivo ASS carregado durante a vida do processo. `canParse(scanner:)`
(linhas 44-80) só faz `styleMap[values[0]] = dic.parseASSStyle()` (atribuição por
chave) — nunca `styleMap.removeAll()` no início do parse de um novo arquivo.

**Cenário concreto de falha:** o usuário assiste um episódio cuja legenda ASS define um
estilo `Sign` com determinada fonte/cor/posição. Ao trocar para outro título (mesma
sessão do app, comum em um app tvOS que fica de pé por horas) cuja legenda ASS também
referencia um estilo chamado `Sign` mas cujo cabeçalho `[V4+ Styles]`, por qualquer
motivo (arquivo malformado, gerado por ferramenta que omite estilos não usados no
próprio arquivo, ou falha de rede truncando o download antes do fim do cabeçalho de
estilos), não redefine `Sign` — o `styleMap` ainda contém a definição do arquivo
**anterior**, e o diálogo do novo arquivo herda fonte/cor/posição de um vídeo diferente.

**Correção sugerida:** limpar `styleMap`/`eventKeys`/`playResX`/`playResY` no início de
`canParse(scanner:)`, ou instanciar um `AssParse()` novo por chamada a
`KSSubtitle.parse(data:)` em vez de reusar a instância estática.

---

## 8. [BAIXA-MÉDIA] Normalização de `startTime` assimétrica em `SubtitleDecode` pode deixar cues de legenda embutida (bitmap/ASS via FFmpeg) fora do relógio zero-based usado pelo resto do player

**Arquivo:** `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:46-50`

```swift
let timestamp = packet.timestamp
var start = packet.assetTrack.timebase.cmtime(for: timestamp).seconds + TimeInterval(subtitle.start_display_time) / 1000.0
if start >= startTime {
    start -= startTime
}
```

`startTime` aqui é `assetTrack.startTime.seconds` (o `start_time` reportado pelo FFmpeg
especificamente para a track de legenda — `FFmpegAssetTrack.swift:84-86`). A subtração
só ocorre **se** `start >= startTime`; se um pacote de legenda tiver timestamp bruto
menor que o `start_time` da própria track (situação plausível com PTS fora de ordem,
contêineres com padding, ou tracks cujo primeiro cue foi codificado com timestamp
anterior ao valor de `start_time` reportado pelo demuxer), o valor de `start` **não** é
normalizado e permanece na escala bruta/absoluta.

Isso é inconsistente com o resto do player: `MEPlayerItem.currentPlaybackTime`
(`MEPlayerItem.swift:44-46`) sempre calcula `(mainClock().time - startTime).seconds` —
ou seja, o tempo usado para comparação em
`SubtitleModel.subtitle(currentTime:)`/`KSSubtitleProtocol.search(for:)` é **sempre**
zero-based, incondicionalmente. Um `part.start` que escapou da normalização por cair no
ramo `else` fica numa escala diferente da usada para buscá-lo.

**Cenário concreto de falha:** para uma legenda embutida (ASS/bitmap decodificada via
FFmpeg) cujo primeiro(s) cue(s) caem nesse caso de borda, o `SubtitlePart.start`/`.end`
não bate com `currentTime` (zero-based) na hora da busca em
`KSSubtitle.search(for:)`/`outputRenderQueue.search`, fazendo esse(s) cue(s)
específico(s) nunca aparecerem (silenciosamente descartados por nunca corresponder a
nenhum `currentTime` da reprodução).

**Correção sugerida:** normalizar incondicionalmente (`start -= startTime`, sem o `if`),
espelhando o que já é feito em `currentPlaybackTime`, e usar `max(0, ...)` se necessário
para tratar valores negativos residuais.

---

## Notas sobre as issues do upstream mencionadas no escopo

- **#403** (legendas não carregam em m3u8 live com AVPlayer por baixo): reproduzido e
  detalhado no finding **#3** acima — a causa raiz no fork atual é
  `KSAVPlayer.subtitleDataSouce` retornar sempre `nil`, e isso vale para qualquer
  conteúdo tocado pelo motor padrão (`KSOptions.firstPlayerType`), não só m3u8 live.
- **#885** (stutter/judder com frame rate matching + DV/HDR quando legendas ativas): não
  encontrei, lendo `KSOptions.updateVideo(refreshRate:isDovi:formatDescription:)`
  (`KSOptions.swift:338-357`) e o restante do pipeline de vídeo/Metal, nenhum código que
  correlacione a troca de `preferredDisplayCriteria` (frame rate matching do tvOS) com o
  estado de legendas ativas — a lógica de troca de refresh rate roda independente de
  `SubtitleModel`. Não consegui sustentar um finding específico de código para essa
  issue nesta varredura de `Sources/`; pode ser um comportamento do próprio
  `AVDisplayManager`/compositor do tvOS ao redesenhar a camada de overlay de texto
  durante uma troca de `isDisplayModeSwitchInProgress`, fora do código deste fork — não
  reportado aqui por falta de evidência direta no repositório.
