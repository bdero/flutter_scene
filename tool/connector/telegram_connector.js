const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION — ALL values come from environment variables (not embedded in
// code). Set them in the shell before running:
//
//   export TELEGRAM_BOT_TOKEN="123456789:ABCDEF..."
//   export TELEGRAM_API_KEYS="sk-or-v1-AAAA..., sk-or-v1-BBBB..."   # keys for rotation
//   export TELEGRAM_PROVIDER="openrouter"      # (optional) default: openrouter
//   export TELEGRAM_MODEL="YOUR-MODEL"          # (optional) model to use
//   export TELEGRAM_CWD="/path/to/workspace"    # (optional) default: this directory
//   export TELEGRAM_ALLOWED_USER_ID="123..."    # (optional) restrict to a user
//   export TELEGRAM_RESTART_DELAY_MS="2000"     # (optional) delay before restarting
// ─────────────────────────────────────────────────────────────────────────────

// Reads the keys for rotation, accepting comma, space, or `;` as separators.
const API_KEYS = (process.env.TELEGRAM_API_KEYS || '')
  .split(/[,;\s]+/)
  .map((k) => k.trim())
  .filter(Boolean);

// Basic config with safe fallbacks.
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const ALLOWED_USER_ID = process.env.TELEGRAM_ALLOWED_USER_ID || '';
const RESTART_DELAY_MS = parseInt(process.env.TELEGRAM_RESTART_DELAY_MS || '2000', 10);
const AVAILABLE_MODELS = (process.env.TELEGRAM_AVAILABLE_MODELS || '')
  .split(/[,;\s]+/)
  .map((k) => k.trim())
  .filter(Boolean);

// Model list for rotation. Falls back to a single slot holding the default
// model (empty string = let cline use its own configured default; buildArgs
// then omits the --model flag) so the key×model rotation grid never divides
// by zero when TELEGRAM_AVAILABLE_MODELS is unset.
const DEFAULT_MODEL = process.env.TELEGRAM_MODEL || '';
const MODELS = AVAILABLE_MODELS.length > 0 ? AVAILABLE_MODELS : [DEFAULT_MODEL];

// Validates minimum configuration before starting.
if (!TELEGRAM_BOT_TOKEN) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_BOT_TOKEN is not set.');
  process.exit(1);
}
if (API_KEYS.length === 0) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_API_KEYS is not set.');
  process.exit(1);
}

// Where cline keeps the connector's own logs. We rotate off these files instead
// of parsing stdout: the Telegram connector records runtime errors (e.g.
// `INFERENCE_CAP_ERROR` / "Error 429: Daily free limit reached") here.
const CLINE_LOGS_DIR = path.join(os.homedir(), '.cline', 'data', 'logs');
const TELEGRAM_LOG_DIR = path.join(CLINE_LOGS_DIR, 'connectors', 'telegram');
const SHARED_CLINE_LOG = path.join(CLINE_LOGS_DIR, 'cline.log');

