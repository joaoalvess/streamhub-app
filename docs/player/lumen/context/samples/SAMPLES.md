# Biblioteca curada de amostras de teste

Catálogo de referência para a task [[sample-library]] do `ROADMAP.md` (seção 🎯 Agora — "Preparação transversal"). Objetivo: dar a cada task do roadmap ([[spike-ffmpegkit-614]], [[proavplayer]], [[ffmpeg-8x]], [[dv-fase0]], [[dv-nativo]], [[hdr10plus]], [[fontes-embutidas]], [[libass]], [[migracao-streamhub]]) uma amostra específica pronta para apontar no critério de aceite, em vez de caçar arquivo no meio da implementação.

Este documento só cataloga — nenhuma mídia foi baixada. Toda amostra listada precisa ser **confirmada com os comandos da seção abaixo** antes de ser usada como evidência de aceite: nomes de release/descrições de terceiros erram; o mediainfo/ffprobe do arquivo real é a fonte da verdade.

Legitimidade das fontes: priorizei (a) hospedagem oficial do fabricante (Dolby, Netflix, FF Pictures), (b) projetos open source com afirmação explícita de licença (Jellyfin/CC BY-SA, Netflix Open Content/CC BY 4.0), (c) o wiki oficial do Kodi (`kodi.wiki/view/Samples`, mantido pela comunidade sob "fair use... para teste, avaliação técnica e documentação", link de cada arquivo hospedado por terceiros — Google Drive/mega.nz/demolandia — não pelo próprio Kodi). Onde só existe torrent/comunidade de raws (ex. Beatrice-Raws), sinalizei explicitamente. Nenhuma amostra aqui envolve DRM quebrado ou rip próprio — são todos arquivos já circulando publicamente com o propósito declarado de teste.

## Como verificar cada spec (mediainfo/ffprobe)

Rodar contra o arquivo real antes de usá-lo como evidência de qualquer critério de aceite do roadmap.

```bash
# 1) Visão geral (contêiner, codecs, HDR format resumido)
mediainfo "arquivo.mkv"

# 2) Dolby Vision — profile/level/RPU via side data do stream de vídeo
ffprobe -v error -select_streams v:0 -show_entries stream_side_data -of json "arquivo.mkv"
# Procurar side_data_type "DOVI configuration record" com os campos:
#   dv_version_major / dv_version_minor
#   dv_profile                       (5, 7, 8...)
#   dv_level
#   rpu_present_flag / el_present_flag / bl_present_flag
#   dv_bl_signal_compatibility_id    (0 = P5/IPT-PQc2 puro; 1 = BL compatível c/ HDR10; 2 = BL compatível c/ SDR/BT.709; 4 = BL compatível c/ HLG)
# mediainfo resume isso em "HDR Format": ex. "Dolby Vision, Version 1.0, dvhe.05.06" ou
# "Dolby Vision, Version 1.0, dvhe.07.06, BL+EL+RPU, Blu-ray compatible"

# 3) Distinguir MEL vs FEL em perfil 7 — NÃO dá pra ler direto no ffprobe/mediainfo
#    (ambos mostram "BL+EL+RPU"/"Blu-ray compatible"; a diferença é se a RPU usa NLQ)
dovi_tool info -i "arquivo.hevc" -f 0        # quietvoid/dovi_tool, https://github.com/quietvoid/dovi_tool
# fallback sem dovi_tool: comparar o bitrate isolado da trilha EL —
# MEL tipicamente poucos kbps (só metadata), FEL sobe a centenas de kbps/poucos Mbps
# (heurística usada pela própria comunidade dovi_tool/AVSForum, não é regra formal da spec Dolby)

# 4) HDR10+ — metadata dinâmica é POR FRAME, não por stream (precisa -show_frames)
ffprobe -v error -select_streams v:0 -read_intervals "%+#5" -show_entries frame=side_data_list -of json "arquivo.mkv"
# Procurar side_data_type "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)" nos primeiros frames

# 5) E-AC-3 JOC (Atmos) — flag do átomo dec3 (complexity_index_type_a)
mediainfo --Full "arquivo.mkv" | grep -i -E "JOC|Atmos|Complexity"
# mediainfo expõe direto "Dolby Atmos" / "Complexity index type A" quando o JOC está presente e != 0;
# ffprobe sozinho não decodifica esse campo do dec3, só confirma o codec-base:
ffprobe -v error -select_streams a -show_entries stream=index,codec_name,channels,channel_layout -of json "arquivo.mkv"

# 6) TrueHD 7.1 Atmos
mediainfo "arquivo.mkv" | grep -B2 -A20 "Audio #"
# "Format profile" deve indicar objetos Atmos (mediainfo recentes: "Dolby Atmos" na mesma seção);
# canais = 8 (7.1); confirmar com ffprobe:
ffprobe -v error -select_streams a -show_entries stream=codec_name,channels,channel_layout -of json "arquivo.mkv"

# 7) DTS-HD MA
ffprobe -v error -select_streams a -show_entries stream=codec_name,profile,channels,channel_layout -of json "arquivo.mkv"
# profile deve retornar "DTS-HD MA" (não confundir com "DTS-HD HRA", lossy)

# 8) Legenda ASS + fontes embutidas
ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=filename,mimetype -of json "arquivo.mkv"
# Trilha de legenda: codec_type=subtitle, codec_name=ass
# Anexos de fonte: codec_type=attachment, mimetype application/x-truetype-font|application/vnd.ms-opentype
#   (ou, na ausência de mimetype útil, extensão .ttf/.otf/.ttc no filename — mesma heurística do VLC)
# Para ver se o script ASS usa karaokê/typesetting pesado, extrair a trilha e grep os tags:
ffmpeg -i "arquivo.mkv" -map 0:s:0 -c copy legenda.ass
grep -o -E '\\\\(k|kf|ko|t|move|clip|iclip|p[0-9]|fr[xyz])\(' legenda.ass | sort | uniq -c
```

