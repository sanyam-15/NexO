#!/data/data/com.termux/files/usr/bin/bash
#
# Nexo AI bridge — instalador de UN comando para Termux.
#
# Hace todo lo aburrido de golpe: instala Node, las CLIs (Claude Code + Codex),
# coloca el bridge, genera un token, deja autostart en el arranque del teléfono
# y los scripts para correrlo. Solo te queda loguearte una vez.
#
# Uso:
#   sh install.sh                       # instala usando el .js que está al lado
#   BRIDGE_URL=https://.../nexo-ai-bridge.js sh install.sh   # baja el .js de una URL
#
set -e

INSTALL_DIR="$HOME/.nexo-bridge"
BRIDGE_JS="$INSTALL_DIR/nexo-ai-bridge.js"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "$HOME")"
BRIDGE_URL="${BRIDGE_URL:-}"

say() { printf '\n\033[1;36m==>\033[0m %s\n' "$1"; }
err() { printf '\n\033[1;31mx\033[0m %s\n' "$1" >&2; }

# 1. ¿Estamos en Termux?
if [ -z "$PREFIX" ] || ! command -v pkg >/dev/null 2>&1; then
  err "Esto debe correr DENTRO de Termux. Instálalo desde F-Droid o GitHub (no Play Store)."
  exit 1
fi

# 2. Node + helpers
say "Instalando Node y utilidades…"
pkg update -y >/dev/null 2>&1 || true
pkg install -y nodejs >/dev/null
pkg install -y termux-api >/dev/null 2>&1 || true   # da termux-wake-lock
command -v curl >/dev/null 2>&1 || pkg install -y curl >/dev/null 2>&1 || true

# 3. Las CLIs (cada usuario usa SU propia suscripción)
say "Instalando Claude Code y Codex (esto tarda un poco)…"
npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code @openai/codex

# 4. Colocar el bridge
mkdir -p "$INSTALL_DIR"
say "Colocando el bridge en $INSTALL_DIR…"
if [ -f "$SELF_DIR/nexo-ai-bridge.js" ]; then
  cp "$SELF_DIR/nexo-ai-bridge.js" "$BRIDGE_JS"
elif [ -n "$BRIDGE_URL" ]; then
  curl -fsSL "$BRIDGE_URL" -o "$BRIDGE_JS"
else
  err "No encontré nexo-ai-bridge.js junto al instalador ni una BRIDGE_URL."
  err "Copia nexo-ai-bridge.js a $INSTALL_DIR y reintenta."
  exit 1
fi

# 5. Token aleatorio + config (idempotente)
ENV_FILE="$INSTALL_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  TOKEN="$(node -e 'console.log(require("crypto").randomBytes(24).toString("hex"))')"
  printf 'BRIDGE_TOKEN=%s\nPORT=8787\nHOST=127.0.0.1\n' "$TOKEN" > "$ENV_FILE"
fi
# carga PORT/BRIDGE_TOKEN para el mensaje final
PORT="$(. "$ENV_FILE"; echo "${PORT:-8787}")"
BRIDGE_TOKEN="$(. "$ENV_FILE"; echo "$BRIDGE_TOKEN")"

# 6. Script para correrlo a mano
RUN_SCRIPT="$INSTALL_DIR/run.sh"
cat > "$RUN_SCRIPT" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
set -a; . "$ENV_FILE"; set +a
exec node "$BRIDGE_JS"
EOF
chmod +x "$RUN_SCRIPT"

# 7. Autostart al encender el teléfono (necesita el addon Termux:Boot)
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
BOOT_SCRIPT="$BOOT_DIR/start-nexo-bridge.sh"
cat > "$BOOT_SCRIPT" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
set -a; . "$ENV_FILE"; set +a
exec node "$BRIDGE_JS" >> "$INSTALL_DIR/bridge.log" 2>&1
EOF
chmod +x "$BOOT_SCRIPT"

# 8. Final
say "Instalado. Falta UNA cosa: loguearte (solo el/los que uses)."
echo "    claude          # suscripción Claude (Max)"
echo "    codex login     # suscripción ChatGPT (Plus/Pro)"
echo
say "Arranca el bridge ahora:"
echo "    sh $RUN_SCRIPT"
echo
say "En Nexo → proveedor 'Claude Code / Codex (bridge local)':"
echo "    URL base : http://127.0.0.1:${PORT}/v1"
echo "    API key  : ${BRIDGE_TOKEN}"
echo
echo "Con el addon Termux:Boot instalado, el bridge se levanta solo al encender el teléfono."
