# De-interlace auto detect

## Status
Presente.

## Evidência
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:38` — campo `fieldOrder: FFmpegFieldOrder` na track.
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:142` — `fieldOrder` é populado a partir de `codecpar.field_order` (metadado do FFmpeg), sem input do usuário.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:79` — flag `public var autoDeInterlace = false`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:90-91` — `@Published public var videoInterlacingType: VideoInterlacingType?`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:307-335` — `open func process(assetTrack:)`: se `assetTrack.fieldOrder` estiver em `[.bb, .bt, .tt, .tb]` (ou seja, o stream é sinalizado como entrelaçado), desativa hardware decode e injeta filtro `yadif`/`yadif_videotoolbox` automaticamente nos `videoFilters`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:270-300` — `open func filter(log:)`: faz parsing do log do filtro `idet` do FFmpeg em tempo real (`"Repeated Field:"` / `"Multi frame"`), contabiliza ocorrências de tff/bff/progressive/undetermined e, ao ultrapassar um limiar (>100), define `videoInterlacingType` e desliga `autoDeInterlace` — é uma segunda via de auto-detecção, dinâmica, durante a reprodução (útil quando o metadado do container não indica entrelaçamento mas o conteúdo é entrelaçado de fato).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:327-330` — quando `KSOptions.deInterlaceAddIdet` (flag estática) está ligado, o filtro `idet` é adicionado à cadeia antes do `yadif`, alimentando o parsing de log acima.
- `Sources/KSPlayer/MEPlayer/Filter.swift:110-113` — segunda camada: se `options.autoDeInterlace == true` e a cadeia de filtros de vídeo ainda não contém `"idet"`, adiciona `"idet"` automaticamente antes de montar a `AVFilterGraph`.
- `Sources/KSPlayer/MEPlayer/Model.swift:87-88` — `static var yadifMode = 1` e `static var deInterlaceAddIdet = false`, configuráveis globalmente via `KSOptions`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:453-456` — `enum VideoInterlacingType: String { case tff, bff, progressive, undetermined }`.

## Como funciona
Existem duas vias de auto-detecção que convergem no mesmo pipeline de filtros do FFmpeg (libavfilter), ambas sem exigir toggle manual do usuário:

1. **Detecção estática via metadado do container/codec** (`process(assetTrack:)`): ao abrir a track de vídeo, o `field_order` reportado pelo FFmpeg (`codecpar.field_order`) é inspecionado. Se indicar entrelaçamento (`bb`/`bt`/`tt`/`tb`), o player desativa decodificação por hardware (comentário no código explica que `yadif_videotoolbox` pode crashar) e injeta a string de filtro `"yadif=mode=X:parity=-1:deint=1"` na cadeia `videoFilters` do `KSOptions`, além de dobrar o `nominalFrameRate` quando `yadifMode` é 1 ou 3 (modo "send field").
2. **Detecção dinâmica via filtro `idet` + parsing de log** (`filter(log:)` + `Filter.swift:110-113`): quando `autoDeInterlace` está ativo, o filtro `idet` do FFmpeg é inserido na graph; seu log de análise quadro-a-quadro ("Repeated Field: ...", "Multi frame: tff:N bff:N prog:N undet:N") é interceptado pelo callback `filter(log:)` do `KSOptions`, que acumula contagens por tipo e, ao ultrapassar o limiar de 100 amostras de vantagem de um tipo sobre os demais, fixa `videoInterlacingType` e desativa `autoDeInterlace` (evita reprocessar depois de decidido).

Ambas as vias alimentam a mesma infraestrutura de `AVFilterGraph` usada pelo decoder por software (MEPlayer/FFmpeg), então o resultado é um deinterlace real aplicado ao vídeo, não apenas uma flag decorativa.

## O que falta
Não se aplica — feature presente e funcional de ponta a ponta no pipeline de software decode (MEPlayer/FFmpeg). Observações não-bloqueantes encontradas durante a investigação:
- O comentário em `KSOptions.swift:313` ("todo 先不要用yadif_videotoolbox...") indica que a variante acelerada por hardware (`yadif_videotoolbox`) está deliberadamente desabilitada por instabilidade (crash), então o auto-detect por metadado sempre força fallback para software decode quando aciona o yadif — isso é uma limitação de robustez, não de existência da feature.
- O bloco comentado em `KSOptions.swift:317-326` sugere que havia planos de ajustar `yadifMode` conforme a relação entre `realFrameRate`/`avgFrameRate` (heurística adicional para conteúdo telecined/PAL), mas está desativado — não impede a feature central de auto detect funcionar, apenas uma refinamento de heurística que ficou incompleto.
