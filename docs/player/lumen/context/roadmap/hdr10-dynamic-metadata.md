**Dificuldade:** L · **Relevância:** crítica

## Abordagem proposta

O achado central desta pesquisa muda o enquadramento do problema: **não existe API pública da Apple para entregar metadado dinâmico HDR10+ (SMPTE ST 2094-40) ao compositor nativo em nenhuma plataforma Apple** — nem para `AVSampleBufferDisplayLayer`, nem para `CAMetalLayer`/EDR, nem via `VTDecompressionSession`.

- `CAEDRMetadata` (o tipo que `VideoVTBFrame.edrMetadata` já monta em `Model.swift:437-462`) só tem construtores estáticos: `.hdr10(displayInfo:contentInfo:opticalOutputScale:)` (payload SEI *Mastering Display Colour Volume* + *Content Light Level*, ambos estáticos — um valor para o filme inteiro) e `.hlg(ambientViewingEnvironment:)`. Não existe `.hdr10Plus(...)` nem qualquer variante que aceite uma curva por cena/frame. Confirmado na documentação oficial (`CAEDRMetadata`, TN3145, WWDC21 "Explore HDR rendering with EDR", WWDC22 "Explore EDR on iOS").
- `kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata` (já ativado em `VideoToolboxDecode.swift:142-145`, motivo do comentário em `KSOptions.swift:255`) é especificamente sobre metadado **Dolby Vision perfil 8.4** por frame — não sobre HDR10+. Não existe um `kCVImageBuffer*` attachment key documentado para carregar ST 2094-40 num `CVPixelBuffer`.
- `AVPlayer.HDRMode`/`DynamicRange` (`PlayerDefines.swift:45-91`) não têm caso para HDR10+: o valor `.hdr10` é o mesmo tanto para HDR10 estático quanto para HDR10+ — a Apple trata a parte "dinâmica" como um comportamento interno e opaco do próprio pipeline nativo `AVPlayer`/`AVURLAsset`, nunca exposto a apps de terceiros que fazem seu próprio demux/decode (como o motor `MEPlayer`/FFmpeg deste fork).

Isso implica que **terminar de "ligar" o parsing morto de `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` (`FFmpegDecode.swift:102-103`) na forma óbvia — popular um `EDRMetaData`-like e jogar num `CAEDRMetadata`** — não produziria tone mapping dinâmico nenhum, porque o tipo de destino não tem onde guardar isso. Sobram duas estratégias reais, não mutuamente exclusivas:

> **Correção (2026-07-25): a estratégia A abaixo está errada no ponto central — ela não é "de graça".** O passthrough do SEI é necessário mas não suficiente: sem a brand `cdm4` declarada em `SUPPLEMENTAL-CODECS` na playlist, o tvOS trata o stream como HDR10 estático. Ver "Resultado da execução" no fim deste documento antes de agir sobre este parágrafo. A estratégia B continua válida como escrita.

**A) Passthrough "de graça" via o pipeline nativo `AVPlayer` (depende do item de roadmap "MKV com Dolby Vision e Atmos nativos via AVPlayer")** — quando existir o remux local MKV→HLS/fMP4 (stream-copy) alimentando `KSAVPlayer`/`AVURLAsset` (ver `context/investigation/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md`, hoje Ausente), o SEI de HDR10+ sobrevive ao remux sem re-encode, e o próprio tvOS (Apple TV 4K 3ª geração+, tvOS 16+ — HDR10+ é suportado a nível de sistema desde então) aplica o tone mapping dinâmico sozinho, de ponta a ponta, sem nenhum código deste pacote. **Esse caminho não usa nem valida nada do parsing hoje presente no `MEPlayer`/`FFmpegDecode.swift`** — resolve o problema só para o subconjunto de conteúdo que passar por aquele pipeline nativo, e o parsing morto continua morto e irrelevante para ele.

