# Nexo AI bridge — Claude Code & Codex vía suscripción, desde el celular

Servidor local (Node, sin dependencias) que expone el subconjunto
**OpenAI-compatible que usa Nexo** y por dentro llama a las CLIs `claude`
(Claude Code) y `codex` (OpenAI Codex) en modo headless. Así Nexo usa **tus
suscripciones** (Claude Max / ChatGPT Plus·Pro) como si fueran un proveedor más
— sin API keys de pago por token.

> **Uso personal.** Autentica con tu propio login y consume el límite de tu
> suscripción. No compartas credenciales ni expongas el bridge fuera de
> `localhost`. Nexo puede ofrecer esto como opción avanzada BYO-subscription:
> cada usuario corre su propio bridge y usa su propia cuenta.

> ⚠️ **En Android/Termux usa `install-proot.sh`, NO `install.sh`.** Las CLIs
> modernas de Claude/Codex son binarios nativos sin build para Android (y el
> musl estático es no-PIE, que Android rechaza). No corren en Termux pelado.
> `install-proot.sh` instala un Linux glibc (proot-distro Ubuntu) donde sí
> corren; el bridge vive dentro del proot y, como proot comparte la red, Nexo
> lo alcanza igual en `127.0.0.1:8787`. `install.sh` queda solo para escritorio
> (Mac/Linux/servidor con Tailscale), donde las CLIs instalan normal.
>
> **Notas verificadas en dispositivo:** Codex con cuenta ChatGPT solo acepta su
> modelo default (`gpt-5.5`) — el bridge omite `-m`. Claude se autentica con
> `claude setup-token` → exporta `CLAUDE_CODE_OAUTH_TOKEN` en el `.env`. El
> sandbox de Codex (bubblewrap) no corre en proot, por eso se usa
> `--dangerously-bypass-approvals-and-sandbox` (ya estás dentro del sandbox de
> proot).

---

## Instalación rápida (un comando)

Tras instalar **Termux** (paso 1), copia esta carpeta a Termux y corre:

```bash
sh install.sh
```

Hace todo: Node, las dos CLIs, el bridge, un token aleatorio, scripts de arranque
y autostart en el encendido. Solo te queda **loguearte una vez** (`claude` y/o
`codex login`) y arrancar con `sh ~/.nexo-bridge/run.sh`. Para autostart real,
instala el addon **Termux:Boot**. Nexo solo prueba la conexión; por seguridad no
pide permiso para ejecutar comandos dentro de Termux.

---

## 1. Instalar Termux

Instala **Termux** desde F-Droid o GitHub (no la versión vieja de Play Store):
https://github.com/termux/termux-app/releases

Luego, dentro de Termux:

```bash
pkg update && pkg upgrade -y
pkg install -y nodejs git
termux-setup-storage     # para guardar/leer archivos si hace falta
```

## 2. Instalar las CLIs y loguearte (una vez)

```bash
# Claude Code (npm)
npm install -g @anthropic-ai/claude-code
claude            # primera vez: inicia sesión con tu cuenta Claude (Max)

# Codex CLI (npm)
npm install -g @openai/codex
codex login       # inicia sesión con tu ChatGPT (Plus/Pro)
```

Verifica que respondan en headless:

```bash
claude -p "di hola en una palabra" --output-format json
codex exec --skip-git-repo-check "di hola en una palabra"
```

## 3. Copiar y arrancar el bridge

Copia `nexo-ai-bridge.js` a Termux (por ejemplo a `~/`), y:

```bash
# (opcional, recomendado) un token para que solo Nexo pueda usar el bridge
export BRIDGE_TOKEN="pon-aqui-un-secreto-largo"

# evita que Android mate el proceso
termux-wake-lock

node ~/nexo-ai-bridge.js
```

Deberías ver: `Nexo AI bridge escuchando en http://127.0.0.1:8787`.

Pruébalo en otra sesión de Termux. Si usaste el instalador, lee el token desde
la config:

```bash
TOKEN="$(. ~/.nexo-bridge/.env; echo "$BRIDGE_TOKEN")"
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8787/health
```

### Mantenerlo vivo en segundo plano

