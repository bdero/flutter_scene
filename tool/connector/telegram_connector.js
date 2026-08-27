const { spawn } = require('child_process');

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
const TELEGRAM_BOT_TOKEN  = process.env.TELEGRAM_BOT_TOKEN;
const PROVIDER            = process.env.TELEGRAM_PROVIDER || 'openrouter';
const MODEL               = process.env.TELEGRAM_MODEL || undefined;
const CWD                 = process.env.TELEGRAM_CWD || __dirname;
const ALLOWED_USER_ID     = process.env.TELEGRAM_ALLOWED_USER_ID || undefined;
const RESTART_DELAY_MS    = parseInt(process.env.TELEGRAM_RESTART_DELAY_MS || '2000', 10);

// Validates minimum configuration before starting.
if (!TELEGRAM_BOT_TOKEN) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_BOT_TOKEN is not set.');
  process.exit(1);
}
if (API_KEYS.length === 0) {
  console.error('[Rotator] ERROR: environment variable TELEGRAM_API_KEYS is not set.');
  process.exit(1);
}

let currentKeyIndex = 0;
let clineProcess = null;
let restarting = false;

function startCline() {
  const currentKey = API_KEYS[currentKeyIndex];
  console.log(`\n[Rotator] Starting connector with key #${currentKeyIndex + 1}...`);

  // Builds the arguments. The key is rotated via `--api-key` / `--provider`
  // (which the Telegram connector actually reads) — NOT via inherited env var.
  const args = [
    'connect', 'telegram',
    '-k', TELEGRAM_BOT_TOKEN,   // required — read from env TELEGRAM_BOT_TOKEN
    '-i',                       // keeps the process in the foreground
    '--provider', PROVIDER,
    '--api-key', currentKey,    // rotated key via flag (not via inherited env)
    '--cwd', CWD,
  ];
  if (MODEL) args.push('--model', MODEL);
  if (ALLOWED_USER_ID) args.push('--allowed-user-id', ALLOWED_USER_ID);

  // Since the connector runs in the foreground (-i), we can pipe output and kill it.
  clineProcess = spawn('cline', args, { stdio: ['inherit', 'pipe', 'pipe'] });
  restarting = false;

  // In both streams, forward the output to the console AND search for limit
  // signals (429 / "daily free limit reached"). If the connector is visibly
  // connected but silent, that is normal operation (waiting for a message).
  const handleOutput = (stream, data) => {
    const output = data.toString();
    if (stream === 'stdout') process.stdout.write(output);
    else process.stderr.write(output);

    if (output.includes('429') || /daily free limit reached/i.test(output)) {
      console.warn(`\n[Rotator] Limit reached on key #${currentKeyIndex + 1}! Rotating...`);
      rotateKeyAndRestart();
    }
  };
  clineProcess.stdout && clineProcess.stdout.on('data', (d) => handleOutput('stdout', d));
  clineProcess.stderr && clineProcess.stderr.on('data', (d) => handleOutput('stderr', d));

  clineProcess.on('error', (err) => {
    // Prevents crash if the binary doesn't exist / spawn fails (e.g.: ENOENT).
    console.error(`[Rotator] Failed to start cline: ${err.message}`);
  });

  clineProcess.on('close', (code) => {
    console.log(`[Rotator] Connector closed with code ${code}`);
    if (!restarting) scheduleRestart(false); // restart shortly (except on manual stop)
  });
}

function rotateKeyAndRestart() {
  // Advances to the next key (wraps back to the first at the end of the list).
  currentKeyIndex = (currentKeyIndex + 1) % API_KEYS.length;
  scheduleRestart(true);
}

function scheduleRestart(manualKill) {
  if (restarting) return; // debounce against repeated 429 calls
  restarting = true;
  if (manualKill && clineProcess) clineProcess.kill('SIGTERM');
  setTimeout(startCline, RESTART_DELAY_MS); // wait before restarting
}

// Handles script shutdown (Ctrl+C) — does not restart and gives the child time to stop.
process.on('SIGINT', () => {
  restarting = true;
  if (clineProcess) clineProcess.kill('SIGTERM');
  setTimeout(() => process.exit(0), 500);
});

// Starts the wrapper.
startCline();