**B) Tone mapping manual via shader, só no caminho Metal custom** — usar os campos já extraídos de `AVDynamicHDRPlus` (curva Bezier + knee point + `targeted_system_display_maximum_luminance`, ST 2094-40 Anexo B) para aplicar a EETF (*Electro-optical-to-electro-optical transfer function*) por pixel no fragment shader, exatamente como `libplacebo`/`mpv` fazem hoje em código aberto (`haasn/libplacebo`, `shaders/colorspace.h`): parseiam a curva HDR10+ quando presente, senão caem para uma curva Bezier constante/estimativa de brilho de cena. Isso só é aplicável no caminho `CAMetalLayer` (`MetalPlayView.swift:185-219`, `Shaders.metal`), nunca no `AVSampleBufferDisplayLayer` — que é justamente o caminho **default e preferido hoje** (`KSOptions.isUseDisplayLayer()`, `KSOptions.swift:256-258`, com o comentário na linha 255 que citamos acima e que hoje sabemos ser impreciso quanto a HDR10+ dinâmico). Ou seja: essa feature entraria em tensão direta com a preferência atual por `displayLayer` — exigiria uma exceção que force o caminho Metal quando o frame carrega `AV_FRAME_DATA_DYNAMIC_HDR_PLUS`, abrindo mão do compositing por hardware/IOSurface nesses casos.

Escopo realista de MVP para B: tratar `num_windows == 1` (janela global) e aplicar só a curva Bezier de tone mapping (`tone_mapping_flag`/`knee_point_x,y`/`bezier_curve_anchors`) — ignorar os seletores elípticos multi-janela (`center_of_ellipse_*`, `semimajor/semiminor_axis_*`), que nenhuma implementação open-source de referência conhecida (`libplacebo` incluído) trata além do caso global. Implementar o espectro completo do Anexo B (múltiplas janelas, per-region blending) é trabalho de outra ordem de grandeza (XL).

## Arquivos e tipos afetados

- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:102-105` — hoje descarta `AVDynamicHDRPlus`/`AVDynamicHDRVivid` em variáveis locais; passaria a popular um novo struct Swift (ver abaixo) e a corrigir o bug adjacente de índice errado em `display_primaries_b_x` (linha 113-114, usa `.2.1.num` em vez de `.2.0.num` — não é HDR10+ dinâmico, mas está no mesmo bloco).
- `Sources/KSPlayer/MEPlayer/Model.swift:420-462` — `VideoVTBFrame` ganharia um campo novo (ex. `dynamicHDR10PlusMetaData: HDR10PlusMetaData?`) ao lado de `edrMetaData` (linha 429); `edrMetadata` computed var (437-462) precisaria de um caminho alternativo, já que `CAEDRMetadata` não tem construtor dinâmico — esse campo alimentaria o shader (estratégia B), não o `CAEDRMetadata`.
- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:45-137` — `DynamicRange` continua sem precisar de um novo `case` (HDR10+ reporta como `.hdr10` mesmo, igual ao comportamento nativo da Apple); mas a lógica de `updateVideo`/`AVDisplayCriteria` (`KSOptions.swift:339-357`) não muda nada aqui — HDR10+ dinâmico não afeta o *display mode matching* do tvOS, só o tone mapping do conteúdo.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:256-258` (`isUseDisplayLayer()`) — precisaria de uma exceção para forçar o caminho Metal quando `dynamicHDR10PlusMetaData != nil`, ou aceitar que HDR10+ dinâmico só funciona no fallback Metal (perdendo o caminho displayLayer/PiP para esse conteúdo).
- `Sources/KSPlayer/Metal/PixelBufferProtocol.swift` — precisaria expor a curva de tone mapping como parte do `PixelBufferProtocol` ou como parâmetro adicional entregue ao `MetalRender.draw`.
- `Sources/KSPlayer/Metal/MetalRender.swift:92-136` — ponto de injeção de mais um fragment buffer (curva Bezier — nós de controle + knee point + luminância alvo), ao lado dos já existentes (matriz YUV→RGB, offset, `leftShift`, linhas 116-136); precisa reusar um `MTLBuffer` por instância (não alocar por frame — mesma pegadinha já documentada para `VRDisplayModel`/`VRBoxDisplayModel` em `docs/06-render-de-v-deo-e-hdr.md`).
- `Sources/KSPlayer/Metal/Shaders.metal:69-81` — `shaderLinearize`/`shaderDeLinearize` já implementam a EOTF/OETF PQ (ST 2084); o tone mapping ST 2094-40 Anexo B entraria como um passo novo entre essas duas chamadas (hoje só usadas por `displayYCCTexture`, linhas 83-103, dedicado a Dolby Vision P5 IPTPQc2→LMS→RGB e também não referenciado por nenhum pipeline Swift — mesmo "esqueleto morto" documentado em `docs/06`).
- `Sources/KSPlayer/Metal/DisplayModel.swift` — `pipeline(planeCount:bitDepth:)` precisaria de uma variante de pipeline que inclua o passo de tone mapping dinâmico.
- Fora deste pacote: nenhuma mudança em `KSAVPlayer.swift` é necessária para a estratégia A — o ganho vem de graça pelo remux + AVPlayer nativo, sem tocar código HDR aqui.

## Dependências

- **Nenhuma dependência bloqueante do upgrade FFmpeg 6.1→8.x**: `hdr_dynamic_metadata.h`/`av_dovi_get_header`/`av_dovi_get_mapping`/`av_dovi_get_color` já existem e compilam na versão 6.1.4 hoje empacotada (`context/investigation/ffmpeg-version-bundled.md`, status Presente) — os side data já chegam ao `FFmpegDecode.swift` como está.
- **Sobreposição de infraestrutura com "Dolby Vision dynamic metadata P5/P8/P7"** (`context/investigation/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md`, status Parcial): ambas as features precisam do mesmo tipo de canal novo — "metadado dinâmico por frame → tone mapping por shader no caminho Metal" — já que o RPU do Dolby Vision profile 5 (sem base layer compatível) tem exatamente o mesmo problema de ausência de API nativa que o HDR10+. Recomenda-se desenhar/implementar as duas juntas para não duplicar a plumbing (novo campo em `VideoVTBFrame`, novo fragment buffer no `MetalRender`, exceção em `isUseDisplayLayer()`) duas vezes.
- **Dependência estratégica (não bloqueante) do item "MKV com Dolby Vision e Atmos nativos via AVPlayer"** (`proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md`, status Ausente): se esse remux local existir, ele resolve HDR10+ "de graça" (estratégia A) para o subconjunto de conteúdo que passar por ali, tornando o trabalho da estratégia B menos urgente para esse subconjunto — mas não elimina a necessidade de B para conteúdo tocado pelo motor `MEPlayer`/FFmpeg (o caminho principal hoje para streams HTTP de debrid, que é o uso real do StreamHub).

## Riscos e incógnitas

- **Raridade real vs. prioridade nomeada**: HDR10+ é bem mais raro que Dolby Vision ou HDR10 estático nos releases 4K WEB-DL/remux típicos de debrid (a maior parte do catálogo Ultra HD Blu-ray e streaming é HDR10 puro ou Dolby Vision; HDR10+ concentra-se em conteúdo Amazon/Samsung e alguns UHD BDs). Vale medir, antes de investir, que fração real do catálogo consumido pelo StreamHub carrega `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` — o esforço de implementar a EETF corretamente é significativo (estratégia B) para um payoff que pode ser visualmente sutil.
- **Dificuldade de validação sem hardware/amostra de referência**: não há um jeito automatizado de confirmar visualmente que a curva de tone mapping está correta sem comparar lado a lado com uma TV certificada HDR10+ (ou com o próprio Apple TV 4K 3ª geração rodando o mesmo arquivo via app nativo/Infuse). Amostras HDR10+ livres para teste são escassas.
- **Conflito com a preferência atual por `AVSampleBufferDisplayLayer`**: implementar a estratégia B exige desviar HDR10+ dinâmico para o caminho Metal, que em tvOS não expõe `edrMetadata` no `CAMetalLayer` (`#if !os(tvOS)` em `MetalPlayView.swift:213-217`, documentado em `docs/06`) — ou seja, mesmo com a curva aplicada manualmente nos pixels, o EDR/HDR real da tela em tvOS depende só do `colorspace`/matching do `AVDisplayCriteria`. Isso é factível (a curva vira parte dos valores de pixel entregues, não metadado separado), mas é mais uma camada de indireção sobre um caminho que hoje não é o default.
- **Casos de conteúdo dual-perfil (Dolby Vision + HDR10+)**: alguns UHD Blu-ray rips carregam ambos os metadados simultaneamente; mesmo o Infuse — referência de qualidade citada no objetivo deste projeto — tem bugs reportados nesse cenário-limite (thread "Unable to play HDR10+ from a dual profile DV/HDR10+ files", community.firecore.com), sinal de que a prioridade entre os dois metadados dinâmicos não é trivial de resolver nem para apps maduros.
- **Alocação por frame no hot path**: se a implementação não reusar `MTLBuffer`s para os coeficientes da curva (mesma armadilha já vista em `VRDisplayModel`/`VRBoxDisplayModel`, `docs/06`), o custo de alocação por frame pode comprometer o frame pacing em conteúdo 4K/HFR.
- **Rebaixamento silencioso já é o comportamento atual**: hoje, conteúdo HDR10+ já funciona — só que como HDR10 estático (via `MASTERING_DISPLAY_METADATA`/`CONTENT_LIGHT_LEVEL`, que são de fato consumidos, `FFmpegDecode.swift:106-133`). Uma implementação incorreta ou malfeita da EETF dinâmica pode produzir resultado visual **pior** que simplesmente manter esse fallback estático atual — o bar de "correto o suficiente para valer a pena" é alto.

