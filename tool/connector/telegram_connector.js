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
//   export TELEGRAM_AVAILABLE_MODELS="model-a,model-b"   # models to rotate (REQUIRED)
//   export TELEGRAM_CWD="/path/to/workspace"    # (optional) default: this directory
//   export TELEGRAM_ALLOWED_USER_ID="123..."    # (optional) restrict to a user
//   export TELEGRAM_RESTART_DELAY_MS="2000"     # (optional) delay before restarting
//
// Rotation grid: keys × models. A "daily free limit" 429 blocks only the
// current (key, model) combo; the wrapper restarts on the next free combo.
// --model is ALWAYS passed explicitly — cline's own default is never used.
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

// The numeric bot user ID is the first segment of the token (before the ':').
// We use it to filter shared cline.log entries so that multiple duplicated
// instances (each with a different TELEGRAM_BOT_TOKEN) don't cross-react to
// each other's log entries (e.g. Instance A handling Instance B's messages).
const BOT_USER_ID = (TELEGRAM_BOT_TOKEN || '').split(':')[0];

// Model list for rotation. The wrapper ALWAYS controls the model explicitly —
// `--model` is never omitted, so the key×model cooldown grid reflects exactly
// what the connector runs. With K keys and M models there are K×M combos; a
// "daily free limit" hit blocks only one combo and rotation moves on, which
// makes a full cooldown (all combos blocked) unlikely unless every key is
// exhausted on every model.
const MODELS = AVAILABLE_MODELS;

// Validates minimum configuration before starting.
if (!TELEGRAM_BOT_TOKEN) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_BOT_TOKEN is not set.');
  process.exit(1);
}
if (API_KEYS.length === 0) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_API_KEYS is not set.');
  process.exit(1);
}
if (MODELS.length === 0) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_AVAILABLE_MODELS is not set.');
  console.error('[Rotator] The wrapper always controls model switching explicitly — set it to the');
  console.error('[Rotator] comma-separated models to rotate, e.g. TELEGRAM_AVAILABLE_MODELS="model-a,model-b".');
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
const BOT_USER_ID_RE = /"botUserId"\s*:\s*"([^"]+)"/;
const PID_RE = /"pid"\s*:\s*(\d+)/;

// The PID of the currently running cline child process (our own child). We use
// it to filter shared cline.log entries for lines that lack a botUserId field.
let currentClinePid = null;

