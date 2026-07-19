## Status

parcial

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:122-123` — `protocol_whitelist` comentado de propósito ("默认情况下允许所有协议" = por padrão todos os protocolos são permitidos); o KSPlayer não impõe nenhuma barreira de protocolo.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:197-202` — a URL é passada como `url.absoluteString` direto para `avformat_open_input` com `avOptions` sem whitelist; qualquer scheme que o libavformat linkado suporte é aceito.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:446-447` — fallback automático do `firstPlayerType` (KSAVPlayer, que não abre smb://) para o `secondPlayerType` (KSMEPlayer/FFmpeg) em caso de falha, o que faz URLs smb:// chegarem ao pipeline FFmpeg sem intervenção do app.
- `Package.swift:24,46` + `Package.resolved` — dependência obrigatória `kingslay/FFmpegKit` pinada em `6.1.4` (revision `c32be9bf`).
- FFmpegKit 6.1.4 (`Package.swift` do repo kingslay/FFmpegKit, linha 52) — o target `FFmpegKit` linka `libsmbclient` como binaryTarget em todas as plataformas (iOS/tvOS/macOS/visionOS).
- FFmpegKit 6.1.4 (`Plugins/BuildFFmpeg/BuildFFMPEG.swift:31,235-236,297`) — o FFmpeg é compilado com `--enable-protocols` (todos os protocolos) e, com `libsmbclient` no conjunto default de libs, `--enable-libsmbclient --enable-protocol=libsmbclient`.
- `Demo/Pods/Local Podspecs/FFmpegKit.podspec.json:62` e `Demo/Pods/Target Support Files/FFmpegKit-tvOS/FFmpegKit-tvOS-xcframeworks-input-files.xcfilelist` — evidência dentro deste repo: o pod FFmpegKit consumido pelo Demo vendoriza `libsmbclient.xcframework` (inclusive no target tvOS).
- Árvore completa do repo kingslay/FFmpegKit em 6.1.4: zero ocorrências de `nfs`/`libnfs`/`upnp` — o protocolo `nfs` do FFmpeg requer `--enable-libnfs`, que não existe nesse build.
- `rg -in 'smb|nfs|upnp|dlna|cifs|webdav|samba|bonjour|netservice' Sources/ --glob '*.swift'` — nenhum resultado: não há código Swift dedicado (UI de descoberta, credenciais, flags KSOptions) para esses protocolos no fork.
- `README.md:73` — a tabela oficial marca "Custom url protocols such as nfs/smb/UPnP" como ✅ na versão GPL.

## Como funciona

A feature, tal como o KSPlayer GPL a entrega, é "pass-through de protocolo para o FFmpeg":

1. O app passa qualquer URL (`smb://user:pass@host/share/file.mkv`, `http://…`, `rtsp://…`) para `KSPlayerLayer`/`KSMEPlayer`.
2. `MEPlayerItem` entrega a string da URL ao `avformat_open_input` sem `protocol_whitelist`, então a resolução do scheme fica 100% a cargo do libavformat embarcado.
3. O binário FFmpegKit 6.1.4 (dependência pinada deste fork) foi compilado com todos os protocolos habilitados e com libsmbclient linkado estaticamente — portanto **smb:// funciona out of the box**, com autenticação via credenciais embutidas na URL (formato `smb://user:senha@host/share/path`).
4. Para URLs que o AVPlayer nativo rejeita (como smb), o fallback de `KSPlayerLayer` troca automaticamente para o KSMEPlayer.

O que NÃO funciona com a dependência pinada:

- **nfs://** — o build do FFmpegKit 6.1.4 não inclui libnfs, então o protocolo `nfs` do FFmpeg não está compilado; a URL falha na abertura.
- **UPnP/DLNA como protocolo** — o FFmpeg não possui um protocolo "upnp"; reproduzir mídia de um servidor DLNA funciona apenas porque o transporte final é HTTP. Não há descoberta SSDP/Bonjour, browsing de servidores nem UI de rede em lugar nenhum do fork.

## O que falta

- Paridade real com o item "nfs" da tabela: exigiria um build do FFmpegKit com `--enable-libnfs` (mudança no repo FFmpegKit/binário, não neste código Swift) ou uma implementação de protocolo custom via `AVIOContext`.
- Suporte a UPnP de verdade (descoberta SSDP, browsing de content directory, resolução para URL HTTP) — inexistente; seria feature nova no app (StreamHub) ou no fork.
- UI/UX estilo Infuse: navegador de compartilhamentos de rede, keychain de credenciais SMB, teste de conexão — nada disso existe; hoje as credenciais só entram embutidas na URL.
- Nenhuma flag ou API dedicada em `KSOptions` para esses protocolos (ex.: timeouts específicos de SMB); só os dicionários genéricos `formatContextOptions`/`avOptions`.

## Verificação

**Veredito: REFUTADA PARCIALMENTE a conclusão "ausente" do investigador original — status correto: parcial.**

O investigador acertou nos fatos brutos (nenhuma string smb/nfs/upnp em `Sources/*.swift`, nenhuma UI de descoberta, whitelist comentada), mas errou na interpretação ao descartar o binário FFmpegKit como "fora do escopo deste código Swift". Três pontos derrubam o "ausente":

1. **A dependência é parte do produto, não uma variável externa.** O fork pina `kingslay/FFmpegKit` 6.1.4 em `Package.resolved`, e esse pacote linka `libsmbclient` incondicionalmente no target `FFmpegKit` e compila o FFmpeg com `--enable-protocols` + `--enable-protocol=libsmbclient`. Não é "na teoria, se o binário tiver sido buildado com suporte" — o binário pinado **foi** buildado com suporte a SMB, e há evidência disso dentro do próprio repo (`Demo/Pods/Local Podspecs/FFmpegKit.podspec.json:62` vendoriza `libsmbclient.xcframework`, inclusive para tvOS).
2. **O design da feature é exatamente "ausência de restrição + binário capaz".** A tabela oficial promete "custom url protocols", não uma UI de rede. O caminho `KSPlayerLayer` (fallback :446-447) → `MEPlayerItem` (sem whitelist, :197-202) → libavformat com smb compilado entrega smb:// funcionando de ponta a ponta sem nenhuma linha extra no app.
3. **Porém a promessa da tabela é maior do que o entregue**, o que impede "presente" pleno: `nfs` não está compilado no FFmpegKit 6.1.4 (zero libnfs no repo/flags — verificado na árvore da revision pinada) e "UPnP" não existe como protocolo no FFmpeg nem como descoberta no fork. Dos três protocolos citados no README, só SMB funciona de fato.

Conclusão: nem "presente" (nfs e UPnP não funcionam), nem "ausente" (smb funciona out of the box pela dependência pinada e o fork foi desenhado para isso). **parcial**.