// All diagnostics also go to this file, so "no log" can't hide anything even
// when stdout is not redirected.
const WRAPPER_LOG = path.join(__dirname, 'connector.log');

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.join(' ')}`;
  try {
    fs.appendFileSync(WRAPPER_LOG, line + '\n');
  } catch (_) {}
  console.log(line);
}

// Matches rate-limit / quota / capacity errors. Kept to strong patterns so
// unrelated numbers (e.g. token counts) can't trigger a false rotation — the
// real errors always carry INFERENCE_CAP_ERROR, "daily free limit", or an
// explicit "Error 429"/"rate limit"/"too many requests".
const LIMIT_RE = /INFERENCE_CAP_ERROR|daily free limit|Error 429|rate limit|too many requests|quota exceeded/i;
// Only react to telegram-connector entries in the shared cline.log.
const IS_TELEGRAM_RE = /"component"\s*:\s*"telegram-connect"/;

let clineProcess = null;
let restarting = false;
let curKeyIndex = 0;
let curModelIndex = 0;
// If a generic (crash) restart is already pending when a limit rotation fires,
// remember the rotation target so the next start uses it instead of the key
// that just hit the limit again.
let pendingRotation = null;
// Remembers which (key, model) combos are on cooldown and until when, so a
// model-scoped limit ("Daily free limit reached on model X") is not re-tried
// every restart. Key `"<keyIdx>:<modelIdx>"` -> unblock epoch ms.
const blockedCombos = new Map();
const COOLDOWN_DEFAULT_MS = 15 * 60 * 1000;      // fallback when no "try again in"
const COOLDOWN_GRACE_MS = 2 * 60 * 1000;         // extra safety beyond quoted time
// Spawns a short-lived `cline` helper (e.g. `connect --stop`) without crashing
// the wrapper if the binary is missing or the command fails.
function runCline(args) {
  const child = spawn('cline', args, { stdio: ['ignore', 'ignore', 'ignore'] });
  child.on('error', (err) => {
    log(`[Rotator] Failed to spawn "cline ${args.join(' ')}": ${err.message}`);
  });
  return child;
}

// Kills any connector still polling this bot token from an earlier run. Leftover
// background daemons steal Telegram updates and answer the user — the wrapper
// never hears the errors they get.
function purgeStale() {
  runCline(['connect', '--stop']);

  try {
    const out = execFileSync('pgrep', ['-f', 'connect telegram'], { encoding: 'utf8' });
    const myPid = process.pid;
    const childPid = clineProcess ? clineProcess.pid : -1;
    for (const raw of out.split('\n')) {
      const pid = parseInt(raw, 10);
      if (!pid || pid === myPid || pid === childPid) continue;
      try {
        process.kill(pid, 'SIGKILL');
        log(`[Rotator] Killed stale connector pid ${pid}`);
      } catch (_) {}
    }
  } catch (_) {
    // pgrep absent, or no matching processes — nothing to purge.
  }
}

// Builds the `cline connect telegram` argv from the current key/model indices.
function buildArgs(index, modelIndex) {
  const args = [
    'connect', 'telegram',
    '-i',                          // foreground: the connector stays attached and
                                   // its errors land in cline's log files we tail
    '-k', TELEGRAM_BOT_TOKEN,
    '--api-key', API_KEYS[index],
  ];
  const currentModel = MODELS[modelIndex];
  if (currentModel) args.push('--model', currentModel);
  if (ALLOWED_USER_ID) args.push('--allowed-user-id', ALLOWED_USER_ID);
  return args;
}
// Parses "Try again in 7h 3m" (or "1h", "30m") out of an error line, returns ms.
function parseCooldownMs(line) {
  const hm = line.match(/try again in\s+(\d+)h(?:\s+(\d+)m)?/i);
  if (hm) {
    const hours = parseInt(hm[1], 10);
    const mins = hm[2] ? parseInt(hm[2], 10) : 0;
    return (hours * 60 + mins) * 60 * 1000;
  }
  const m = line.match(/try again in\s+(\d+)m/i);
  if (m) return parseInt(m[1], 10) * 60 * 1000;
  return 0;
}

// Returns the next (key, model) pair that is NOT on cooldown, scanning across
// keys first, then models. Rotating the model matters: OpenRouter's "daily free
// limit" is per model, so a fresh model escapes a model-scoped limit even when
// every key is exhausted on the old one.
function nextCombo() {
  const now = Date.now();
  const total = API_KEYS.length * MODELS.length;
  // Start one slot after the current combo so we always make progress.
  const start = curKeyIndex + curModelIndex * API_KEYS.length;
  for (let step = 1; step <= total; step++) {
    const slot = (start + step) % total;
    const k = slot % API_KEYS.length;
    const m = Math.floor(slot / API_KEYS.length);
    const unblockAt = blockedCombos.get(`${k}:${m}`) || 0;
    if (unblockAt <= now) return [k, m];
  }
  return null;                          // every key × model combo is on cooldown
}

// Earliest unblock time across all combos, used to sleep until something frees.
function earliestUnblock() {
  let earliest = Infinity;
  for (const unblockAt of blockedCombos.values()) {
    if (unblockAt < earliest) earliest = unblockAt;
  }
  return earliest === Infinity ? Date.now() + COOLDOWN_DEFAULT_MS : earliest;
}

function stopCurrent() {
  if (clineProcess && clineProcess.exitCode === null && !clineProcess.killed) {
    try {
      clineProcess.kill('SIGTERM');
    } catch (err) {
      log(`[Rotator] Failed to kill cline: ${err.message}`);
    }
  }
  runCline(['connect', '--stop']);
}

function scheduleRestart(index, modelIndex, delay = RESTART_DELAY_MS) {
  if (restarting) {
    // A restart is already scheduled. If this is a limit rotation superseding a
    // crash-restart that was queued first, keep the rotation target so the next
    // start doesn't loop back onto the exhausted key.
    pendingRotation = [index, modelIndex];
    log(`[Rotator] Restart already scheduled; queueing target key #${index}, model #${modelIndex}.`);
    return;
  }
  restarting = true;

  stopCurrent();
  purgeStale();                      // no stale daemons left to steal updates

  setTimeout(() => {                  // wait before restarting
    restarting = false;
    if (pendingRotation) {
      [index, modelIndex] = pendingRotation;
      pendingRotation = null;
      log(`[Rotator] Applying queued rotation: key #${index}, model #${modelIndex}.`);
    }
    startCline(index, modelIndex);
  }, delay);
}

