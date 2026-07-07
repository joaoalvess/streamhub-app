<div align="center">

# 📺 StreamHub

**A native tvOS streaming hub that aggregates movies, series and anime through Stremio-style addons.**

![Platform](https://img.shields.io/badge/platform-tvOS-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-F9A825)
![License](https://img.shields.io/badge/license-MIT-4C9AFF)

</div>

---

StreamHub is an Apple TV app that brings movies, series and anime into a single, focus-driven interface. Instead of juggling isolated services, it aggregates **discovery** (catalogs & metadata) and **playback** (stream sources) through addons that speak the Stremio Addon Protocol — but run **natively and in-process** inside the app, rather than as remote HTTP services.

> 🇧🇷 🇵🇹 Built with a Portuguese-speaking audience in mind (PT-BR / PT-PT).

> ⚠️ **Early stage.** The tvOS interface is in place (currently powered by mock data) and the architecture is fully documented. Native addon integration and external-player handoff are specified under [`docs/`](docs/) and tracked on the roadmap below.

## ✨ Highlights

- 🧩 **Native Stremio-style addons** — catalog, metadata, stream and subtitle providers as in-process Swift objects, aggregated in parallel by content type and ID prefix.
- 🎬 **Rich catalogs** — focus-driven home with a hero banner, horizontal shelves, Top 10 and "Continue Watching".
- 🌊 **Stream aggregation** — pulls ready-to-play HTTP(S) sources from a self-hosted [AIOStreams](https://github.com/Viren070/AIOStreams) setup (multi-scraper + TorBox debrid) split into three server-side profiles — dubbed PT-BR, subtitled and anime — so the first result is always the right one.
- ▶️ **External player handoff** — opens streams in [Infuse](https://firecore.com/infuse) via `x-callback-url`, with two-way resume, external subtitles and TMDB metadata.
- 🍿 **Native fallback player** — `AVPlayer`-based playback for HLS / MP4 / Matroska when Infuse isn't available.

## 🏗️ Architecture

StreamHub is organized around three documented pillars:

| Pillar | What it does | Docs |
| --- | --- | --- |
| 🧩 **Addons** | Stremio Addon Protocol reused as native in-process providers (manifest, catalog, meta, stream, subtitles) | [`docs/addons/`](docs/addons/) |
| 🌊 **Streams API** | Self-hosted AIOStreams returning aggregated, debrid-backed playback URLs | [`docs/api/streams/`](docs/api/streams/) |
| ▶️ **Infuse Player** | External playback via the `infuse://x-callback-url/play` scheme | [`docs/player/infuse/`](docs/player/infuse/) |

## 🛠️ Tech Stack

- **Language:** Swift / SwiftUI
- **Platform:** tvOS (Apple TV)
- **Build:** Xcode (`StreamHub.xcodeproj`)
- **Playback:** AVFoundation (native) + Infuse (external)
- **Content protocol:** Stremio Addon Protocol (native implementation)

## 📂 Project Structure

```text
StreamHub/
├── StreamHub/            # SwiftUI app — Models, Features, Navigation, Theme
├── StreamHubTests/       # Unit tests
├── StreamHubUITests/     # UI tests
├── docs/
│   ├── addons/           # Addon protocol, manifest, resources, SDK
│   ├── api/streams/      # AIOStreams API reference
│   ├── api/metadata/     # AIOMetadata discovery API
│   └── player/infuse/    # Infuse integration & URL schemes
└── references/           # UI design references
```

## 🚀 Getting Started

> Requires macOS with Xcode and an Apple TV simulator (or device) running a recent tvOS.

```bash
git clone git@github.com:joaoalvess/StreamHub.git
cd StreamHub
open StreamHub.xcodeproj
```

Select the **StreamHub** scheme and an **Apple TV** destination, then build & run (⌘R).

## 🗺️ Roadmap

- [x] tvOS interface (home, hero, shelves, Top 10, Continue Watching)
- [x] Technical documentation (addons, streams API, Infuse)
- [ ] Native addon layer (Codable models, addon manager, parallel aggregation)
- [ ] AIOStreams / AIOMetadata integration
- [ ] Infuse handoff with two-way resume
- [ ] Native AVPlayer playback & subtitles

## 📚 Documentation

Full technical documentation lives in [`docs/`](docs/) and is the source of truth for the addon protocol, the streams API and the Infuse integration.

## 📄 License

Released under the [MIT License](LICENSE) © 2026 João Alves.
