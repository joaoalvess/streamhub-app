---
titulo: "Modo Enhanced — spec de implementação (serviço companion de remux + app)"
parte_de: "docs/enhanced"
objetivo: "Especificação completa para implementar o modo Enhanced do StreamHub: um serviço self-hosted com ffmpeg que junta o vídeo do melhor release (4K HDR/DV) com o áudio PT-BR de um release dublado, entregando uma URL única que o Infuse reproduz."
tipo: spec
relevancia_para_streamhub: alta
status: "aprovado pelo usuário — pronto para implementar sem nova entrevista"
depende_de:
  - "Fase 1 implementada no app: StreamsAPI, StreamSelector, PlaybackCoordinator, InfusePlayer, SecretsStore (ver seção 7)"
  - "docs/api/streams/ (contrato do AIOStreams)"
  - "docs/player/infuse/ (contrato do deep link)"
---

# Modo Enhanced — spec de handoff

> **Para a IA que vai implementar:** tudo neste doc já foi decidido com o usuário. Não é preciso
> re-perguntar produto ou arquitetura; apenas os itens marcados **[a validar]** exigem teste em
> runtime antes de virarem contrato. A fase 1 (dublado/legendado/streaming handoff/resume) já está
> no app — este doc cobre exclusivamente o que falta para o Enhanced.

## TL;DR

- **Produto:** terceiro modo do seletor de reprodução ("Enhanced"): vídeo do release de **maior
  qualidade** (4K HDR/Dolby Vision, tipicamente sem áudio PT) + faixa de **áudio PT-BR** de um
  release dublado — "o melhor dos dois mundos".
- **Por que um serviço:** o Infuse aceita **uma** URL de vídeo (+ `sub=`); não existe parâmetro de
  faixa de áudio externa. A junção acontece **server-side**: serviço companion self-hosted no mesmo
  host Tailscale do AIOStreams (`spark.tailcb6aa4.ts.net`), com **ffmpeg em modo remux** (`-c copy`,
  sem re-encode).
- **Fluxo:** app escolhe o par (vídeo top + áudio PT) → `GET /probe` valida sincronia → abre o
  Infuse com a URL `GET /play` do serviço → serviço puxa os 2 streams do CDN do TorBox e responde o
  MKV remuxado em chunked streaming.

## 1. Decisões fechadas (não re-perguntar)

| Decisão | Valor |
|---|---|
| Onde roda | Self-hosted, mesmo host Tailscale do AIOStreams (`spark.tailcb6aa4.ts.net`), porta própria |
| Stack | Node.js + ffmpeg via `spawn`, container Docker (compose) |
| Acesso | Restrito à tailnet + `key` simples em query string |
| Transcode | **Nunca.** Só remux (`-c copy`) — CPU irrisória, qualidade intacta |
| Elegibilidade | Ambos os candidatos **cacheados** (`[TB+]`); não-cacheado é inelegível |
| Par degenerado | Se o melhor vídeo já tem áudio PT (vídeo top == candidato áudio), pular o serviço e tocar direto (equivale ao Dublado) |
| Sincronia | Guard de duração `|durVideo − durAudio| ≤ 2.0s`; divergiu → erro + CTA de cair para Dublado (offset fino é v2) |
| Player | Infuse, mesmo handoff da fase 1 (`infuse://x-callback-url/play`), filename `"{título} ({ano}).mkv"` |
| UX de erro | Mensagens dedicadas: par incompatível, serviço offline; sempre sugerindo o modo Dublado como fallback |

## 2. Seleção do par (no app — infra já existe)

Usar `StreamSelector`/`StreamCandidate` da fase 1 (`StreamHub/Streams/`):

- **Candidato VÍDEO:** ranking do modo `subtitled` (melhor qualidade geral:
  `hasOriginalAudio > isCached > resolution > hdrScore > sizeBytes > seeds`), filtrado por
  `isCached == true`.
- **Candidato ÁUDIO:** ranking do modo `dubbed` restrito a `hasPTAudio == true` e
  `isCached == true`; empate → **menor** `sizeBytes` (só o áudio interessa; arquivo menor = remux
  mais leve para o servidor).