// Filter: is this log line from OUR bot? Uses botUserId where available,
// falls back to child PID. This prevents cross-talk between duplicated
// instances that share the same ~/.cline/data/logs/cline.log file.
function isOurBot(line) {
  const m = line.match(BOT_USER_ID_RE);
  if (m) return m[1] === BOT_USER_ID;
  // Fall back to PID matching for lines that lack botUserId.
  if (currentClinePid !== null) {
    const pidMatch = line.match(PID_RE);
    if (pidMatch) return parseInt(pidMatch[1], 10) === currentClinePid;
  }
  // Can't determine bot identity — accept as potential match (best-effort).
  return true;
}

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
// NOTE: The pgrep pattern is scoped to THIS bot token so that multiple
// duplicated instances (each with a different TELEGRAM_BOT_TOKEN) don't
// kill each other's connectors.
// We do NOT call `cline connect --stop` here — that's a global command that
// stops *any* running connector, not just ours. Instead we kill via pgrep,
// which is now token-scoped.
function purgeStale() {
  try {
    // Only match processes carrying THIS bot token — not generic "connect
    // telegram" which would catch and kill other bot instances.
    const pattern = `connect telegram.*${TELEGRAM_BOT_TOKEN}`;
    const out = execFileSync('pgrep', ['-f', pattern], { encoding: 'utf8' });
    const myPid = process.pid;
    for (const raw of out.split('\n')) {
      const pid = parseInt(raw, 10);
      // NOTE: no childPid skip — if our own child ignored SIGTERM and is hung,
      // this SIGKILL is the only thing that will actually stop it. Without it,
      // the hung connector keeps polling the bot and replying with limit
      // errors while its replacement fights it over getUpdates.
      if (!pid || pid === myPid) continue;
      try {
        process.kill(pid, 'SIGKILL');
        log(`[Rotator] Killed stale connector pid ${pid}`);
      } catch (_) {}
    }
  } catch (_) {
    // pgrep absent, no matching processes, or token pattern didn't match — nothing to purge.
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
  // Always pass --model explicitly: never let cline fall back to its own
  // default, so the key×model cooldown grid matches what actually runs.
  args.push('--model', MODELS[modelIndex]);
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

// How long to wait after SIGTERM before force-killing a connector that ignores
// graceful shutdown. A hung connector keeps polling the bot and replying with
// limit errors while the replacement connector fights it over getUpdates.
const STOP_GRACE_MS = 3000;

// Stops the current connector. SIGTERM first, escalating to SIGKILL if the
// process doesn't exit within STOP_GRACE_MS. Calls onStopped() once the child
// is actually gone (or immediately when there is nothing to stop) — callers
// must not assume the connector is dead until then. Token-scoped by design:
// never touches connectors belonging to other bot instances.
function stopCurrent(onStopped) {
  const finish = () => { if (onStopped) onStopped(); };
  const child = clineProcess;
  if (!child || child.exitCode !== null || child.killed) {
    finish();
    return;
  }

  let finished = false;
  const once = () => {
    if (finished) return;
    finished = true;
    finish();
  };
  child.once('close', once);

  try {
    child.kill('SIGTERM');
  } catch (err) {
    log(`[Rotator] Failed to kill cline: ${err.message}`);
  }

  // Escalate if the connector ignores SIGTERM.
  setTimeout(() => {
    if (finished || child.exitCode !== null) return;
    try {
      child.kill('SIGKILL');
      log('[Rotator] Connector ignored SIGTERM; sent SIGKILL.');
    } catch (_) {}
  }, STOP_GRACE_MS);

  // Absolute safety net: never wait forever for the child to exit.
  setTimeout(once, STOP_GRACE_MS + 5000);
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

  // Wait until the old connector is actually dead (SIGTERM, then SIGKILL
  // escalation) before purging and starting the replacement — two pollers on
  // one bot token conflict over Telegram getUpdates.
  stopCurrent(() => {
    purgeStale();                    // no stale daemons left to steal updates

    setTimeout(() => {               // wait before restarting
      restarting = false;
      if (pendingRotation) {
        [index, modelIndex] = pendingRotation;
        pendingRotation = null;
        log(`[Rotator] Applying queued rotation: key #${index}, model #${modelIndex}.`);
      }
      startCline(index, modelIndex);
    }, delay);
  });
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
  currentClinePid = clineProcess.pid;

  clineProcess.on('error', (err) => {
    log(`[Rotator] Failed to start cline: ${err.message}`);
  });

  clineProcess.on('close', (code) => {
    if (restarting) return;            // a rotation's timer will take over
    currentClinePid = null;
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
const TURN_ACK_DELAY_MS = 30 * 1000;          // ack only if no reply lands by then

let activeTurn = null;                       // { chatId, startedAt, pings, timer }
let pendingAck = null;                       // { chatId, timer } — ack not yet sent
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
  cancelPendingAck();
}

// Actually starts tracking a turn: sends the acknowledgement and begins the
// progress pings. Called only once it's clear the connector hasn't answered
// instantly, i.e. a genuinely long-running task.
function startTurn(chatId) {
  stopTurn();
  activeTurn = { chatId, startedAt: Date.now(), pings: 0, timer: null };
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

  const now = Date.now();
  if (now - lastAckAt < TURN_ACK_THROTTLE_MS) return;   // burst guard
  lastAckAt = now;
  log(`[Turn] Acknowledging chat ${chatId}${allBlocked ? ' (quota exhausted notice)' : ''}.`);
  sendTelegramMessage(chatId, text);
}

function cancelPendingAck() {
  if (pendingAck && pendingAck.timer) clearTimeout(pendingAck.timer);
  pendingAck = null;
}

// Fired when the connector logs that a user message arrived. The ack is
// DELAYED: if the connector replies quickly (chat commands like /new, or
// simple questions), the reply lands first and the ack is cancelled. It only
// fires when nothing has come back — a genuinely long-running task.
function onTurnStarted(line) {
  const chatId = extractChatId(line);
  if (!chatId) {
    log('[Turn] Message received, but no chat id found in the log line.');
    return;
  }

  // Slash commands (/new, /cwd, /tools, …) are handled instantly by the
  // connector — never treat them as heavy tasks.
  const preview = (line.match(/"textPreview":"((?:[^"\\]|\\.)*)"/) || [])[1] || '';
  if (preview.startsWith('/')) {
    log(`[Turn] Command "${preview}" received — handled instantly, no ack.`);
    return;
  }

  // Another message from the same chat while we're already working: just reset
  // the elapsed clock, no new acknowledgement.
  if (activeTurn && activeTurn.chatId === chatId) {
    activeTurn.startedAt = Date.now();
    activeTurn.pings = 0;
    log('[Turn] Follow-up message received; still working.');
    return;
  }

  cancelPendingAck();

  pendingAck = {
    chatId,
    timer: setTimeout(() => {
      pendingAck = null;
      log(`[Turn] No reply after ${TURN_ACK_DELAY_MS / 1000}s (chat ${chatId}) — acknowledging so it doesn't feel stuck.`);
      startTurn(chatId);
    }, TURN_ACK_DELAY_MS),
  };
}

function onTurnDone(ok) {
  // Cancel any not-yet-sent ack FIRST — a fast reply (like /new) lands while
  // its acknowledgement is still waiting on the delay timer, and activeTurn
  // doesn't exist yet in that case.
  cancelPendingAck();
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
// secondary source. Both are filtered by isOurBot() so multiple duplicated
// instances don't cross-react to each other's log entries.
function pollLogs() {
  tailLog(SHARED_CLINE_LOG, (line) => {
    if (!IS_TELEGRAM_RE.test(line)) return;
    if (!isOurBot(line)) return;
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
      if (LIMIT_RE.test(line) && isOurBot(line)) onLimitSignal(line);
    });
  }
}

// Clean shutdown: stop the child before the wrapper exits.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    log(`[Rotator] ${sig} received; stopping connector.`);
    // Wait for the child to actually die (incl. SIGKILL escalation) so a hung
    // connector isn't orphaned to keep polling the bot after we exit.
    stopCurrent(() => process.exit(0));
  });
}

// Starts the wrapper. Purge stale connectors first, then give them a moment to
// release the bot token before our foreground connector takes it over.
purgeStale();
log(`[Rotator] Stale connectors purged; starting in ${RESTART_DELAY_MS}ms...`);
setInterval(pollLogs, 1000);            // check cline's logs every second
setTimeout(() => startCline(0, 0), RESTART_DELAY_MS);