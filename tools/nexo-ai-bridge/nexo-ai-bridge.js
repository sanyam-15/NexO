#!/usr/bin/env node
'use strict';

/**
 * Nexo AI bridge — usa tus SUSCRIPCIONES de Claude Code y Codex desde el celular.
 *
 * Expone el subconjunto OpenAI-compatible que usa Nexo (`POST
 * /v1/chat/completions`) y por dentro invoca las CLIs `claude` (Claude Code) y
 * `codex` (OpenAI Codex) en modo headless. Devuelve la forma que espera Nexo.
 *
 * Nexo (su OpenAiCompatibleClient) ya:
 *   - manda { model, messages, tools?, tool_choice? }
 *   - lee choices[0].message.tool_calls[0].function.arguments (JSON string)
 *   - si no hay tool_calls, parsea choices[0].message.content como JSON
 *     (quitando ```fences``` y extrayendo el primer {...} si hace falta)
 * Así que para "extractStructured" devolvemos el JSON tanto en content como en
 * tool_calls, y para "complete" devolvemos texto plano en content.
 *
 * Ruteo por modelo:
 *   - el id contiene "claude"            -> Claude Code  (claude -p)
 *   - empieza con gpt / o<n> / codex     -> Codex        (codex exec)
 *   - cualquier otro                      -> DEFAULT_BACKEND
 *
 * Sin dependencias: solo builtins de Node (http, child_process, crypto, fs, os).
 * Requiere Node 18+ (Termux trae 20+).
 *
 * Uso personal: consume tu límite de la suscripción y autentica con TU login.
 * No compartas credenciales ni lo expongas fuera de localhost. Las CLIs son
 * agentic, así que el bridge las corre con herramientas/config reducidas.
 */

const http = require('http');
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ---------------------------------------------------------------------------
// Configuración (vía variables de entorno; todas tienen un default razonable).
// ---------------------------------------------------------------------------
const HOST = process.env.HOST || '127.0.0.1';
const PORT = parseInt(process.env.PORT || '8787', 10);

// Token opcional. Si lo defines, Nexo debe mandar el mismo valor en el campo
// "API key" del proveedor (se envía como `Authorization: Bearer <token>`).
const BRIDGE_TOKEN = (process.env.BRIDGE_TOKEN || '').trim();

const CLAUDE_BIN = process.env.CLAUDE_BIN || 'claude';
const CODEX_BIN = process.env.CODEX_BIN || 'codex';

// Backend por defecto cuando el id del modelo no es claramente claude/codex.
const DEFAULT_BACKEND = (process.env.DEFAULT_BACKEND || 'codex').toLowerCase();

// Tope por petición. Por debajo del timeout de 180s que usa Nexo para locales.
const REQUEST_TIMEOUT_MS = parseInt(process.env.REQUEST_TIMEOUT_MS || '170000', 10);
const MAX_BODY_BYTES = parseInt(process.env.MAX_BODY_BYTES || String(20 * 1024 * 1024), 10);
const MAX_CONCURRENT = Math.max(1, parseInt(process.env.MAX_CONCURRENT || '1', 10));

// Carpeta de trabajo aislada para que las CLIs no toquen ningún repo real.
const SCRATCH_DIR = process.env.SCRATCH_DIR || path.join(os.tmpdir(), 'nexo-ai-bridge');
fs.mkdirSync(SCRATCH_DIR, { recursive: true });

const LOG = (...a) => console.log(new Date().toISOString(), ...a);
let activeRequests = 0;

function cliEnv() {
  // No heredes todo el ambiente del bridge (tokens/config privados). Mantén lo
  // mínimo para que las CLIs encuentren sus binarios y credenciales de usuario.
  const keep = [
    'ANDROID_DATA',
    'ANDROID_ROOT',
    // Token OAuth de suscripción de Claude Code (lo emite `claude setup-token`).
    'CLAUDE_CODE_OAUTH_TOKEN',
    'CODEX_HOME',
    'HOME',
    'LANG',
    'LC_ALL',
    // Termux runtime essentials. Sin LD_PRELOAD (libtermux-exec) los hijos no
    // pueden ejecutar binarios con shebang `#!/usr/bin/env node` y fallan con
    // "env: 'node': Permission denied". No son secretos, son del runtime.
    'LD_LIBRARY_PATH',
    'LD_PRELOAD',
    'LOGNAME',
    'PATH',
    'PREFIX',
    'SHELL',
    'TERM',
    'TMPDIR',
    'USER',
  ];
  const env = {};
  for (const k of keep) {
    if (process.env[k]) env[k] = process.env[k];
  }
  env.CLAUDE_CODE_SAFE_MODE = '1';
  env.NO_COLOR = '1';
  return env;
}

