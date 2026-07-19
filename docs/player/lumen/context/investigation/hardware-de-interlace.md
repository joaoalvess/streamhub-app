# Hardware De-interlace

## Status

Parcial.

Existe um branch de código explicitamente pensado para de-interlace via hardware (`yadif_videotoolbox`), mas ele está desativado no próprio código por causa de um crash conhecido, e nunca é alcançável em runtime. Todo o de-interlace efetivo hoje roda via filtro FFmpeg em software (`yadif` / `idet`), independente de `hardwareDecode` estar ligado.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:310-336` — `KSOptions.process(assetTrack:)`: detecta `fieldOrder` intercalado (`bb`/`bt`/`tt`/`tb`) e monta a cadeia de filtros de de-interlace.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:313-316` — comentário `// todo 先不要用yadif_videotoolbox，不然会crash` seguido de `hardwareDecode = false` incondicional, e só depois o ternário `hardwareDecode ? "yadif_videotoolbox" : "yadif"`. Como `hardwareDecode` acabou de ser forçado a `false` na linha anterior, o ternário sempre resolve para `"yadif"` — o branch hardware é código morto inalcançável.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:330` — `videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")`: string de filtro FFmpeg efetivamente usada.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:79` — `public var autoDeInterlace = false`: flag de detecção automática via filtro `idet` (software).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:270-301` — `filter(log:)`: faz parsing do log do filtro `idet` (linhas `"Repeated Field:"`) para inferir `videoInterlacingType` (tff/bff/progressive/undetermined) e desligar `autoDeInterlace` quando decide o tipo. Puramente lógica de detecção, roda em CPU.
- `Sources/KSPlayer/MEPlayer/Filter.swift:105-131` — `KSFilter.filter(options:inputFrame:completionHandler:)`: monta e executa o `avfilter_graph` com a string de `videoFilters`/`audioFilters`. Aceita frames com `hw_frames_ctx` (linha 126-128, repassa o buffer de hw frames pro grafo), mas isso é só para permitir hw frames *atravessarem* filtros (ex. escala), não implica que o filtro de de-interlace em si rode em hardware — `yadif` puro processa em CPU mesmo recebendo um frame com contexto de hw (haveria erro/fallback se o formato não bater, mas neste código o branch hw nunca é selecionado de qualquer forma).
- `Sources/KSPlayer/MEPlayer/Model.swift:87-88` — `static var yadifMode = 1` e `static var deInterlaceAddIdet = false`: flags de configuração globais estáticas (não expostas como opção de UI/perfil no que foi verificado neste arquivo).
- Busca `rg -i "vaapi|videotoolbox.*deint|deinterlace_vt|yadif_cuda"` não retornou nenhum outro caminho de hardware de-interlace (via VideoToolbox nativo, VTDecompressionSession, ou filtro `deinterlace_vt`/`vaapi`) além dessa única linha morta.

## Como funciona (fluxo real, sempre cai no caminho software)

1. Ao processar um `assetTrack` de vídeo, `KSOptions.process(assetTrack:)` verifica `fieldOrder` do stream (vindo do FFmpeg/AVFormat). Se indicar campos intercalados, entra no bloco de de-interlace.
2. O código força `hardwareDecode = false` e `asynchronousDecompression = false` incondicionalmente — ou seja, mesmo que o usuário/app tivesse decodificação por hardware ligada, ela é desligada nesse caso, e o filtro selecionado é sempre `"yadif"` (software), nunca `"yadif_videotoolbox"`.
3. Opcionalmente adiciona `idet` antes do `yadif` (`KSOptions.deInterlaceAddIdet`, default `false`) para permitir detecção mais precisa via log parsing (`filter(log:)`).
4. A string de filtro final (`yadif=mode=...:parity=-1:deint=1`) é concatenada em `videoFilters` e, no pipeline de decodificação (`Filter.swift`), executada via `libavfilter` (`avfilter_graph_parse_ptr` + `avfilter_graph_config`), processando pixel a pixel em CPU.
5. Separadamente, `autoDeInterlace` (flag pública, default `false`) ativa detecção automática via filtro `idet` sem forçar de-interlace: o log é interpretado em `filter(log:)` para decidir se o conteúdo é progressivo/tff/bff e ajustar `videoInterlacingType`, mas essa via também não envolve qualquer aceleração de hardware.

## O que falta

Para ter de-interlace por hardware de verdade (paridade com Infuse/KSPlayer pago), seria necessário:

- Reativar/consertar o branch `yadif_videotoolbox` em `KSOptions.swift:310-336`: hoje ele é inalcançável porque `hardwareDecode` é zerado antes do ternário ser avaliado. Resolver o crash mencionado no comentário (provavelmente relacionado a formato de pixel/`hw_frames_ctx` incompatível entre o decoder de hardware do VideoToolbox e o filtro `yadif_videotoolbox` do FFmpeg) e então permitir `hardwareDecode` permanecer `true` quando esse filtro for usado.
- Verificar/gerenciar corretamente `hw_frames_ctx` em `Filter.swift:105-131` para o caso do filtro de hardware — hoje o código só repassa o buffer (`av_buffer_ref`) sem tratamento específico para filtros VideoToolbox.
- Alternativamente, avaliar um caminho por VTDecompressionSession/VideoToolbox nativo (fora do libavfilter) caso o filtro FFmpeg `yadif_videotoolbox` não seja viável em tvOS/iOS — não há hoje nenhum esboço desse caminho alternativo no código.
- Expor a escolha de hardware vs. software de-interlace como opção de usuário/perfil (hoje `yadifMode` e `deInterlaceAddIdet` são `static var` fixas em `Model.swift:87-88`, sem UI/KSOptions pública documentada para o usuário final ajustar).
- Adicionar testes/validação em tvOS real (o comentário indica que o crash foi observado empiricamente, então qualquer reativação exige verificação em dispositivo).