function startCline(index, modelIndex) {
  curKeyIndex = index;
  curModelIndex = modelIndex;
  const args = buildArgs(index, modelIndex);
  const startedAt = Date.now();
  log(`[Rotator] Starting connector (key #${index}, model #${modelIndex})`);
  log(`[Rotator] pid=${process.pid} running: cline ${args.join(' ')}`);

  // stdin is a pipe we keep open (never write/end it): a headless run inherits
  // /dev/null for stdin, and an immediate EOF there can make the foreground
  // connector quit right after starting.
  clineProcess = spawn('cline', args, { stdio: ['pipe', 'pipe', 'pipe'] });

  clineProcess.on('error', (err) => {
    log(`[Rotator] Failed to start cline: ${err.message}`);
  });

  clineProcess.on('close', (code) => {
    if (restarting) return;            // a rotation's timer will take over
    clineProcess = null;

    const elapsedMs = Date.now() - startedAt;
    const delay = elapsedMs < 1000 ? Math.max(elapsedMs, 1000) : RESTART_DELAY_MS;

    log(`[Rotator] Connector exited with code ${code} after ${elapsedMs}ms. Restarting in ${delay}ms...`);
    scheduleRestart(index, modelIndex, delay);
  });
}
// ─────────────────────────────────────────────────────────────────────────────
// Log tailing — watch the files the `-i` connector writes and rotate on limit.
// ─────────────────────────────────────────────────────────────────────────────

// Keeps the last-read byte offset per file.
const tailState = new Map();

// Tails a single file, calling onLine for every newly-appended complete line.
// Handles truncation/rotation by resetting the offset back to 0.
function tailLog(file, onLine) {
  let size;
  try {
    size = fs.statSync(file).size;
  } catch (_) {
    return;                            // file not there yet — try again next tick
  }
  const prev = tailState.get(file);
  if (prev === undefined) {
    tailState.set(file, size);         // first sight: don't react to old content
    return;
  }
  if (size < prev) {
    tailState.set(file, size);         // file was truncated/rotated
    return;
  }
  if (size === prev) return;

  const fd = fs.openSync(file, 'r');
  const buf = Buffer.alloc(size - prev);
  fs.readSync(fd, buf, 0, buf.length, prev);
  fs.closeSync(fd);
  tailState.set(file, size);

  for (const line of buf.toString('utf8').split('\n')) {
    if (line.trim()) onLine(line);
  }
}

// Guards against reacting twice to the same underlying error: cline logs each
// failed turn as both "Telegram reply failed" and "Telegram turn handling
// failed", so the same 429 produces two DIFFERENT limit lines ~1ms apart. An
// exact-line comparison can't catch that, so we use a time window instead.
let lastLimitHandledAt = 0;
const LIMIT_DEDUPE_MS = 5000;

