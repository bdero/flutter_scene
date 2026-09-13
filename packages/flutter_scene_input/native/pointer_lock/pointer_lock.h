// Cursor lock for flutter_scene_input's PointerLock, bound through dart:ffi by
// lib/src/pointer_lock/pointer_lock_backend_native.dart.
//
// Every function must be called on the platform thread, which runs the UI
// isolate by default on macOS, Windows, and Linux. Requests from any other
// thread are refused.

#ifndef FLUTTER_SCENE_POINTER_LOCK_H_
#define FLUTTER_SCENE_POINTER_LOCK_H_

#include <stdint.h>

#if defined(_WIN32)
#define FS_POINTER_LOCK_EXPORT __declspec(dllexport)
#else
#define FS_POINTER_LOCK_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Loss codes passed to the loss callback.
#define FS_POINTER_LOCK_LOSS_FOCUS 1

typedef struct {
  double x;
  double y;
} FsPointerLockMovement;

// Nonzero when this platform and session can lock the cursor.
FS_POINTER_LOCK_EXPORT int32_t fs_pointer_lock_supported(void);

// Hides and holds the cursor in the focused window. Returns nonzero on success.
FS_POINTER_LOCK_EXPORT int32_t fs_pointer_lock_request(void);

// Releases the lock without invoking the loss callback. Safe when unlocked.
FS_POINTER_LOCK_EXPORT void fs_pointer_lock_release(void);

// Returns and clears the movement accumulated since the last call, in logical
// pixels.
FS_POINTER_LOCK_EXPORT FsPointerLockMovement fs_pointer_lock_take_movement(void);

// Called when the platform ends the lock on its own (focus loss).
FS_POINTER_LOCK_EXPORT void fs_pointer_lock_set_loss_callback(
    void (*callback)(int32_t reason));

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_SCENE_POINTER_LOCK_H_
