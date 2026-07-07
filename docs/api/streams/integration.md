# Integração no StreamHub (end-to-end)

> Como o StreamHub deve consumir esta API com robustez: montagem da URL, sequência de chamadas, rate limiting, cache, tratamento de erros, processamento da lista de streams e handoff para o player.

---

## 1. Fluxo completo

```
┌─ boot ────────────────────────────────────────────────┐
│ GET /manifest.json  (1x, cacheado, revalidado por ETag)│
└───────────────────────────────────────────────────────┘
        │ descobre tipos/idPrefixes suportados
        ▼
┌─ assistir um título ───────────────────────────────────────┐
│ resolver ID externo (tt… / mal:… / kitsu:…) ← AIOMetadata   │
│ escolher perfil: anime → anime; Dub → casual; Leg → cinema  │
│ GET {BASE do perfil}/stream/{type}/{id}.json                │
│   → tomar o 1º stream playável (ranking é server-side)      │
│   → reproduzir stream.url (handoff para o Infuse)           │
└─────────────────────────────────────────────────────────────┘

┌─ navegar biblioteca debrid ───────────────────────────┐
│ GET /catalog/other/{catálogo}.json  (paginar /skip=N)  │
│ GET /meta/other/{id}.json                              │
│   → reproduzir videos[].streams[].url                  │
└───────────────────────────────────────────────────────┘
```

Rotas: [manifest](./manifest.md) · [stream](./stream.md) · [catalog](./catalog.md) · [meta](./meta.md). O passo "resolver ID externo" usa a [API de metadados (AIOMetadata)](../metadata/README.md).

---

## 2. URL base e segredo

- Estrutura em [README §2](./README.md#2-anatomia-da-url-base). Guarde a **base completa de cada perfil** protegida no Keychain — chaves `AIOStreamsCinemaBase`/`AIOStreamsCasualBase`/`AIOStreamsAnimeBase`, bootstrap via `Secrets.plist` (`SecretsStore.swift`).
- A base inteira é credencial (o `CONFIG` carrega chaves de debrid criptografadas; as `url` de stream/meta carregam o **token TorBox em texto claro**). Nunca logar, nunca enviar a serviços externos, nunca exibir em UI.

---

## 3. Sequência e cache

| Chamada | Frequência | Cache |
|---|---|---|
| `/manifest.json` | 1x por sessão | Cachear; revalidar com `If-None-Match` (ETag) → `304`. |
| `/stream/…` | a cada título aberto | Cache curto (segundos–minutos). A `url` resolvida tem **token de sessão**; não cachear a `url` final por muito tempo. |
| `/catalog/…` | ao abrir biblioteca | Cache curto; conteúdo **volátil** (ver [catalog §3](./catalog.md#3-paginação-skip)). |
| `/meta/…` | ao abrir detalhe | Cache curto. |

> Resolva a `url` (siga o 302) **perto do play**, não na listagem — evita usar tokens expirados.

---

## 4. Rate limiting

Limite real: **5 requisições / 5 s** (`ratelimit-policy: 5;w=5`). Cada resposta traz `ratelimit-remaining` e `ratelimit-reset` (s).

Estratégia recomendada:

1. **Throttle client-side:** no máx. 5 chamadas por janela de 5 s (token bucket / fila serial).
2. **Respeitar headers:** se `ratelimit-remaining == 0`, aguardar `ratelimit-reset` segundos.
3. **Tratar `429`:** backoff exponencial com jitter; honrar `Retry-After` se presente.
4. **Coalescer:** deduplicar chamadas idênticas em voo (mesma rota+id).

---

## 5. Tratamento de erros

| Situação | Sintoma | Ação |
|---|---|---|
| ID inválido/desconhecido | `/stream` retorna **streams genéricos** (não vazio, não 404) | Os filtros refinados dos perfis eliminam os genéricos na prática — o app **não** valida título/ano client-side. Se voltar a acontecer, calibrar o perfil no AIOStreams. Ver [id-formats §5](./id-formats.md#5-comportamento-com-id-inválidodesconhecido). |
| Sem resultados úteis | só Scrape Summaries, 0 streams reais após filtro | Mostrar "nenhuma fonte"; logar os summaries (status por scraper) para diagnóstico. |
| Rate limit | `429` | Backoff (ver §4). |
| Erro do addon | meta com prefixo `aiostreamserror` | Tratar como diagnóstico, não como conteúdo. Ver [meta §4](./meta.md#4-prefixos-de-id-de-meta). |
| `url` expirada | player recebe 4xx ao seguir o 302 | Re-buscar `/stream` e re-resolver. |
| Host Tailscale offline | timeout/conexão recusada | A API só responde dentro da tailnet; verificar conectividade Tailscale. |

---

## 6. Processamento de `/stream` (contrato do 1º resultado)

Toda a filtragem e ordenação acontece **server-side, nos perfis** — o app não implementa seleção:

```swift
let chosen = streams.first(where: \.isPlayable)   // 1º sem streamData.statistic e com url http(s)
let videoURL = chosen?.playbackURL                // → handoff para o Infuse
```

- `AddonStream.playbackURL`/`isPlayable` (`StreamHub/Streams/StreamModels.swift`): descartam
  Scrape Summaries (`streamData.type == "statistic"`) e URLs não-http(s) (ex.: magnet).
- Nenhum stream playável → erro "Nenhuma fonte encontrada".
- Os sinais de qualidade (`[TB+]`, bandeiras, `bingeGroup`) seguem documentados em
  [stream.md](./stream.md) — servem para **calibrar os perfis**, não para lógica no cliente.

---

## 7. Handoff para o player

A `url` é HTTP(S) direta (302 → CDN → 206, **sem headers**) — ver [stream §6](./stream.md#6-comportamento-da-url). Isso a torna compatível tanto com player nativo quanto com o **Infuse**.

| Caso | Player | Por quê |
|---|---|---|
| `url` HTTP/HTTPS (padrão desta instância) | **Infuse** ou nativo | Infuse aceita URLs HTTP(S) sem headers. |
| HLS (`.m3u8`) | nativo (Infuse: a validar) | Suporte de HLS via deep link do Infuse não confirmado. |
| magnet / `infoHash` puro | nativo | Infuse **não** abre magnet. (Raro aqui: o debrid entrega HTTP.) |
| URL que exija header custom | nativo | O deep link do Infuse não passa headers. (Não aplicável às URLs com token-na-URL desta instância.) |

Sempre manter o **player nativo como fallback**. Detalhes do deep link, detecção de instalação, callbacks e limitações (incl. **tvOS**): **[../../player/infuse/](../../player/infuse/README.md)** — em especial [integration-guide.md](../../player/infuse/integration-guide.md) e [limitations.md](../../player/infuse/limitations.md).

---

## 8. Checklist de implementação

- [ ] URLs base dos 3 perfis vindas do Keychain (`Secrets.plist`); nunca logadas.
- [ ] Perfil correto por contexto: anime → **anime**; modo Dub → **casual**; modo Leg → **cinema**.
- [ ] Throttle ≤ 5 req / 5 s + tratamento de `429` com backoff.
- [ ] Filtro de Scrape Summaries (`streamData.type === "statistic"` / `url` ausente).
- [ ] 1º stream playável tocado direto — sem validação/ordenação client-side.
- [ ] `url` resolvida sob demanda (perto do play); re-resolver se expirar.
- [ ] Player segue redirects (302); fallback nativo configurado.
- [ ] Handoff Infuse só para `url` HTTP/HTTPS; demais casos no nativo.