function onLimitSignal(line) {
  const now = Date.now();
  if (now - lastLimitHandledAt < LIMIT_DEDUPE_MS) {
    log(`[Rotator] Duplicate limit signal within ${LIMIT_DEDUPE_MS}ms window; ignoring.`);
    return;
  }
  lastLimitHandledAt = now;

  log(`[Rotator] Limit detected in cline log: ${line.slice(0, 300)}`);

  // This exact (key, model) pair is exhausted. From here on we skip it until
  // the cooldown quoted in the error (or a default) has passed.
  const cooldownMs = parseCooldownMs(line) || COOLDOWN_DEFAULT_MS;
  const unblockAt = now + cooldownMs;
  blockedCombos.set(`${curKeyIndex}:${curModelIndex}`, unblockAt);
  log(`[Rotator] Blocked key #${curKeyIndex} + model #${curModelIndex} (${MODELS[curModelIndex]}) until ${new Date(unblockAt).toISOString()}`);

  const next = nextCombo();
  if (next === null) {
    // Every key×model combo is exhausted right now: stop hammering and sleep
    // until the earliest one frees up (plus a grace period), then restart with
    // that exact combo.
    const waitMs = Math.max(earliestUnblock() - now + COOLDOWN_GRACE_MS, 30 * 1000);
    log(`[Rotator] All ${API_KEYS.length}×${MODELS.length} combos on cooldown. Waiting ${Math.round(waitMs / 60000)}m before retrying.`);
    // Find the combo that becomes available first.
    let parkKey = 0, parkModel = 0, parkAt = Infinity;
    for (let m = 0; m < MODELS.length; m++) {
      for (let k = 0; k < API_KEYS.length; k++) {
        const unblockAt = blockedCombos.get(`${k}:${m}`) || 0;
        if (unblockAt < parkAt) { parkAt = unblockAt; parkKey = k; parkModel = m; }
      }
    }
    scheduleRestart(parkKey, parkModel, waitMs);
    return;
  }

  const [nextKey, nextModel] = next;
  log(`[Rotator] Rotating to key #${nextKey}, model #${nextModel} (${MODELS[nextModel]})`);
  scheduleRestart(nextKey, nextModel);
}

// ─────────────────────────────────────────────────────────────────────────────
// Turn activity — acknowledge heavy tasks in the chat so they don't feel stuck,
// and surface progress in the wrapper log.
// ─────────────────────────────────────────────────────────────────────────────

const TURN_ACK_TEXT = '🧠 Working on it — heavy tasks can take a few minutes. You\'ll get the answer here when it\'s done.';
const TURN_PING_TEXT = (mins) => `⏳ Still working… (${mins} min elapsed)`;
const TURN_PING_INTERVAL_MS = 5 * 60 * 1000; // progress ping cadence (every 5 min)
const TURN_MAX_PINGS = 12;                   // safety cap (~60 min of pings)
const TURN_ACK_THROTTLE_MS = 15 * 1000;      // don't re-ack bursts of messages

let activeTurn = null;                       // { chatId, startedAt, pings, timer }
let lastAckAt = 0;

// Sends a chat message through the Telegram Bot API as the same bot.
async function sendTelegramMessage(chatId, text) {
  try {
    const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text, disable_notification: true }),
    });
    const body = await res.json().catch(() => ({}));
    if (!body.ok) log(`[Telegram] sendMessage failed: ${body.description || `HTTP ${res.status}`}`);
    return body.ok === true;
  } catch (err) {
    log(`[Telegram] sendMessage error: ${err.message}`);
    return false;
  }
}

// Last chat id seen in any telegram-connect log line; fallback when a line
// lacks a threadId (e.g. some "message received" entries).
let lastSeenChatId = null;

// Turns "telegram:123456" thread ids (also works for group ids) into chat ids.
function extractChatId(line) {
  const m = line.match(/"threadId":"telegram:(-?\d+)"/);
  if (m) {
    lastSeenChatId = m[1];
    return m[1];
  }
  return lastSeenChatId;               // fallback: last chat seen in the logs
}

function stopTurn() {
  if (activeTurn && activeTurn.timer) clearInterval(activeTurn.timer);
  activeTurn = null;
}

