# Use fonts embedded in the video to render subtitles

## Status

Ausente.

## Evidência

- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:179` — parsing do bloco `[Aegisub Project Garbage]`/inline do ASS lê `fontName`.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:241-242` — `UIFont(name: fontName, size: CGFloat(fontSize)) ?? UIFont.systemFont(ofSize: CGFloat(fontSize))`: se a fonte citada pelo estilo ASS não estiver instalada no SO, cai silenciosamente para a fonte do sistema.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:252-262` — mesmo padrão de fallback ao montar `ASSStyle` a partir de `Fontname`/`Fontsize`, incluindo `UIFontDescriptor(name:matrix:)`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:283-317` — único ponto do player que itera `codecpar.pointee.codec_type` sobre os streams do `AVFormatContext`; trata apenas `AVMEDIA_TYPE_AUDIO`, `AVMEDIA_TYPE_VIDEO` e `AVMEDIA_TYPE_SUBTITLE` (e mesmo assim só no contexto de `startRecord`/remuxing, não no pipeline normal de playback). Nenhuma menção a `AVMEDIA_TYPE_ATTACHMENT`.
- Busca em todo `Sources/` por `AVMEDIA_TYPE_ATTACHMENT`, `CTFontManagerRegister`, `registerFont`, `fontconfig`, `libass`, `fontsdir` não retornou nenhuma ocorrência.

## O que falta

Não existe nenhum esboço da feature. Para implementar do zero seria necessário:

1. **Extrair os anexos do contêiner**: no loop de streams do `AVFormatContext` (padrão já presente em `MEPlayerItem.swift:283`, mas seria um novo trecho no caminho de abertura normal, não em `startRecord`), tratar `codecpar.pointee.codec_type == AVMEDIA_TYPE_ATTACHMENT`. Cada stream de anexo expõe o nome do arquivo e o mimetype via `av_dict_get(stream.pointee.metadata, "filename"/"mimetype", ...)`, e os bytes da fonte ficam em `codecpar.pointee.extradata`/`extradata_size`.
2. **Persistir/registar as fontes**: gravar os bytes extraídos em arquivo temporário (ou usar `CTFontManagerRegisterGraphicsFont`/`CTFontManagerRegisterFontsForURL` a partir de `Data` em memória) antes de o parser ASS resolver os nomes de fonte.
3. **Conectar ao parser de legendas**: `AssParse` (`KSParseProtocol.swift:39` em diante) precisaria consultar essas fontes registradas em vez de depender apenas de `UIFont(name:)` contra as fontes do sistema — isto é, o registro tem que acontecer antes do primeiro `UIFont(name: fontName, ...)` ser chamado, e o fallback silencioso para `systemFont` deveria só ocorrer se o registro também falhar.
4. **Ciclo de vida**: as fontes registradas via `CTFontManagerRegisterFontsForURL`/`RegisterGraphicsFont` precisam ser des-registradas (`CTFontManagerUnregisterFontsForURL`/`UnregisterGraphicsFont`) ao trocar de mídia, para não vazar fontes entre reproduções.

Nenhum desses pontos (extração de anexos, registro CoreText, hook no parser) existe hoje no código; a análise foi feita inteiramente por ausência de evidência (greps exaustivos sem hits), não por suposição.
