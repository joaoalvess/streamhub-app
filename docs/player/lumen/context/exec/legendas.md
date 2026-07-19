# Diário de execução — lane legendas

## Etapa: [[fontes-embutidas]] — fontes embutidas no MKV para render de legendas

**Branch:** `task/legendas` · **Worktree:** `/private/tmp/claude-501/-Users-joaoalves-Developer-StreamHub/113db3ca-fa39-47b3-8e07-30a97e5e0f39/scratchpad/wt-legendas`

**Commits:**
- `1d0c7bc` feat: add embedded font registry for subtitle rendering
- `37f087e` feat: register MKV font attachments from the demuxer
- `51f0a82` feat: resolve ASS font names against embedded fonts
- `8c4ce6d` fix: keep per-run subtitle fonts under the global font floor

### O que foi feito

Implementação completa conforme `context/roadmap/use-fonts-embedded-in-the-video-to-render-subtitles.md` (os 4 passos + o bloqueador funcional):

1. **Extração dos anexos** (`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`): novo ramo `else if` no loop de `createCodec` para `AVMEDIA_TYPE_ATTACHMENT` → `registerEmbeddedFont(stream:)` privado. Filtra por mimetype (`application/x-truetype-font`, `application/vnd.ms-opentype`, `font/ttf|otf|sfnt|collection`, `application/x-font-ttf|otf`, `application/font-sfnt`) ou, na ausência, por extensão `.ttf/.otf/.ttc` (heurístico do VLC). Bytes lidos de `codecpar.extradata`/`extradata_size`, metadata via `toDictionary` existente. Registro síncrono no `openThread`, antes de `read()` — nenhum parser de legenda roda antes disso.
2. **Registro CoreText** (novo `Sources/KSPlayer/Subtitle/EmbeddedFontRegistry.swift`): `CGDataProvider` → `CGFont` → `CTFontManagerRegisterGraphicsFont` (direto da memória, sem arquivo temporário). Singleton `@unchecked Sendable` com `NSLock` (registro no openThread, leitura na thread de decode de legenda — StrictConcurrency ok). Só tipos `Data`/`String`/CoreText na camada `Subtitle/` — nenhum tipo FFmpeg vaza (fronteira via `isFontAttachment(mimeType:filename:)` estático).
3. **Tabela de resolução de nomes**: cada fonte é indexada por PostScript name + family name + full name (`CTFontCopyName` com `kCTFontFamilyNameKey`/`kCTFontFullNameKey`), normalizados (trim + lowercase). `fontName(for:)` devolve o PostScript name para `UIFont(name:)`/`UIFontDescriptor(name:matrix:)` — cobre o mismatch family vs PostScript (risco central do doc). Os 3 pontos de `KSParseProtocol.swift` (`\fn` inline em `String.parseStyle`, `Fontname` e ramo `Angle` em `parseASSStyle()`) consultam o registry primeiro; fallback `UIFont(name:) ?? systemFont` intacto.
4. **Ciclo de vida**: `MEPlayerItem` tem `fontOwnerID = UUID()`; desregistro por dono em `shutdown()` (dentro do `closeOperation`, junto de `avformat_close_input`). Colisão de PostScript name entre trocas rápidas de mídia tratada: se a fonte já está registrada por outra instância, o registro é reaproveitado (erro tolerado, entry marcada `didRegister=false`); no desregistro, se outra instância viva usa o mesmo PostScript name, a registration é transferida (o `CGFont` registrado sobrevive) em vez de desregistrar por baixo dela.
5. **Bloqueador funcional** (`Sources/KSPlayer/Subtitle/KSSubtitle.swift`, `subtitle(currentTime:)`): o tick não sobrescreve mais `.font` no range inteiro — `enumerateAttribute(.font)` aplica `SubtitleModel.textFont` só onde `value == nil` (fonte global vira piso, não teto). Sem isso o resto seria código morto.
6. **Toggle**: `KSOptions.registerEmbeddedFonts = true` (static, junto dos outros statics de `KSOptions`).

### Arquivos

- `Sources/KSPlayer/Subtitle/EmbeddedFontRegistry.swift` (novo)
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` (ramo attachment + helper + desregistro no shutdown + `fontOwnerID`)
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift` (3 pontos de resolução de fonte)
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift` (fix do overwrite global)
- `Sources/KSPlayer/AVPlayer/KSOptions.swift` (toggle)

### Decisões

- `CTFontManagerRegisterGraphicsFont` (bytes em memória) em vez de `RegisterFontsForURL` — sem tmp files, conforme doc de contexto.
- Resolução devolve **PostScript name** e usa `UIFont(name:)` em vez de cast toll-free CTFont→UIFont — evita ambiguidade de bridging e funciona igual em UIKit/AppKit (`UIFont = NSFont` no macOS).
- `entries.last` na consulta: mídia aberta mais recentemente vence em nomes duplicados.
- Erro de registro (fonte corrompida/duplicada) é engolido silenciosamente — fallback é o comportamento atual (fonte do sistema), nunca falha de playback.
- Sem libass: `Package.swift` tem o produto `Libass` comentado (linha 25) — regra (e) proibia adicioná-lo. A extração implementada é a metade que sobrevive a uma futura migração para libass (`ass_add_font` substituiria só o consumidor).

### Pendências

- Sem PlayResX/Y → escala de tela: `Fontsize` do ASS é usado em pontos absolutos; num script 1080p a fonte pode render pequena na UI tvOS. Já era assim antes; agora fica visível porque o tamanho parseado não é mais sobrescrito pelo global. Se incomodar na validação, é trabalho da etapa libass/[[word-level]].
- Fontes com nome ofuscado (anti-leech de fansub) não resolvem — limitação de autoria upstream, não perseguir.
- Suíte de testes do pacote é no-op (fixtures ausentes) — sem cobertura automatizada, validação manual.
- Validação `swiftc -parse` OK nos 5 arquivos (sintaxe apenas); `swift build`/device é do dono.

### Como validar

1. `git -C <worktree> log --oneline` → 4 commits acima de `1b8b46f`.
2. Build tvOS e abrir um MKV de anime com fontes embutidas (attachments) + legenda ASS que referencia a família embutida (remux/WEB-DL comum). A legenda deve renderizar com a fonte do fansub, não com a system font.
3. Trocar de episódio da mesma release sem fechar o app (mesmas fontes re-embutidas) — não pode quebrar a fonte nem crashar.
4. `KSOptions.registerEmbeddedFonts = false` → comportamento antigo (system font) volta.
5. Regressão: SRT/VTT comuns continuam com `SubtitleModel.textFont` global (parsers não setam `.font` sem `\fn`/`Fontname`).