## Referências

- Apple Developer, `CAEDRMetadata` — https://developer.apple.com/documentation/quartzcore/caedrmetadata (só expõe `.hdr10(...)` estático e `.hlg(...)`, sem variante dinâmica/HDR10+)
- Apple Developer, TN3145 "HDR video metadata" — https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata
- Apple Developer, WWDC21 10161 "Explore HDR rendering with EDR" — https://developer.apple.com/videos/play/wwdc2021/10161/
- Apple Developer, WWDC22 10113 "Explore EDR on iOS" — https://developer.apple.com/videos/play/wwdc2022/10113/
- Apple Developer, "High Dynamic Range Metadata for Apple Devices" (PDF, preliminar) — https://developer.apple.com/av-foundation/High-Dynamic-Range-Metadata-for-Apple-Devices.pdf
- Apple Developer / Microsoft Learn (Xamarin bindings), `kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata` — confirma escopo Dolby Vision perfil 8.4, não HDR10+ — https://learn.microsoft.com/eu-es/dotnet/api/videotoolbox.vtdecompressionpropertykey
- Apple Support, "About 4K, HDR, HDR10+, and Dolby Vision on your Apple TV 4K" — https://support.apple.com/en-us/102339 (confirma HDR10+ só na 3ª geração do Apple TV 4K, suporte a nível de sistema desde tvOS 16)
- FFmpeg, `libavutil/hdr_dynamic_metadata.h` — https://github.com/FFmpeg/FFmpeg/blob/master/libavutil/hdr_dynamic_metadata.h (definição de `AVDynamicHDRPlus`/`AVHDRPlusColorTransformParams`/`AVHDRPlusPercentile`, já usada nos structs deste fork)
- `haasn/libplacebo`, `src/include/libplacebo/shaders/colorspace.h` e discussão #294 "Tonemapping HDR to SDR with libplacebo" — https://github.com/haasn/libplacebo (implementação de referência open-source da EETF do ST 2094-40 Anexo B, usada por mpv/FFmpeg `vf_libplacebo`)
- AOMediaCodec, "HDR10+ AV1 Metadata Handling Specification" — https://aomediacodec.github.io/av1-hdr10plus/ (estrutura de referência do ST 2094-40, formato-agnóstico quanto ao codec)
- kingslay/KSPlayer, issue #875 "Add native Dolby Vision & Atmos via AVPlayer" — https://github.com/kingslay/KSPlayer/issues/875 (confirma que Dolby Vision "nativo" no ecossistema KSPlayer depende do caminho `AVPlayer`, não do motor FFmpeg/MEPlayer — mesma lógica que se aplica a HDR10+)
- Firecore/Infuse community, "Unable to play HDR10+ from a dual profile DV/HDR10+ files" — https://community.firecore.com/t/unable-to-play-hdr10-from-a-dual-profile-dv-hdr10-files/41524
- Firecore/Infuse community, "Where's HDR10+ support to Apple TV 4K 3rd?" — https://community.firecore.com/t/wheres-hdr10-support-to-apple-tv-4k-3rd/43034
- `context/investigation/hdr10-dynamic-metadata.md` (este repositório) — investigação de origem que motivou este roadmap.
- `context/investigation/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md` (este repositório) — feature irmã com a mesma lacuna de plumbing.
- `context/investigation/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md` (este repositório) — dependência estratégica não bloqueante (estratégia A).
- `docs/04-decodifica-o.md` e `docs/06-render-de-v-deo-e-hdr.md` (este repositório) — mapeamento de arquivos/tipos/pegadinhas do pipeline de decode e render usados nesta pesquisa.

