// HID gamepad tap for flutter_scene_input's GamepadSource on macOS, bound
// through dart:ffi by lib/src/sources/hid_backend_native.dart.
//
// Apple's GameController framework only enumerates known controller families,
// so Steam Input's virtual pad and generic XInput adapters never reach it.
// IOHIDManager sees every device declaring itself a joystick, gamepad, or
// multi-axis controller. All calls happen on the platform thread, and
// callbacks fire on the main run loop.

#ifndef FLUTTER_SCENE_HID_GAMEPADS_H_
#define FLUTTER_SCENE_HID_GAMEPADS_H_

#include <stdint.h>

#define FS_HID_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int32_t vendor_id;
  int32_t product_id;
  uint8_t name[128];
} FsHidDeviceInfo;

// connected is 1 on arrival and 0 on removal.
typedef void (*FsHidDeviceCallback)(int32_t device, int32_t connected);

// code is usagePage << 16 | usage, or one of the synthetic hat codes.
typedef void (*FsHidValueCallback)(int32_t device, int32_t code, double value);

// Starts the tap. Returns nonzero on success.
FS_HID_EXPORT int32_t fs_hid_gamepads_start(FsHidDeviceCallback on_device,
                                            FsHidValueCallback on_value);

FS_HID_EXPORT void fs_hid_gamepads_stop(void);

// Info for a device id reported to the device callback. Stays valid after
// removal.
FS_HID_EXPORT FsHidDeviceInfo fs_hid_gamepads_device_info(int32_t device);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_SCENE_HID_GAMEPADS_H_