- Ambos precisam passar por `StreamSelector.validated(_:title:year:)` (defesa contra streams
  genéricos de ID inválido).
- Se `vídeo.videoURL == áudio.videoURL` → tocar direto no Infuse sem serviço.
- Sem par válido (não há PT cacheado, ou não há vídeo cacheado) → erro `enhancedNoPair` com
  sugestão de Dublado.
- **URLs frescas:** URLs de debrid expiram (token de sessão). Buscar `/stream` na hora do play
  (o cache de 60s do `PlaybackCoordinator` é aceitável; nunca persistir URLs).

## 3. API do serviço (v1 stateless)

Base: `http://{host-tailnet}:{porta}` — valores entram no app via `SecretsStore` (seção 7).

| Rota | Resposta | Uso |
|---|---|---|
| `GET /probe?video={urlenc}&audio={urlenc}&key={k}` | `200 {ok:true, videoDuration, audioDuration, delta, videoCodecs:[...], audioTracks:[{index, language, codec}]}` ou `409 {ok:false, reason:"duration_mismatch", delta}` | App chama antes do play; valida o par e falha cedo |
| `GET /play?video={urlenc}&audio={urlenc}&key={k}` | Corpo **chunked** com o MKV remuxado (`Content-Type: video/x-matroska`, sem `Content-Length`) | É esta URL que vai no `infuse://...play?url=` |
| `GET /health` | `200 {ok:true, ffmpegVersion}` | Diagnóstico/monitor |

Erros: `401` key inválida; `409 duration_mismatch`; `502 upstream_failed` (CDN do TorBox falhou);
`500 remux_failed`. Corpo sempre `{ok:false, reason}`.

**Segurança:** as URLs de vídeo/áudio carregam token do TorBox em claro — o serviço **não loga**
query strings; logs só com hosts truncados. `key` obrigatória em todas as rotas exceto `/health`.

## 4. Pipeline do serviço

1. **Probe:** `ffprobe -v quiet -print_format json -show_format -show_streams {url}` nas duas URLs
   (ffprobe segue o 302 do resolve → CDN). Extrair duração e faixas.
2. **Guard de sincronia:** `|durV − durA| > 2.0s` → `409 duration_mismatch`. (Releases com cortes
   ou framerates diferentes são o principal risco do Enhanced; a tolerância é o guard-rail v1.)
3. **Faixa PT:** no arquivo de áudio, escolher a faixa com `tags.language ∈ {por, pob, pt}`;
   sem tag → primeira faixa de áudio.
4. **Remux:**
   ```
   ffmpeg -i {videoUrl} -i {audioUrl} \
     -map 0:v:0 -map 1:a:{ptIdx} -map 0:a:0? -map 0:s? \
     -c copy -f matroska pipe:1
   ```
   (vídeo do arquivo A; áudio PT como faixa 1; áudio original do A como faixa 2 quando existir;
   legendas embutidas do A preservadas.)
5. **Resposta:** `pipe:1` → corpo HTTP chunked. Encerrar o processo ffmpeg se o cliente desconectar.

## 5. Limitações conhecidas / [a validar]

| Item | Estado | Plano B |
|---|---|---|
| **Seek** no Infuse com stream chunked (sem Range/206) | **[a validar em device]** — provável seek limitado/indisponível | Pre-mux em disco com cache TTL e servir com `206 Partial Content` (custo: espera inicial de minutos em arquivos grandes). Decidir com o usuário após o teste real |
| Infuse tocando MKV chunked via esquema | **[a validar]** | Mesmo pipeline com `-f mp4 -movflags frag_keyframe+empty_moov` (fMP4) |
| Compatibilidade DV profile no remux (DV em MKV) | **[a validar]** — DV profile 7/8 em MKV pode perder metadados no remux | Aceitar HDR10 como fallback visual; documentar perfis testados |
| Banda do host | Puxa 2 streams do CDN simultaneamente | Dimensionar; o áudio pequeno minimiza |
| Sincronia real (durações iguais ≠ sync perfeito) | Guard v1 = duração | v2: offset manual/auto-align por fingerprint |