// Fired when the connector logs that a user message arrived: acknowledge it in
// the chat right away and start progress pings until the reply is sent.
function onTurnStarted(line) {
  const chatId = extractChatId(line);
  const now = Date.now();
  if (!chatId) {
    log('[Turn] Message received, but no chat id found in the log line.');
    return;
  }

  // Another message from the same chat while we're already working: just reset
  // the elapsed clock, no new acknowledgement.
  if (activeTurn && activeTurn.chatId === chatId) {
    activeTurn.startedAt = now;
    activeTurn.pings = 0;
    log('[Turn] Follow-up message received; still working.');
    return;
  }

  stopTurn();
  activeTurn = { chatId, startedAt: now, pings: 0, timer: null };
  activeTurn.timer = setInterval(() => {
    if (!activeTurn) return;
    if (activeTurn.pings >= TURN_MAX_PINGS) {
      log('[Turn] Ping cap reached; going quiet until the reply lands.');
      stopTurn();
      return;
    }
    activeTurn.pings++;
    const mins = Math.round((Date.now() - activeTurn.startedAt) / 60000);
    sendTelegramMessage(activeTurn.chatId, TURN_PING_TEXT(mins));
  }, TURN_PING_INTERVAL_MS);

  // If every key/model combo is parked on quota, say so instead of a generic ack.
  const allBlocked = nextCombo() === null;
  const text = allBlocked
    ? `⛔ All API keys/models are on cooldown right now (until ${new Date(earliestUnblock()).toISOString().slice(11, 16)} UTC). Your message is queued — I'll answer when quota resets.`
    : TURN_ACK_TEXT;

  if (now - lastAckAt < TURN_ACK_THROTTLE_MS) return;   // burst guard
  lastAckAt = now;
  log(`[Turn] Task started for chat ${chatId} — sending acknowledgement${allBlocked ? ' (quota exhausted notice)' : ''}.`);
  sendTelegramMessage(chatId, text);
}

function onTurnDone(ok) {
  if (!activeTurn) return;
  const mins = Math.round((Date.now() - activeTurn.startedAt) / 60000);
  log(`[Turn] Task ${ok ? 'completed' : 'failed'} after ~${mins} min (chat ${activeTurn.chatId}).`);
  stopTurn();
}

// Maps connector log messages to turn events.
function handleTurnEvent(line) {
  const msg = (line.match(/"msg":"([^"]+)"/) || [])[1] || '';

  if (msg === 'Telegram message received') { onTurnStarted(line); return; }
  if (msg === 'Telegram reply completed') { onTurnDone(true); return; }
  if (msg === 'Telegram reply failed' || msg === 'Telegram turn handling failed') {
    onTurnDone(false);   // the limit path logs the details
    return;
  }
  if (msg === 'Telegram thread started RPC session' || msg === 'Telegram thread reusing RPC session') {
    const sessionId = (line.match(/"sessionId":"([^"]+)"/) || [])[1] || '?';
    log(`[Turn] ${msg} (session ${sessionId})`);
  }
}

// Polls the connector's own logs. The shared cline.log carries the
// telegram-connect bridge errors (most reliable signal); the per-bot log is a
// secondary source.
function pollLogs() {
  tailLog(SHARED_CLINE_LOG, (line) => {
    if (!IS_TELEGRAM_RE.test(line)) return;
    if (LIMIT_RE.test(line)) {
      // This line is the failed turn itself: end the turn (stops progress
      // pings) before the rotation path takes over.
      onTurnDone(false);
      onLimitSignal(line);
      return;
    }
    handleTurnEvent(line);
  });

  let botLogs = [];
  try {
    botLogs = fs.readdirSync(TELEGRAM_LOG_DIR)
      .filter((f) => f.endsWith('.log'))
      .map((f) => path.join(TELEGRAM_LOG_DIR, f));
  } catch (_) {}
  for (const file of botLogs) {
    tailLog(file, (line) => {
      if (LIMIT_RE.test(line)) onLimitSignal(line);
    });
  }
}

// Clean shutdown: stop the child before the wrapper exits.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    log(`[Rotator] ${sig} received; stopping connector.`);
    stopCurrent();
    process.exit(0);
  });
}

// Starts the wrapper. Purge stale connectors first, then give them a moment to
// release the bot token before our foreground connector takes it over.
purgeStale();
log(`[Rotator] Stale connectors purged; starting in ${RESTART_DELAY_MS}ms...`);
setInterval(pollLogs, 1000);            // check cline's logs every second
setTimeout(() => startCline(0, 0), RESTART_DELAY_MS);