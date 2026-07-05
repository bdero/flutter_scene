/// Native Flutter GPU backends (Metal, Vulkan, GLES via Impeller) execute
/// GPU work after command buffer submission, so transient uploads can be
/// batched per block and flushed just before each submit.
const bool kImmediateGpuExecution = false;
