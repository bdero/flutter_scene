// IOHIDManager gamepad tap. Axes on the generic desktop page are scaled to
// -1..1 from their logical range with Y axes flipped up positive; the hat
// switch and discrete d-pad usages merge into two synthetic codes; buttons
// report 0 or 1. Ported from the dashsurfers runner, made per device.
// HID Usage Tables 1.4, https://usb.org/document-library/hid-usage-tables-14

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDLib.h>

#include "hid_gamepads.h"

#define kMaxDevices 256
#define kPageDesktop 0x01
#define kPageButton 0x09
#define kHatX ((kPageDesktop << 16) | 0xfff0)
#define kHatY ((kPageDesktop << 16) | 0xfff1)

typedef struct {
  IOHIDDeviceRef ref;
  FsHidDeviceInfo info;
  bool up, down, left, right;
} Device;

static IOHIDManagerRef gManager = NULL;
static FsHidDeviceCallback gOnDevice = NULL;
static FsHidValueCallback gOnValue = NULL;
static Device gDevices[kMaxDevices];
static int32_t gNextDevice = 0;

static int32_t FindDevice(IOHIDDeviceRef ref) {
  for (int32_t i = 0; i < gNextDevice; i++) {
    if (gDevices[i].ref == ref) return i;
  }
  return -1;
}

static int32_t IntProperty(IOHIDDeviceRef ref, CFStringRef key) {
  CFTypeRef value = IOHIDDeviceGetProperty(ref, key);
  int32_t result = 0;
  if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID()) {
    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &result);
  }
  return result;
}

static void DeviceMatched(void* context, IOReturn result, void* sender,
                          IOHIDDeviceRef ref) {
  if (FindDevice(ref) >= 0 || gNextDevice >= kMaxDevices) return;
  int32_t id = gNextDevice++;
  Device* device = &gDevices[id];
  memset(device, 0, sizeof(Device));
  device->ref = ref;
  device->info.vendor_id = IntProperty(ref, CFSTR(kIOHIDVendorIDKey));
  device->info.product_id = IntProperty(ref, CFSTR(kIOHIDProductIDKey));
  CFTypeRef name = IOHIDDeviceGetProperty(ref, CFSTR(kIOHIDProductKey));
  if (name != NULL && CFGetTypeID(name) == CFStringGetTypeID()) {
    CFStringGetCString((CFStringRef)name, (char*)device->info.name,
                       sizeof(device->info.name), kCFStringEncodingUTF8);
  }
  if (gOnDevice != NULL) gOnDevice(id, 1);
}

static void DeviceRemoved(void* context, IOReturn result, void* sender,
                          IOHIDDeviceRef ref) {
  int32_t id = FindDevice(ref);
  if (id < 0) return;
  // Keep the info for late readers; forget the ref so a new arrival at the
  // same address gets a new id.
  gDevices[id].ref = NULL;
  if (gOnDevice != NULL) gOnDevice(id, 0);
}

static void EmitDpad(int32_t id, Device* device) {
  double x = (device->right ? 1.0 : 0.0) - (device->left ? 1.0 : 0.0);
  double y = (device->up ? 1.0 : 0.0) - (device->down ? 1.0 : 0.0);
  gOnValue(id, kHatX, x);
  gOnValue(id, kHatY, y);
}

static void ValueChanged(void* context, IOReturn result, void* sender,
                         IOHIDValueRef value) {
  if (gOnValue == NULL) return;
  IOHIDElementRef element = IOHIDValueGetElement(value);
  int32_t id = FindDevice(IOHIDElementGetDevice(element));
  if (id < 0) return;
  Device* device = &gDevices[id];
  uint32_t page = IOHIDElementGetUsagePage(element);
  uint32_t usage = IOHIDElementGetUsage(element);
  CFIndex raw = IOHIDValueGetIntegerValue(value);

  if (page == kPageButton) {
    gOnValue(id, (int32_t)((kPageButton << 16) | usage), raw != 0 ? 1.0 : 0.0);
    return;
  }
  if (page != kPageDesktop) return;

  CFIndex min = IOHIDElementGetLogicalMin(element);
  CFIndex max = IOHIDElementGetLogicalMax(element);

  if (usage == 0x39) {  // Hat switch, eight directions clockwise from north.
    static const double kStates[8][2] = {{0, 1},  {1, 1},   {1, 0},  {1, -1},
                                         {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
    CFIndex index = raw - min;
    double x = 0, y = 0;
    if (index >= 0 && index < 8) {
      x = kStates[index][0];
      y = kStates[index][1];
    }
    device->right = x > 0;
    device->left = x < 0;
    device->up = y > 0;
    device->down = y < 0;
    EmitDpad(id, device);
    return;
  }
  if (usage >= 0x90 && usage <= 0x93) {  // Discrete d-pad usages.
    bool pressed = raw != 0;
    switch (usage) {
      case 0x90: device->up = pressed; break;
      case 0x91: device->down = pressed; break;
      case 0x92: device->right = pressed; break;
      default: device->left = pressed; break;
    }
    EmitDpad(id, device);
    return;
  }
  if (usage < 0x30 || usage > 0x35 || max <= min) return;
  double normalized = (double)(raw - min) / (double)(max - min) * 2.0 - 1.0;
  // HID reports down as positive on the Y axes.
  if (usage == 0x31 || usage == 0x34) normalized = -normalized;
  gOnValue(id, (int32_t)((kPageDesktop << 16) | usage), normalized);
}

int32_t fs_hid_gamepads_start(FsHidDeviceCallback on_device,
                              FsHidValueCallback on_value) {
  if (![NSThread isMainThread]) return 0;
  gOnDevice = on_device;
  gOnValue = on_value;
  if (gManager != NULL) return 1;

  IOHIDManagerRef manager =
      IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
  NSArray* matches = @[
    @{@kIOHIDDeviceUsagePageKey : @0x01, @kIOHIDDeviceUsageKey : @0x04},
    @{@kIOHIDDeviceUsagePageKey : @0x01, @kIOHIDDeviceUsageKey : @0x05},
    @{@kIOHIDDeviceUsagePageKey : @0x01, @kIOHIDDeviceUsageKey : @0x08},
  ];
  IOHIDManagerSetDeviceMatchingMultiple(manager,
                                        (__bridge CFArrayRef)matches);
  IOHIDManagerRegisterDeviceMatchingCallback(manager, DeviceMatched, NULL);
  IOHIDManagerRegisterDeviceRemovalCallback(manager, DeviceRemoved, NULL);
  IOHIDManagerRegisterInputValueCallback(manager, ValueChanged, NULL);
  IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(),
                                  kCFRunLoopDefaultMode);
  if (IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(),
                                      kCFRunLoopDefaultMode);
    CFRelease(manager);
    return 0;
  }
  gManager = manager;
  return 1;
}

void fs_hid_gamepads_stop(void) {
  if (gManager == NULL) return;
  IOHIDManagerUnscheduleFromRunLoop(gManager, CFRunLoopGetMain(),
                                    kCFRunLoopDefaultMode);
  IOHIDManagerClose(gManager, kIOHIDOptionsTypeNone);
  CFRelease(gManager);
  gManager = NULL;
  gOnDevice = NULL;
  gOnValue = NULL;
}

FsHidDeviceInfo fs_hid_gamepads_device_info(int32_t device) {
  FsHidDeviceInfo info;
  memset(&info, 0, sizeof(info));
  if (device >= 0 && device < gNextDevice) info = gDevices[device].info;
  return info;
}