## 6. Mudanças no app (fase 2)

Pontos de extensão **já existentes** na fase 1:

- `StreamHub/Playback/PlaybackMode.swift` → `isAvailable`: remover a exceção do `.enhanced`
  (hoje `self != .enhanced`); o seletor da `WindowInfoOverlay` habilita sozinho.
- `StreamHub/Playback/PlaybackCoordinator.swift` → protocolo `EnhancedStreamProvider` já declarado:
  ```swift
  protocol EnhancedStreamProvider {
      func remuxURL(video: StreamCandidate, audio: StreamCandidate, item: MediaItem) async throws -> URL
  }
  ```
  Implementar `RemuxServiceProvider` (chama `/probe`, monta `/play`) e injetar no coordinator.
  No `playViaInfuse`, o caso `.enhanced` passa a: selecionar par (seção 2) → provider → handoff
  Infuse idêntico (mesmo `registerSession`/resume).
- `StreamHub/Playback/SecretsStore.swift` → novas chaves `EnhancerBase` e `EnhancerKey` no
  `Secrets.plist`/Keychain (mesmo mecanismo de bootstrap).
- Novos `PlaybackError`: `enhancedNoPair` ("Não há um par de fontes compatível…"),
  `enhancedMismatch` ("As versões encontradas não são compatíveis entre si"),
  `enhancedServiceDown` ("O serviço Enhanced está inacessível") — todos sugerindo Dublado.
- Estado de UI: reutilizar `loading` do botão durante `/probe` (ou label "Preparando…").

## 7. O que a fase 1 já entrega (não refazer)

| Peça | Arquivo |
|---|---|
| Client `/stream` com throttle 5/5s e 429 | `StreamHub/Streams/StreamsAPI.swift` |
| Parsing de qualidade/idioma/cache (`[TB+]`, bandeiras, bingeGroup) | `StreamHub/Streams/StreamCandidate.swift` |
| Validação título/ano + rankings dublado/legendado | `StreamHub/Streams/StreamSelector.swift` |
| Handoff Infuse (builder/callback/launcher, schemes no Info.plist) | `StreamHub/Playback/InfusePlayer.swift` + `StreamHub/Info.plist` |
| Resume + Continue Watching (sessões por videoURL) | `StreamHub/Playback/PlaybackProgressStore.swift` |
| Orquestração, erros PT-BR, cache 60s, rota streaming-assinado | `StreamHub/Playback/PlaybackCoordinator.swift` |
| Segredos Keychain + bootstrap `Secrets.plist` | `StreamHub/Playback/SecretsStore.swift` |

## 8. Critérios de aceite

1. Filme com release 4K DV sem PT **e** release dublado 1080p → Enhanced abre o Infuse tocando
   vídeo 4K DV com áudio PT-BR.
2. Melhor vídeo já dublado → toca direto (sem passar pelo serviço).
3. Par com durações divergentes → alerta "versões incompatíveis" + sugestão de Dublado; nada trava.
4. Serviço desligado → alerta "serviço inacessível"; Dublado/Legendado seguem funcionando.
5. Sem release PT cacheado → alerta "sem par compatível".
6. Resume: sair do Infuse durante um Enhanced atualiza o Continue Watching como nos outros modos
   (a sessão é registrada com a URL do **serviço** — é ela que volta no `lastPlayedUrl`).
7. Nenhum log (app ou serviço) contém URLs com token.

## 9. Ordem de implementação sugerida

1. Serviço: `/health` + `/probe` (ffprobe, guard de duração) — testável com `curl` na tailnet.
2. Serviço: `/play` (remux chunked) — validar com `ffplay`/VLC apontando para a URL.
3. Teste manual no Infuse (Apple TV): URL `/play` direta via esquema — decide o [a validar] de seek/MKV.
4. App: chaves novas no `SecretsStore` + `RemuxServiceProvider` + erros novos.
5. App: habilitar `PlaybackMode.enhanced` e ligar o caso no coordinator.
6. Ajustes conforme os [a validar] (fMP4, pre-mux com Range, etc.).
