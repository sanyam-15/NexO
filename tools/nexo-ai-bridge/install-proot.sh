#!/data/data/com.termux/files/usr/bin/sh
#
# Nexo AI bridge — provisión vía proot-distro (Ubuntu glibc) en Termux. v2:
# usa un bind-mount de staging para no adivinar la ruta del rootfs.
#
LOG="/sdcard/Android/data/com.termux/files/proot-install.log"
: > "$LOG"
exec >> "$LOG" 2>&1
echo "=== START provisión proot v2 ==="

fail() { echo "MARKER_FAIL: $1"; exit 1; }

# 0. Herramientas Termux
echo "--- pkg install proot-distro ---"
pkg install -y proot-distro termux-api curl >/dev/null 2>&1 || fail "pkg proot-distro"

# 1. Instalar Ubuntu (idempotente, sin adivinar rutas)
if proot-distro login ubuntu -- true 2>/dev/null; then
  echo "--- ubuntu ya instalado (salto descarga) ---"
else
  echo "--- proot-distro install ubuntu (descarga rootfs) ---"
  proot-distro install ubuntu || fail "install ubuntu"
fi

# 2. Token: reusar el existente para no reconfigurar Nexo
TOKEN=""
if [ -f "$HOME/.nexo-bridge/.env" ]; then
  TOKEN=$(. "$HOME/.nexo-bridge/.env" 2>/dev/null; printf '%s' "$BRIDGE_TOKEN")
fi
[ -z "$TOKEN" ] && TOKEN=$(node -e 'console.log(require("crypto").randomBytes(24).toString("hex"))' 2>/dev/null)
echo "--- token len ${#TOKEN} ---"

# 3. Carpeta de staging en Termux (se bind-monta en /stage dentro del proot)
STAGE="$HOME/.nexo-proot-stage"
mkdir -p "$STAGE"
if [ -f /sdcard/Android/data/com.termux/files/nexo-ai-bridge.js ]; then
  cp /sdcard/Android/data/com.termux/files/nexo-ai-bridge.js "$STAGE/nexo-ai-bridge.js"
elif [ -f "$HOME/.nexo-bridge/nexo-ai-bridge.js" ]; then
  cp "$HOME/.nexo-bridge/nexo-ai-bridge.js" "$STAGE/nexo-ai-bridge.js"
else
  fail "no encuentro nexo-ai-bridge.js"
fi

cat > "$STAGE/env" <<EOF
BRIDGE_TOKEN=$TOKEN
PORT=8787
HOST=127.0.0.1
CLAUDE_BIN=claude
CODEX_BIN=codex
EOF

cat > "$STAGE/provision-inner.sh" <<'INNER'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
# El PATH dentro de proot no traía /usr/bin para los maintainer scripts de dpkg
# (touch: not found). Fijarlo arregla la instalación de paquetes.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_VER=v22.12.0
APT="apt-get -o APT::Sandbox::User=root -y"
echo "### apt update"; $APT update
echo "### apt deps mínimos (sin npm de Ubuntu para evitar python/node-gyp)"
$APT install --no-install-recommends ca-certificates curl xz-utils
echo "### Node oficial $NODE_VER (glibc/PIE, trae npm)"
mkdir -p /opt && cd /opt
curl -fsSL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-arm64.tar.xz" -o node.tar.xz
tar -xJf node.tar.xz && rm -f node.tar.xz
NODE_DIR="/opt/node-$NODE_VER-linux-arm64"
ln -sf "$NODE_DIR/bin/node" /usr/local/bin/node
ln -sf "$NODE_DIR/bin/npm"  /usr/local/bin/npm
ln -sf "$NODE_DIR/bin/npx"  /usr/local/bin/npx
export PATH="$NODE_DIR/bin:$PATH"
echo "### node: $(node -v)   npm: $(npm -v)"
echo "### npm i -g codex + claude-code (binarios glibc, corren bajo proot)"
npm install -g @openai/codex @anthropic-ai/claude-code
ln -sf "$NODE_DIR/bin/codex"  /usr/local/bin/codex  2>/dev/null || true
ln -sf "$NODE_DIR/bin/claude" /usr/local/bin/claude 2>/dev/null || true
echo "### colocar bridge + .env en /root"
mkdir -p /root/nexo-ai-bridge
cp /stage/nexo-ai-bridge.js /root/nexo-ai-bridge/nexo-ai-bridge.js
cp /stage/env /root/nexo-ai-bridge/.env
echo "### VERIFY codex:"; command -v codex && codex --version || echo "codex FALLO"
echo "### VERIFY claude:"; command -v claude && claude --version || echo "claude FALLO"
echo "### codex exec --help (flags):"; codex exec --help 2>&1 | head -45 || true
echo "### claude --help (flags):"; claude --help 2>&1 | head -70 || true
echo "### INNER_DONE"
INNER

# 4. Provisionar DENTRO de Ubuntu con /stage bind-montado
echo "--- entrando a proot (apt+node+npm, varios minutos) ---"
proot-distro login ubuntu --bind "$STAGE:/stage" -- bash /stage/provision-inner.sh || fail "provision-inner"

# 5. run.sh de Termux: arranca el bridge DENTRO del proot
mkdir -p "$HOME/.nexo-bridge"
cat > "$HOME/.nexo-bridge/run.sh" <<'RUN'
#!/data/data/com.termux/files/usr/bin/sh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
exec proot-distro login ubuntu -- sh -lc 'set -a; . /root/nexo-ai-bridge/.env; set +a; exec node /root/nexo-ai-bridge/nexo-ai-bridge.js'
RUN
chmod +x "$HOME/.nexo-bridge/run.sh"

echo "=== TOKEN=$TOKEN ==="
echo "MARKER_DONE"