---

## 1. DV P5 (`dvhe.05.06`)

**O que valida:** [[dv-fase0]] (aceite principal — cor correta em P5, sem tint verde/roxo dos issues upstream #771/#348, `dv_bl_signal_compatibility_id == 0`); fatia P5 de [[dv-nativo]] (passthrough via `master.m3u8`).

**Spec exata:** HEVC 10-bit; side data DOVI com `dv_profile=5`, `dv_bl_signal_compatibility_id=0` (base layer IPT-PQc2, não compatível com HDR10 puro), `rpu_present_flag=1`, `bl_present_flag=1`, `el_present_flag=0` (single layer); codec tag de saída esperado `dvhe.05.06`/`dvh1.05.06`.

| Fonte pública | Notas |
|---|---|
| [Jellyfin Test Videos — 4K DV P5](https://repo.jellyfin.org/test-videos/HDR/Dolby%20Vision/Test%20Jellyfin%204K%20DV%20P5.mp4) (também 1080p/8K) | CC BY-SA 4.0, mantido por Gnattu, hospedagem oficial do projeto Jellyfin. Vídeo-only (confirmar áudio com mediainfo antes de assumir mudo). |
| [Kodi Wiki #24 — "Dolby Vision Mystery Box (Profile 5)"](https://mega.nz/file/2TYwVSTZ#LBh2CoX3QUfkR_kwey_aim9QWvwk3UpLQozEG9n2ww0) (MP4) | Linkado pelo wiki oficial do Kodi (`kodi.wiki/view/Samples`), hospedado em mega.nz por terceiro da comunidade. |

O próprio issue upstream que motivou [[dv-fase0]] (kingslay/KSPlayer#348, "green and pink tint") cita `dvhe.05.06` nominalmente — qualquer uma das duas amostras acima serve para reproduzir o bug antes do fix e confirmar a correção depois.

---

## 2. DV P8.1 + E-AC-3 JOC (WEB-DL)

**O que valida:** pergunta (c) do [[spike-ffmpegkit-614]] ("um remux E-AC-3 JOC preserva o `complexity_index_type_a` no átomo `dec3` de saída"); aceite Atmos/dec3 do [[ffmpeg-8x]]; aceite principal do [[proavplayer]] (Apple TV entra em modo Dolby Vision real + logo Atmos acende); fatia P8.1 de [[dv-nativo]].

**Spec exata:** vídeo HEVC, side data DOVI `dv_profile=8`, `dv_bl_signal_compatibility_id=1` (BL compatível com HDR10), codec tag `dvhe.08.06`/`dvh1.08.06`; áudio `codec_name=eac3` com JOC — no remux de saída, `complexity_index_type_a != 0` no átomo `dec3`/`EC3SpecificBox`.

| Fonte pública | Notas |
|---|---|
| [Jellyfin Test Videos — 4K DV P8.1](https://repo.jellyfin.org/test-videos/HDR/Dolby%20Vision/Test%20Jellyfin%204K%20DV%20P8.1.mp4) | CC BY-SA 4.0. Cobre só a metade vídeo (perfil DV) — provavelmente sem Atmos, confirmar com mediainfo. |
| [Kodi Wiki — "Enhanced AC3 with Joint Object Coding (EAC3-JOC) ATMOS Sample"](https://drive.google.com/file/d/1_Gc0v7glw5hGJ6l37En5YKDPnPSLR6HM/view?usp=sharing) (MKV @ 4K/23.976, base HDR10 — não DV) | Cobre a metade áudio: é a amostra mais direta para testar especificamente a pergunta (c) do spike (preservação do `dec3`/JOC no remux), independente do vídeo ser DV ou HDR10. |
| [dropcreations/Manzana-Apple-TV-Plus-Trailers](https://github.com/dropcreations/Manzana-Apple-TV-Plus-Trailers) (ferramenta) | Baixa trailers reais de `trailers.apple.com` (CDN oficial da Apple, conteúdo publicamente servido para promoção) com vídeo Dolby Vision/HDR10+ e áudio Dolby Atmos (E-AC-3 JOC) — é o candidato mais próximo de um combo real DV P8.1 + EAC3-JOC em HLS, já que é literalmente o mesmo tipo de entrega (HLS/HTTP) que o [[proavplayer]] consome. Não testado neste levantamento; verificar o trailer específico escolhido com os comandos da seção acima antes de usar como evidência. |

**Placeholder:** `<preencher: URL/caminho do debrid>` — nenhuma das fontes acima é um WEB-DL real de longa-metragem com DV P8.1 + E-AC-3 JOC no mesmo arquivo (o padrão típico de release Amazon/Apple TV+ que compõe o catálogo real do StreamHub); os trailers da Apple são o substituto público mais próximo para validar o pipeline, mas o critério de aceite final do [[proavplayer]] deveria rodar contra um título real do acervo.

---

## 3. DV P7 MEL (remux Blu-ray)

**O que valida:** conversão P7→P8.1 (mode 2) do [[dv-nativo]]; fallback para `KSMEPlayer` do [[proavplayer]] ("DV P7 — não suportado pelo AVPlayer... cai para o KSMEPlayer atual").

**Spec exata:** `dv_profile=7`, `bl_present_flag=1`, `el_present_flag=1`; RPU **sem** NLQ (indício de MEL — ver comando `dovi_tool info` na seção acima; heurística alternativa: bitrate da trilha EL na casa de poucos kbps).

| Fonte pública | Notas |
|---|---|
| — | Nenhuma amostra pública encontrada explicitamente rotulada como MEL (a maior parte do material de teste disponível — Kodi Wiki, Jellyfin — cobre P5/P8.1/P8.4 ou P7 sem diferenciar MEL/FEL). MEL é também minoritário no mercado real: a maioria dos UHD Blu-ray com P7 de estúdios usa FEL (ver item 4). |

**Placeholder:** `<preencher: URL/caminho do debrid>` — depende do acervo pessoal; ao escolher um título, confirmar MEL (não FEL) com `dovi_tool info` antes de fixar como amostra de referência.

---

## 4. DV P7 FEL (remux Blu-ray)

**O que valida:** mesmo conjunto do item 3 (conversão P7→P8.1 do [[dv-nativo]], fallback do [[proavplayer]]); é o caso mais comum de P7 real, então é o que efetivamente testa a rota `dovi_tool`/`libdovi` mode 2 na prática.

**Spec exata:** `dv_profile=7`, `el_present_flag=1`; RPU **com** NLQ presente (indício de FEL); EL com bitrate substancial (centenas de kbps a poucos Mbps, ao contrário do MEL).

| Fonte pública | Notas |
|---|---|
| [Kodi Wiki #21 — "Dolby Vision FEL Test Samples"](https://mega.nz/folder/aagzVbbT#WuxcI61oaTv8X3VA_T9_cg) (mega.nz folder) | Desenhado especificamente para verificar decode de FEL: com o teste "DV FEL All Layers Test" deve aparecer uma pessoa por volta de 80s; com "DV FEL Power Rangers Credits Test" a fonte dos créditos deve ficar branco sólido, não cinza desbotado (comparação visual direta se a EL está sendo aplicada). |
| [Kodi Wiki #22 — "DV FEL vs. BL comparisons"](https://drive.google.com/drive/u/0/folders/1FS42T95TOSpoy4xtwUBIQmziCe_R_IKe) | Mostra o que se perde sem a EL (brilho, cor, grão) — útil para validar visualmente a perda esperada da conversão mode 2 (P7→P8.1 descarta a EL). |
| **Netflix "Sol Levante"** — master oficial em [opencontent.netflix.com](https://opencontent.netflix.com/) (Dolby Vision IMF + XML/VDM, **CC BY 4.0**) + encode MKV de comunidade em [Beatrice-Raws](https://beatrice-raws.org/release/sol-levante-2160p) | Curta-metragem 4K produzida pela própria Netflix/Production I.G especificamente como demo de Dolby Vision + Atmos em anime — conteúdo aberto e livre de uso, não fan-encode de material comercial fechado. O encode MKV do Beatrice-Raws relatado tem HDR Format `Dolby Vision, Version 1.0, dvhe.07.06, BL+EL+RPU, Blu-ray compatible` + áudio `Dolby TrueHD 7.1 (Atmos)` — cobre ao mesmo tempo este item **e** o item 6 (TrueHD 7.1 Atmos) no mesmo arquivo. MEL vs FEL não confirmado pela página do release; conferir com `dovi_tool info` antes de catalogar como FEL definitivo. O master oficial da Netflix é a fonte primária legítima; o MKV do Beatrice-Raws é uma distribuição de terceiro (torrent) do mesmo conteúdo aberto, não uma amostra comercial pirateada. |

**Placeholder:** `<preencher: URL/caminho do debrid>` — usar se for necessário testar contra um remux Blu-ray real de estúdio (long-form, bitrate/GOP típico de disco físico) em vez do teste sintético ou do Sol Levante.

---

## 5. HDR10+

**O que valida:** aceite do [[hdr10plus]] (estratégia A — amostra tocando via [[proavplayer]] ativa o modo HDR10+ na TV).

**Spec exata:** side data por frame `side_data_type = "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)"` (ver comando 4 da seção de verificação — não é visível com `-show_streams`, só com `-show_frames`).

| Fonte pública | Notas |
|---|---|
| [Kodi Wiki — "HDR10+ Int'l Space Station Sample 24fps"](https://drive.google.com/u/0/uc?id=1Nz2MPf2FPz3A99ciBSAl3m0U0XBbV1bv&export=download) (TS) | — |
| [Kodi Wiki — "HDR10+ Profile A HEVC 10-bit 23.976 Sample"](https://mega.nz/file/af4zSAbQ#gBiHRiX3oLnBvxMNnytC08v8DRkKzQIkhGpg96nAWXE) (MKV, áudio DTS:X) | "Profile A"/"Profile B" aqui referem-se aos perfis da própria spec HDR10+ (ST 2094-40), não a codec profile de vídeo. |
| [Kodi Wiki — "HDR10+ Profile B HEVC 10-bit 23.976 Sample"](https://mega.nz/file/nehDka6Z#C5_OPbSZkONdOp1jRmc09C9-viDc3zMj8ZHruHcWKyA) (MKV, áudio **E-AC-3 JOC Atmos**) | Bom candidato 2-em-1: HDR10+ dinâmico + Atmos no mesmo arquivo. |
| [FF Pictures — "1 minute HDR10+ system test"](https://ff.de/hdr10plus-metadata-test/) (MP4, 60fps) | Hospedagem direta do fabricante do clipe (FF Pictures GmbH), não repassador terceiro. |

---

## 6. TrueHD 7.1 Atmos

**O que valida:** aceite do [[proavplayer]] ("amostra TrueHD 7.1 Atmos transcodificada para FLAC toca lossless multicanal via AVPlayer, sem erro de channel layout"); pergunta (b) do [[spike-ffmpegkit-614]] (encoder `flac` habilitado no binário — é o encoder de destino do transcode).

**Spec exata:** `codec_name=truehd`, `channels=8`, `channel_layout=7.1` (ou `7.1(wide)`); mediainfo deve indicar presença de objetos Atmos na seção de áudio (não confundir com TrueHD 7.1 "puro", sem metadata de objeto).

| Fonte pública | Notas |
|---|---|
| [Kodi Wiki — "Dolby TrueHD 7.1 Channel Check"](https://mega.nz/file/GTpF2BYY#oPAC-1XJUp0iLSe0VRnfE4YLOWyucKB6iLJ1rR8UEsE) (MKV @ 1080p/29.97) | Confirmar com mediainfo se carrega metadata Atmos ou é só TrueHD 7.1 "channel-based" (channel check tende a ser só canais, sem objetos — checar antes de assumir Atmos). |
| [Kodi Wiki — "Dolby ATMOS 'Amaze' Demo"](https://mega.nz/file/7XAAkRwK#MdlZNP9diVAyJh1Hnrp7zTQk4AHSRs6ujuHoxGUG85A) (M2TS @ 1080p/24) | Trailer de demonstração oficial da Dolby ("Amaze"), amplamente conhecido por carregar TrueHD+Atmos real. |
| [Kodi Wiki — "Hybrid HDR10/Dolby Vision Sample"](https://mega.nz/file/2ew0DApT#UOEt2mrKYOHDak2TlgZSk6nQmJPckHntZvWHdfjVARY) (MKV, áudio TrueHD ATMOS) | Cobre vídeo dual HDR10/DV + áudio TrueHD Atmos no mesmo arquivo — útil pra teste de pipeline completo. |
| **Sol Levante / Beatrice-Raws** (ver item 4) | Mesmo arquivo citado para DV P7 FEL: `Dolby TrueHD – 7.1 (Atmos) + Dolby Digital AC-3 embedded – 5.1`. |

---

## 7. DTS-HD MA

**O que valida:** metade "DTS" do transcode de áudio do [[proavplayer]] (mesmo mecanismo do TrueHD — DTS-HD MA também não é decodificável pelo `AVPlayer` e precisa ser transcodificado para FLAC).

**Spec exata:** `codec_name=dts`, `profile="DTS-HD MA"` (não confundir com `DTS-HD HRA`, que é lossy), `channels` 6 (5.1) ou 8 (7.1).

| Fonte pública | Notas |
|---|---|
| [Kodi Wiki — "DTS-HD MA 5.1 Channel Check"](https://www.demolandia.net/downloads.html?id=30191483) (MKV @ 1080p/23.976) | Demolandia é arquivo comunitário de discos de demo originais, não hospedagem oficial DTS. |
| [Kodi Wiki — "DTS-HD MA 5.1 THX Deep Note Genesis"](https://drive.google.com/file/d/1HyQE5eqvV8BewCdbR9Xq3jbh1eUX0zXN/view?usp=sharing) (MKV @ 2160p/24) | 4K + DTS-HD MA no mesmo arquivo. |
| [Kodi Wiki — "DTS-HD MA 5.1 Baraka HDR Sample"](https://drive.google.com/file/d/1_y0iB7MQmGX3K5XOjB_iT9gl3FVICvii/view?usp=sharing) (MKV @ 2160p/24) | 4K + HDR + DTS-HD MA — cobre 3 specs num arquivo só. |
| [Kodi Wiki — "DTS-HD MA 7.1 'Dredd' Audio Channel Check"](https://mega.nz/file/KaogwLiY#gs1Gpd3s65zPjLciE_hCoGb_zpIWlcVeslnNXnWgpMY) (M2TS @ 1080p/23.976) | Especificamente 7.1 (a maioria dos exemplos públicos de DTS-HD MA é 5.1). |

---

## 8. MKV de anime com legenda ASS + fontes de fansub embutidas (karaokê/typesetting pesado)

**O que valida:** aceite principal de [[fontes-embutidas]] (extração de anexo, registro CoreText, resolução family/PostScript name, fix do overwrite em `KSSubtitle.swift:346-351`); fidelidade de [[libass]] contra mpv (`\move`/`\fad`/`\t`/karaokê/`\clip`); parte do aceite "MKV de anime com legenda ASS embutida" do [[proavplayer]].

**Spec exata:** trilha de legenda `codec_name=ass`; ao menos uma trilha `codec_type=attachment` com `mimetype` `application/x-truetype-font`/`application/vnd.ms-opentype` (ou extensão `.ttf`/`.otf`/`.ttc` no filename, quando o mimetype vier genérico); cabeçalho/eventos ASS usando `\k`/`\kf`/`\ko` (karaokê) e `\t`/`\move`/`\clip`/`\p` (typesetting/vetorial) nas falas de abertura/encerramento — típico de fansub, raro em legenda comercial simples.

| Fonte pública | Notas |
|---|---|
| [Kodi Wiki — "Main10 Anime Samples w/Heavy Subtitles"](https://mega.nz/folder/LPJwRDZQ#vQxEzSpeB7_NGO_fqh0q0w) (mega.nz folder) | O nome já sinaliza o perfil procurado ("Heavy Subtitles"); não verificado neste levantamento se as legendas são ASS com fonte embutida ou só SRT pesado — checar com o comando 8 da seção de verificação antes de usar. |
| [Kodi Wiki — "Hi10p & Main10 720p & 1080p Anime Samples"](https://www.dropbox.com/sh/6iy4gxgsfn14opq/AAAK_L1M_NwZwBPb5IkEPh7Ga?dl=0) (Dropbox) | Foco em perfil de vídeo (Hi10P/Main10), não necessariamente em legenda pesada — usar como fallback. |
| [koi-sama.net — "AVC High 10 Profile Anime Samples"](https://www.koi-sama.net/files/hi10/) | Mesmo perfil do item acima. |

**Placeholder:** `<preencher: URL/caminho do debrid>` — nenhuma das fontes acima é confirmadamente uma release de fansub real com KFX pesado (o caso de uso genuíno do StreamHub: openings/endings com karaokê animado + typesetting de sinais). Esse tipo de arquivo é tipicamente anime licenciado + fansub não-oficial, sem uma fonte "limpa" de direitos disponível publicamente — a melhor prática aqui é usar um episódio real do acervo de debrid do dono, de um grupo de fansub conhecido por typesetting pesado, e confirmar com o comando 8 da seção de verificação (contagem de tags `\k`/`\t`/`\move`/`\clip`) antes de fixá-lo como amostra de referência.

---

## Resumo — cobertura por task do roadmap

| Task | Amostra(s) primária(s) | Status |
|---|---|---|
| [[spike-ffmpegkit-614]] | #2 (EAC3-JOC Kodi Wiki), #6 (encoder FLAC — qualquer amostra TrueHD/DTS-HD MA serve para testar o encode de saída) | Fonte pública disponível |
| [[proavplayer]] | #1, #2, #6, #7, #8 | Parcial — combo real DV+Atmos WEB-DL e fansub real ficam em placeholder |
| [[ffmpeg-8x]] | #1 (P5/HDR10 real), #2 (dec3 JOC) | Fonte pública disponível |
| [[dv-fase0]] | #1 | Fonte pública disponível |
| [[dv-nativo]] | #1, #2, #3, #4 | Parcial — MEL público não encontrado, FEL com boa cobertura (Sol Levante + Kodi FEL tests) |
| [[hdr10plus]] | #5 | Fonte pública disponível |
| [[fontes-embutidas]] / [[libass]] | #8 | Placeholder — depende do acervo pessoal |

Ao fechar cada task, revalidar a amostra escolhida contra este documento (regra 7 do `ROADMAP.md`: referências envelhecem) e atualizar os placeholders `<preencher: URL/caminho do debrid>` com o caminho real usado.
