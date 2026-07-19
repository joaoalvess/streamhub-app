## Status

Ausente.

## Evidência

- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:150-207` — `KSSubtitle.parse` apenas decodifica a string (tentando encodings utf8/big5/gb18030/unicode) e delega a um parser de formato (`KSOptions.subtitleParses`, ex. SRT/ASS/VTT). Não há qualquer parâmetro de idioma-alvo nem chamada a serviço de tradução.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:233-386` — `SubtitleModel` (ObservableObject) gerencia apenas: fontes de legenda (`subtitleDataSouces`), busca de legenda por tempo (`subtitle(currentTime:)`), seleção de faixa (`selectedSubtitleInfo`) e reconhecimento de áudio (`AudioRecognize`, ou seja, transcrição, não tradução). Nenhum campo tipo `targetLanguage`, `translatedText` ou similar.
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift`, `Sources/KSPlayer/Subtitle/KSParseProtocol.swift`, `Sources/KSPlayer/Subtitle/AudioRecognize.swift` — os três outros arquivos do módulo Subtitle também não têm nada relacionado (data source = onde buscar/cachear arquivos de legenda; parse protocol = parsers de formato; audio recognize = reconhecimento de fala on-device, feature distinta).
- `rg -ni "translat"` em todo `.swift` do repo — os únicos matches são `translatesAutoresizingMaskIntoConstraints` (Auto Layout) e `CGAffineTransform`/`translation` de gestos (`Slider.swift:141`, `Transforms.swift:27`). Nenhum resultado relacionado a tradução de texto/idioma.
- Nenhuma referência a serviços de tradução (DeepL, Google Translate, Microsoft Translator, Apple `Translation` framework, LibreTranslate) em nenhum arquivo do projeto.
- `README.md:49` — a própria tabela comparativa GPL-vs-pago do fork já documenta: `|Text subtitle translation|✅|❌|` (coluna paga = sim, coluna GPL/free = não), confirmando que o mantenedor original sabe que esta é uma feature exclusiva da versão paga e que este fork (coluna ❌) não a possui.

## O que falta

Não existe nenhuma base/esboço para esta feature — seria uma implementação nova do zero. Pontos de partida prováveis:

- **Modelo de dados**: `SubtitlePart` (`Sources/KSPlayer/Subtitle/KSSubtitle.swift:14-37`) teria que ganhar um campo opcional para texto traduzido (hoje só tem `text: NSAttributedString?` original), ou um mecanismo de segunda linha/legenda dupla.
- **Pipeline de tradução**: precisaria de um novo tipo análogo a `AudioRecognize` (protocolo em `Sources/KSPlayer/Subtitle/AudioRecognize.swift`) — algo como `SubtitleTranslate` — chamado depois do parse (`KSSubtitle.parse`, linha 176) ou sob demanda por `SubtitlePart`, integrando com uma API de tradução (on-device via `Translation` framework do Apple, disponível desde iOS/tvOS 17.4, ou serviço externo).
- **Configuração**: `KSOptions` (não localizado em `Sources/KSPlayer/Core/KSOptions.swift` — precisa achar o arquivo correto, possivelmente movido/renomeado) precisaria de flags como idioma-alvo de tradução e toggle de habilitar/desabilitar, análogas a `KSOptions.subtitleParses`/`subtitleDataSouces` já existentes.
- **UI**: `PlayerToolBar`/`VideoPlayerView` (`Sources/KSPlayer/Core/PlayerToolBar.swift`, `Sources/KSPlayer/Video/VideoPlayerView.swift:706-707`) exibem `subtitleLabel`/`subtitleBackView` — precisaria de toggle/seletor de idioma de tradução na UI e possivelmente exibição de legenda dupla (original + traduzida).
- **Cache/performance**: tradução teria custo (rede ou compute on-device) por linha de legenda, exigindo cache por `SubtitlePart` para não retraduzir a cada replay/seek.