// ---------------------------------------------------------------------------
// Ruteo de modelo -> backend.
// ---------------------------------------------------------------------------
function backendFor(model) {
  const m = (model || '').toLowerCase();
  if (m.includes('claude')) return 'claude';
  if (/^(gpt|o\d|codex|chatgpt)/.test(m)) return 'codex';
  return DEFAULT_BACKEND === 'claude' ? 'claude' : 'codex';
}

// ---------------------------------------------------------------------------
// Aplanar los `messages` de OpenAI a un solo prompt + extraer imágenes.
// ---------------------------------------------------------------------------
function flatten(messages) {
  const systemParts = [];
  const userParts = [];
  const images = []; // { mediaType, base64 }

  for (const msg of messages || []) {
    const role = msg.role || 'user';
    const content = msg.content;
    const bucket = role === 'system' ? systemParts : userParts;

    if (typeof content === 'string') {
      if (content.trim()) bucket.push(content);
    } else if (Array.isArray(content)) {
      for (const part of content) {
        if (!part || typeof part !== 'object') continue;
        if (part.type === 'text' && typeof part.text === 'string') {
          bucket.push(part.text);
        } else if (part.type === 'image_url' && part.image_url && part.image_url.url) {
          const parsed = parseDataUri(part.image_url.url);
          if (parsed) images.push(parsed);
        }
      }
    }
  }

  return {
    system: systemParts.join('\n\n').trim(),
    user: userParts.join('\n\n').trim(),
    images,
  };
}

function parseDataUri(uri) {
  // data:image/png;base64,XXXX
  const m = /^data:([^;,]+);base64,(.+)$/s.exec(uri || '');
  if (!m) return null;
  return { mediaType: m[1], base64: m[2] };
}

function writeImages(images) {
  const paths = [];
  for (let i = 0; i < images.length; i++) {
    const ext = (images[i].mediaType.split('/')[1] || 'png').replace(/[^a-z0-9]/gi, '') || 'png';
    const file = path.join(SCRATCH_DIR, `img_${process.pid}_${Date.now()}_${i}.${ext}`);
    fs.writeFileSync(file, Buffer.from(images[i].base64, 'base64'));
    paths.push(file);
  }
  return paths;
}

// ---------------------------------------------------------------------------
// Construir el prompt final. Si la petición trae `tools` (Nexo forzando
// structured output), pedimos JSON puro que cumpla el schema de la función.
// ---------------------------------------------------------------------------
function buildPrompt({ system, user }, structuredTool) {
  const parts = [];
  if (system) parts.push(system);
  if (user) parts.push(user);

  if (structuredTool) {
    const schema = JSON.stringify(structuredTool.parameters || {}, null, 2);
    parts.push(
      [
        'FORMATO DE SALIDA (obligatorio):',
        'Responde ÚNICAMENTE con un objeto JSON válido que cumpla EXACTAMENTE el',
        'siguiente JSON Schema. Sin texto antes ni después, sin explicaciones y sin',
        'bloques de código (``` ). Solo el objeto JSON.',
        '',
        'JSON Schema:',
        schema,
      ].join('\n'),
    );
  }

  return parts.join('\n\n');
}

// ---------------------------------------------------------------------------
// Ejecutar una CLI capturando stdout/stderr con timeout duro.
// ---------------------------------------------------------------------------
function run(bin, args, { stdin } = {}) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawn(bin, args, { cwd: SCRATCH_DIR, env: cliEnv() });
    } catch (e) {
      return reject(new Error(`No se pudo lanzar "${bin}": ${e.message}`));
    }

    let stdout = '';
    let stderr = '';
    let done = false;

    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try { child.kill('SIGKILL'); } catch (_) {}
      reject(new Error(`"${bin}" excedió el tiempo límite (${REQUEST_TIMEOUT_MS} ms).`));
    }, REQUEST_TIMEOUT_MS);

    child.stdout.on('data', (d) => { stdout += d.toString(); });
    child.stderr.on('data', (d) => { stderr += d.toString(); });

    child.on('error', (e) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      reject(new Error(`Error ejecutando "${bin}": ${e.message}`));
    });

    child.on('close', (code) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });

    if (stdin != null) {
      child.stdin.write(stdin);
    }
    child.stdin.end();
  });
}