---

## Resultado da execução (2026-07-25) — [[hdr10plus]] entregue (código); a estratégia A precisava de código

Seção adicionada na baixa da task. A análise das duas estratégias acima fica como estava, **exceto pelo ponto corrigido aqui**. Detalhe completo em [../exec/paridade-infuse-2026-07-25.md](../exec/paridade-infuse-2026-07-25.md).

### O que esta pesquisa errou

A estratégia A foi escrita como "o SEI sobrevive ao remux sem re-encode e o tvOS aplica o tone mapping sozinho, **sem nenhum código deste pacote**". O card do `ROADMAP.md` herdou isso ("estratégia A: nenhum código HDR novo — é validação sobre o ProAVPlayer entregue"). **É falso.**

O passthrough do SEI é condição necessária, não suficiente. Em 2024 a Apple definiu como HDR10+ se declara em HLS: o atributo **`SUPPLEMENTAL-CODECS`** da `#EXT-X-STREAM-INF`, com a brand **`cdm4`** (a mesma brand do CTA-5001 / spec HDR10+ da AOM) anexada à string de codec da base layer, junto com `VIDEO-RANGE=PQ`. A forma é `SUPPLEMENTAL-CODECS="hvc1.2.20000000.L123.B0/cdm4"` — exatamente o exemplo que aparece no material público da Apple, e o appendix lista a forma análoga para AV1 (`av01…/cdm4`, PQ). **Sem esse atributo o tvOS não sabe que existe metadado dinâmico e trata o stream como HDR10 estático**, mesmo com o SEI ST 2094-40 intacto dentro do bitstream — que é precisamente o "rebaixamento silencioso" que a seção de riscos deste doc já descrevia como o comportamento atual.

Consequência prática: a estratégia A é **S de esforço mas não é zero**, e o critério de aceite do card ("amostra HDR10+ ativa o modo HDR10+ na TV") nunca teria sido atingido só validando.

### O que a lane `signaling` implementou

