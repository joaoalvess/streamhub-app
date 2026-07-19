# AV1 hardware decoding

## Status

Ausente.

## Evidência

- Busca `rg -ni "av1"` em todo o repositório (`*.swift`, `*.h`, `*.m`) não retorna nenhum resultado — não existe nenhuma referência a AV1 (nem `AV_CODEC_ID_AV1`, nem `kCMVideoCodecType_AV1`) no código.
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:326-342` — `extension AVCodecID { var mediaSubType: ... }` mapeia explicitamente apenas H263, H264, HEVC, MPEG1/2/4 e VP9 para `CMFormatDescription.MediaSubType`. Não há `case AV_CODEC_ID_AV1`, então qualquer stream AV1 cai no `default` (retorna `nil`, ver linha ~320), o que impede a criação do `CMVideoFormatDescription` necessário para o VideoToolbox.
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:202-216` — `extension CMVideoCodecType { var avc: String }` também só trata `kCMVideoCodecType_MPEG4Video/H264/HEVC/VP9`; sem entrada para AV1 o path de hardware decode não sabe montar o box de extradata (`avcC`/`hvcC`/`vpcC`) correspondente.
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:131-133,196,225` — o pipeline de criação de `CMFormatDescription` depende de `codecpar.codec_id.mediaSubType` (que retorna nil para AV1) e de checagens específicas de VP9/HEVC para habilitar `EnableHardwareAcceleratedVideoDecoder`; não existe branch equivalente para AV1.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:85,477` — `hardwareDecode` é apenas um flag booleano genérico (liga/desliga VideoToolbox como um todo), sem qualquer seleção ou exceção por codec relacionada a AV1.

## O que falta

Não há nenhuma base/esboço para AV1 hardware decoding — é ausência total, não parcial. Para uma implementação futura, os pontos de entrada seriam:

1. `AVFFmpegExtension.swift` — adicionar `case AV_CODEC_ID_AV1: return CMFormatDescription.MediaSubType(rawValue: kCMVideoCodecType_AV1)` (o raw value já existe no VideoToolbox do sistema desde que a plataforma suporte AV1 em hardware, ex. Apple Silicon com decoder dedicado).
2. `VideoToolboxDecode.swift` — adicionar o case correspondente em `CMVideoCodecType.avc` para o box de extradata do AV1 (formato `av1C`), e verificar se o restante do decode path (`VideoToolboxDecode`, criação de `CMFormatDescription` via `CMVideoFormatDescriptionCreate`/`CMFormatDescriptionCreate`) precisa de tratamento específico de extradata AV1 (diferente de avcC/hvcC baseado em NAL units).
3. `FFmpegAssetTrack.swift:196-225` — estender a checagem que hoje é específica para VP9/HEVC (`EnableHardwareAcceleratedVideoDecoder`/`RequireHardwareAcceleratedVideoDecoder`) para também cobrir AV1.
4. Validar suporte de plataforma: nem todo hardware Apple decodifica AV1 (apenas chips recentes com decoder dedicado); seria necessário runtime capability check antes de forçar hardware path, com fallback para o decoder de software do FFmpeg (que já decodifica AV1 via libaom/dav1d se a lib estiver linkada — isso não foi verificado nesta investigação, é fora do escopo "hardware decoding").