// ---------------------------------------------------------------------------
// Backend: Claude Code (claude -p --output-format json).
// ---------------------------------------------------------------------------
async function callClaude({ prompt, model, images }) {
  if (images.length) {
    // Claude Code headless no tiene una entrada de imagen estable; para visión
    // (recibos) usa un modelo Codex (gpt-*) o Gemma/nube.
    throw new Error('El backend Claude Code no soporta imágenes en modo headless. Usa un modelo Codex (gpt-*) o Gemma para visión.');
  }

  // Solo flags reales de Claude Code (verificados vs `claude --help` 2.1.x).
  // OJO: NO usar --bare (fuerza ANTHROPIC_API_KEY y nunca lee OAuth de la
  // suscripción). En modo -p con un prompt de Q&A no se disparan herramientas.
  const args = [
    '-p',
    '--output-format',
    'json',
    '--max-turns',
    '1',
    '--disable-slash-commands',
  ];
  if (model) args.push('--model', model);

  const { code, stdout, stderr } = await run(CLAUDE_BIN, args, { stdin: prompt });
  const out = stdout.trim();

  // --output-format json => un objeto { type, subtype, is_error, result, ... }.
  let obj = null;
  try {
    obj = JSON.parse(out);
  } catch (e) {
    // si no parseó, quizá no estás logueado o el flag cambió: muestra contexto
    if (code !== 0 || !out) {
      throw new Error(loginHint('claude', stderr || out || `exit ${code}`));
    }
    return out; // último recurso: stdout crudo
  }

  if (code !== 0) {
    throw new Error(loginHint('claude', stderr || out || `exit ${code}`));
  }
  if (obj && typeof obj === 'object') {
    if (obj.is_error) {
      throw new Error(`Claude Code devolvió error: ${obj.result || obj.subtype || 'desconocido'}`);
    }
    if (typeof obj.result === 'string') return obj.result;
    // algunos eventos traen el texto en otro campo
    if (typeof obj.text === 'string') return obj.text;
  }
  if (!out) throw new Error(loginHint('claude', stderr || `exit ${code}`));
  return out; // último recurso: stdout crudo
}

// ---------------------------------------------------------------------------
// Backend: Codex (codex exec). stdout = mensaje final del agente.
// ---------------------------------------------------------------------------
async function callCodex({ prompt, model, images }) {
  const imagePaths = writeImages(images);
  // El sandbox de Codex usa bubblewrap, que no corre dentro de proot (no hay
  // namespaces). Ya estamos en el sandbox de proot y solo pedimos texto (el
  // modelo no ejecuta comandos), así que bypasseamos su sandbox: es justo el
  // caso "externally sandboxed" que documenta el flag.
  const args = [
    'exec',
    '--skip-git-repo-check',
    '--ephemeral',
    '--ignore-user-config',
    '--ignore-rules',
    '--dangerously-bypass-approvals-and-sandbox',
    '--cd',
    SCRATCH_DIR,
    '--color',
    'never',
  ];
  // Con una cuenta ChatGPT, Codex solo acepta el modelo por defecto del plan
  // (p. ej. gpt-5.5); ids como gpt-5 / gpt-5-codex devuelven "model not
  // supported". Por eso NO forzamos -m: dejamos el default de la cuenta. Se
  // puede forzar con CODEX_MODEL (p. ej. si usas una cuenta por API key).
  const codexModel = (process.env.CODEX_MODEL || '').trim();
  if (codexModel) args.push('-m', codexModel);
  for (const img of imagePaths) args.push('-i', img);
  args.push('-');

  try {
    const { code, stdout, stderr } = await run(CODEX_BIN, args, { stdin: prompt });
    const out = stdout.trim();
    if (code !== 0) {
      throw new Error(loginHint('codex', stderr || out || `exit ${code}`));
    }
    if (!out) throw new Error(loginHint('codex', stderr || 'salida vacía'));
    return out;
  } finally {
    cleanupFiles(imagePaths);
  }
}

function cleanupFiles(files) {
  for (const file of files) {
    try { fs.unlinkSync(file); } catch (_) {}
  }
}

function loginHint(bin, detail) {
  const d = (detail || '').slice(0, 400);
  if (/login|auth|unauthorized|not logged|sign in|401/i.test(d)) {
    return `${bin}: parece que no has iniciado sesión. Corre \`${bin === 'claude' ? 'claude' : 'codex'} login\` en Termux. Detalle: ${d}`;
  }
  return `${bin} falló: ${d}`;
}

// ---------------------------------------------------------------------------
// Manejar /v1/chat/completions.
// ---------------------------------------------------------------------------
async function handleChat(body) {
  const model = (body.model || '').trim() || (DEFAULT_BACKEND === 'claude' ? 'claude-opus-4-8' : 'gpt-5-codex');

  const flat = flatten(body.messages);

  // Claude Code headless NO acepta imágenes. Un request con imágenes (recibos)
  // se rutea SIEMPRE a Codex, que soporta `-i`. Si Codex no está logueado/falla,
  // el bridge devuelve error y Nexo cae a Gemma on-device.
  let backend = backendFor(model);
  if (flat.images.length > 0) backend = 'codex';

  // ¿structured output? Nexo manda tools:[{type:function, function:{...}}].
  let structuredTool = null;
  if (Array.isArray(body.tools) && body.tools.length && body.tools[0].function) {
    structuredTool = body.tools[0].function; // { name, description, parameters }
  }

  const prompt = buildPrompt(flat, structuredTool);
  LOG(`-> ${backend} (${model}) structured=${!!structuredTool} imgs=${flat.images.length} chars=${prompt.length}`);

  const text = backend === 'claude'
    ? await callClaude({ prompt, model, images: flat.images })
    : await callCodex({ prompt, model, images: flat.images });

  return toOpenAiResponse(model, text, structuredTool);
}