- **`Sources/Lumen/MEPlayer/ProAVHDR10PlusScanner.swift`** (novo, puro, sem estado compartilhado): walker de NALs length-prefixed que filtra **prefix SEI (NAL type 39)**, desfaz o emulation prevention e casa **payload type 4** com country code `0xB5`, provider `0x003C`, provider oriented code `0x0001` e application identifier `4`. As constantes foram conferidas contra `itut35.c`/`itut35.h` do FFmpeg, não de memória.
- **Fiação em `MEPlayerItem`**: caminho barato primeiro (`coded_side_data` do stream, depois `AV_PKT_DATA_DYNAMIC_HDR10_PLUS` por packet), com o scanner de SEI como fallback; armado em `startProAVRemux`, aplicado a cada packet de vídeo em `writeProAVPacket` **antes** da lógica de corte, desarmado após `remuxMoovWritten`.
- **`ProAVRemuxSession.noteDynamicHDR10Plus()`** (flag sob lock, ignorada depois de `initBoundaryFound`) e `completeInitSegmentLocked` aplicando `signaling.addingDynamicHDR10Plus()` antes de escrever a master.
- **Brand `cdm4` também nas compatible brands do `ftyp`** do init segment. A spec HDR10+ da AOM referenciando CTA-5001 diz que a brand "should be used in the ftyp box"; é barato aqui porque o init segment chega inteiro como `Data` e o fMP4 usa `default_base_moof` + `skip_sidx` (sem offset absoluto), com init e segmentos em arquivos separados. Qualquer falha de parse grava o init original — a sessão nunca morre por isso.

### Janela de timing: por que funciona

Com `+delay_moov` e `frag_custom` o muxer não emite nada até o primeiro corte, e o `ProAVInitBoundaryScanner` devolve `.buffering` até aparecer uma caixa `moof`. Ou seja, `completeInitSegmentLocked` (e a escrita da master) só pode rodar no primeiro flush de fragmento — **todos os packets da primeira janela (~2 s) já passaram pelo scan nessa altura**. O gate é simplesmente `!remuxMoovWritten`, sem corrida. Sem deadlock: `noteDynamicHDR10Plus` pega o mesmo `NSLock` de `write(buffer:)`, mas roda antes de qualquer `av_write_frame` da mesma invocação.

### Desempate Dolby Vision × HDR10+ (o cenário-limite que a seção de riscos apontava)

Resolvido **estruturalmente**, sem checagem extra: `addingDynamicHDR10Plus()` só age quando `codecTag == "hvc1" && videoRange == "PQ" && supplementalCodecs == nil`. Isso exclui DV 5 e 8.1 (`dvh1`), DV 8.2 e 8.4 (já têm `supplementalCodecs`), 8.4/HLG (range) e H.264 (`avc1`). Um rip dual-profile DV+HDR10+ sai anunciado como Dolby Vision, nunca como os dois — que é a escolha do Infuse e evita o bug de prioridade que a pesquisa citou.

Com a flag desligada nada muda: playlist e init segment saem byte-idênticos (há teste comparando a master contra a string literal completa).

### O que continua aberto

- **Nenhuma validação em hardware.** Não dá para provar em teste unitário que o tvOS aplica tone mapping dinâmico com `SUPPLEMENTAL-CODECS=".../cdm4"`. Falta um título HDR10+ real numa TV que suporte.
- **O fio completo `side data → SEI → flag` não tem teste** (exige mídia real). Provado por partes: scanner (14 testes com fixtures inline) e sessão.
- **Efeito da brand no `ftyp` desconhecido.** Se a mídia parar de tocar com a brand presente, remover é diff de 3 linhas em `ProAVRemuxSession.swift`.
- **A estratégia B continua não iniciada e continua a resposta certa para o caminho `KSMEPlayer`** — o `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` segue sendo lido e jogado fora em `FFmpegDecode.swift`. Nada nesta entrega mudou isso, e a recomendação de medir a fração real do catálogo antes de investir continua válida.
