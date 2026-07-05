/// The WebGL2 backend executes GL commands while passes are encoded
/// (`CommandBuffer.submit` is bookkeeping), so a draw consumes its buffers
/// immediately: transient bytes must be device-resident when the view is
/// bound, and a buffer must never be rewritten after a draw referenced it
/// (the browser ghosts, copies, any buffer written while in use).
const bool kImmediateGpuExecution = true;