- **tmux** (simple):
  ```bash
  pkg install -y tmux
  tmux new -s bridge
  termux-wake-lock && node ~/nexo-ai-bridge.js
  # detach: Ctrl-b luego d  |  volver: tmux attach -t bridge
  ```
- **Arranque automático**: instala **Termux:Boot** y deja un script en
  `~/.termux/boot/` que haga `termux-wake-lock` y lance el bridge.
- En *Ajustes de Android → Batería*, marca Termux como **sin restricciones**.

## 4. Conectar Nexo

En Nexo → ajustes de IA, elige el proveedor **“Claude Code / Codex (bridge local)”**:

- **URL base**: `http://127.0.0.1:8787/v1` (ya viene por defecto).
- **API key**: vacío, o el mismo `BRIDGE_TOKEN` si lo configuraste.
- **Modelo**: el id decide el backend:
  - `claude-opus-4-8`, `claude-sonnet-4-6` → **Claude Code**
  - `gpt-5-codex`, `gpt-5`, `o4-mini` → **Codex**

Activa la IA y listo. Los módulos (Diagnóstico, Planes, Sugerencias, Captura…)
usan el bridge automáticamente.

> Si el emulador/otro dispositivo no alcanza `127.0.0.1`, prueba la IP del
> teléfono en la misma red, y arranca el bridge con `HOST=0.0.0.0` (solo en redes
> de confianza, e idealmente con `BRIDGE_TOKEN`).

---

## Configuración (variables de entorno)

| Variable             | Default                    | Para qué |
|----------------------|----------------------------|----------|
| `PORT`               | `8787`                     | Puerto del bridge |
| `HOST`               | `127.0.0.1`                | Interfaz. `0.0.0.0` para LAN (con token) |
| `BRIDGE_TOKEN`       | *(vacío)*                  | Si lo pones, Nexo debe mandarlo como API key |
| `CLAUDE_BIN`         | `claude`                   | Ruta/al binario de Claude Code |
| `CODEX_BIN`          | `codex`                    | Ruta/al binario de Codex |
| `DEFAULT_BACKEND`    | `codex`                    | Backend si el modelo no es claramente claude/codex |
| `REQUEST_TIMEOUT_MS` | `170000`                   | Tope por petición (Nexo espera hasta 180s) |
| `MAX_BODY_BYTES`     | `20971520`                 | Límite del cuerpo HTTP (incluye imágenes base64) |
| `MAX_CONCURRENT`     | `1`                        | Peticiones simultáneas permitidas |
| `SCRATCH_DIR`        | `$TMPDIR/nexo-ai-bridge`   | Carpeta aislada de trabajo |

## Cómo encaja con Nexo (sin tocar `LlmClient`)

- Nexo manda `{ model, messages, tools?, tool_choice? }` a `/v1/chat/completions`.
- **`complete()`** (texto): el bridge devuelve el texto del modelo en
  `choices[0].message.content`.
- **`extractStructured()`** (JSON con schema): el bridge inyecta el JSON Schema en
  el prompt, fuerza salida JSON, y devuelve el objeto **tanto** en
  `message.content` **como** en `message.tool_calls[0].function.arguments`, que
  son justo los dos caminos que `OpenAiCompatibleClient` ya parsea.
- Por eso se conecta como un proveedor **local OpenAI-compatible para Nexo** más
  (como Ollama/LM Studio): timeout largo, sin key obligatoria.

## Límites y notas

- **Rate limits**: el headless consume el mismo cupo de tu suscripción que el uso
  interactivo. Para uso intenso, Anthropic recomienda pasar a API key.
- **Visión (recibos)**: el backend **Codex** acepta imágenes (`-i`); el backend
  **Claude Code** headless no, así que para fotos elige un modelo `gpt-*`.
- **Latencia**: cada petición arranca un proceso (~1–3 s de overhead). Es normal.
- **Seguridad**: mantenlo en `127.0.0.1` y usa `BRIDGE_TOKEN`. Otras apps del
  teléfono también ven `localhost`.
- **Aislamiento**: el bridge corre las CLIs con entorno reducido. Claude se lanza
  en safe mode y sin herramientas; Codex se lanza efímero, sin reglas/config de
  usuario y con sandbox read-only. Aun así, son CLIs agentic: no expongas este
  servidor a redes no confiables.