function toOpenAiResponse(model, text, structuredTool) {
  const id = 'chatcmpl-' + crypto.randomUUID();
  const message = { role: 'assistant', content: text };

  if (structuredTool) {
    // Normaliza a JSON puro para los dos caminos del cliente de Nexo.
    const json = extractJsonString(text);
    message.content = json; // camino fallback (content como JSON)
    message.tool_calls = [
      {
        id: 'call_' + crypto.randomUUID(),
        type: 'function',
        function: { name: structuredTool.name, arguments: json },
      },
    ];
  }

  return {
    id,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{ index: 0, message, finish_reason: structuredTool ? 'tool_calls' : 'stop' }],
  };
}

/** Devuelve la mejor representación JSON-string posible del texto del modelo. */
function extractJsonString(text) {
  let s = (text || '').trim();
  if (s.startsWith('```')) {
    s = s.replace(/^```[a-zA-Z]*\s*/, '').replace(/\s*```$/, '').trim();
  }
  // ¿ya es JSON válido?
  try { JSON.parse(s); return s; } catch (_) {}
  // extrae el primer { ... último }
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start !== -1 && end > start) {
    const span = s.slice(start, end + 1);
    try { JSON.parse(span); return span; } catch (_) {}
  }
  return s; // que el parser tolerante de Nexo haga el resto
}

// ---------------------------------------------------------------------------
// Servidor HTTP.
// ---------------------------------------------------------------------------
function authorized(req) {
  if (!BRIDGE_TOKEN) return true;
  const h = req.headers['authorization'] || '';
  return h === `Bearer ${BRIDGE_TOKEN}`;
}

function sendJson(res, status, obj) {
  const data = JSON.stringify(obj);
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(data);
}

function sendError(res, status, message) {
  sendJson(res, status, { error: { message, type: 'bridge_error' } });
}

const server = http.createServer((req, res) => {
  const url = req.url || '';

  if (req.method === 'GET' && (url === '/' || url === '/health')) {
    if (!authorized(req)) return sendError(res, 401, 'Token inválido.');
    return sendJson(res, 200, { ok: true, service: 'nexo-ai-bridge', backends: ['claude', 'codex'] });
  }

  // Algunos clientes sondean /v1/models; respondemos algo mínimo.
  if (req.method === 'GET' && url.replace(/\/+$/, '') === '/v1/models') {
    if (!authorized(req)) return sendError(res, 401, 'Token inválido.');
    return sendJson(res, 200, {
      object: 'list',
      data: [
        { id: 'claude-opus-4-8', object: 'model', owned_by: 'claude-code' },
        { id: 'gpt-5-codex', object: 'model', owned_by: 'codex' },
      ],
    });
  }

  if (req.method === 'POST' && url.replace(/\/+$/, '').endsWith('/chat/completions')) {
    if (!authorized(req)) return sendError(res, 401, 'Token inválido.');
    if (activeRequests >= MAX_CONCURRENT) {
      return sendError(res, 429, 'Bridge ocupado. Intenta de nuevo en unos segundos.');
    }

    let raw = '';
    let tooLarge = false;
    req.on('data', (c) => {
      if (tooLarge) return;
      raw += c;
      if (Buffer.byteLength(raw) > MAX_BODY_BYTES) {
        tooLarge = true;
        raw = '';
        return sendError(res, 413, 'La petición excede el tamaño máximo del bridge.');
      }
    });
    req.on('end', async () => {
      if (tooLarge) return;
      let body;
      try {
        body = JSON.parse(raw || '{}');
      } catch (_) {
        return sendError(res, 400, 'JSON inválido en el cuerpo.');
      }
      activeRequests++;
      try {
        const result = await handleChat(body);
        return sendJson(res, 200, result);
      } catch (e) {
        LOG('ERROR', e.message);
        return sendError(res, 500, e.message || 'Error interno del bridge.');
      } finally {
        activeRequests--;
      }
    });
    return;
  }

  sendError(res, 404, 'No encontrado.');
});

server.listen(PORT, HOST, () => {
  LOG(`Nexo AI bridge escuchando en http://${HOST}:${PORT}`);
  LOG(`Backends: claude="${CLAUDE_BIN}", codex="${CODEX_BIN}", default="${DEFAULT_BACKEND}"`);
  LOG(`Auth por token: ${BRIDGE_TOKEN ? 'activado' : 'desactivado'}`);
  LOG(`Scratch dir: ${SCRATCH_DIR}`);
});
