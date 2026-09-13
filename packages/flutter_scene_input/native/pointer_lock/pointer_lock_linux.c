// Linux backend for GDK on X11 and Wayland.
//
// GTK, GDK, GLib, and (under Wayland) libwayland-client are already loaded by
// the Flutter runner, so their symbols are resolved from the process with
// dlsym. The library needs no headers or link flags, and a process without
// them reports unsupported.
//
// Both backends grab the seat with a blank cursor, which hides it and keeps
// button events flowing to the app.
//
// X11. Every motion event is measured from the lock point, accumulated, and
// the pointer is warped back, so it reappears where it was locked. Motion is
// swallowed so Flutter sees none. Under XWayland the hidden-cursor warp is
// what makes XWayland lock the host pointer itself.
//
// Wayland does not allow warping. The pointer is locked with
// zwp_pointer_constraints_v1 and movement comes from
// zwp_relative_pointer_manager_v1, both bound on a private event queue so
// dispatching them never runs GTK's handlers.
// https://wayland.app/protocols/pointer-constraints-unstable-v1
// https://wayland.app/protocols/relative-pointer-unstable-v1

#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

#include "pointer_lock.h"

typedef struct _GList {
  void* data;
  struct _GList* next;
  struct _GList* prev;
} GList;

typedef void GdkEvent;
typedef void (*GdkEventFunc)(GdkEvent* event, void* data);
typedef int (*GSourceFunc)(void* data);

// Enum values from gdkevents.h and gdkcursor.h (GTK 3 ABI).
enum { kGdkMotionNotify = 3, kGdkGrabBroken = 35 };
enum { kGdkBlankCursor = -2 };
enum { kGdkSeatCapabilityAllPointing = 7 };

// No hand movement travels this far between two motion events. An event this
// far from the lock point is either a synthetic jump or an absolute device
// (a VM tablet, a remote desktop) that ignores warps.
static const double kUnwarpedJump = 300.0;

static struct {
  int resolved;
  void* (*gdk_display_get_default)(void);
  const char* (*g_type_name_from_instance)(void* instance);
  void* (*g_main_context_default)(void);
  int (*g_main_context_is_owner)(void* context);
  unsigned (*g_timeout_add)(unsigned interval, GSourceFunc func, void* data);
  int (*g_source_remove)(unsigned id);
  GList* (*gtk_window_list_toplevels)(void);
  void (*g_list_free)(GList* list);
  int (*gtk_window_is_active)(void* window);
  void* (*gtk_widget_get_window)(void* widget);
  void* (*gdk_display_get_default_seat)(void* display);
  void* (*gdk_seat_get_pointer)(void* seat);
  void (*gdk_device_get_position)(void* device, void** screen, int* x, int* y);
  void* (*gdk_cursor_new_for_display)(void* display, int type);
  int (*gdk_seat_grab)(void* seat, void* window, int capabilities,
                       int owner_events, void* cursor, GdkEvent* event,
                       void* prepare_func, void* prepare_data);
  void (*gdk_seat_ungrab)(void* seat);
  void (*gdk_event_handler_set)(GdkEventFunc func, void* data, void* notify);
  void (*gtk_main_do_event)(GdkEvent* event);
  int (*gdk_event_get_event_type)(const GdkEvent* event);
  int (*gdk_event_get_root_coords)(const GdkEvent* event, double* x, double* y);
  void (*gdk_device_warp)(void* device, void* screen, int x, int y);
  void (*gdk_window_get_origin)(void* window, int* x, int* y);
  int (*gdk_window_get_width)(void* window);
  int (*gdk_window_get_height)(void* window);
  unsigned long (*g_signal_connect_data)(void* instance, const char* signal,
                                         void* handler, void* data,
                                         void* destroy, int flags);
  void (*g_signal_handler_disconnect)(void* instance, unsigned long id);
  void (*g_object_unref)(void* object);
} gtk;

#define RESOLVE(table, name)                                      \
  table.name = (__typeof__(table.name))dlsym(RTLD_DEFAULT, #name); \
  if (table.name == NULL) return 0;

static int ResolveGtk(void) {
  if (gtk.resolved != 0) return gtk.resolved > 0;
  gtk.resolved = -1;
  RESOLVE(gtk, gdk_display_get_default);
  RESOLVE(gtk, g_type_name_from_instance);
  RESOLVE(gtk, g_main_context_default);
  RESOLVE(gtk, g_main_context_is_owner);
  RESOLVE(gtk, g_timeout_add);
  RESOLVE(gtk, g_source_remove);
  RESOLVE(gtk, gtk_window_list_toplevels);
  RESOLVE(gtk, g_list_free);
  RESOLVE(gtk, gtk_window_is_active);
  RESOLVE(gtk, gtk_widget_get_window);
  RESOLVE(gtk, gdk_display_get_default_seat);
  RESOLVE(gtk, gdk_seat_get_pointer);
  RESOLVE(gtk, gdk_device_get_position);
  RESOLVE(gtk, gdk_cursor_new_for_display);
  RESOLVE(gtk, gdk_seat_grab);
  RESOLVE(gtk, gdk_seat_ungrab);
  RESOLVE(gtk, gdk_event_handler_set);
  RESOLVE(gtk, gtk_main_do_event);
  RESOLVE(gtk, gdk_event_get_event_type);
  RESOLVE(gtk, gdk_event_get_root_coords);
  RESOLVE(gtk, gdk_device_warp);
  RESOLVE(gtk, gdk_window_get_origin);
  RESOLVE(gtk, gdk_window_get_width);
  RESOLVE(gtk, gdk_window_get_height);
  RESOLVE(gtk, g_signal_connect_data);
  RESOLVE(gtk, g_signal_handler_disconnect);
  RESOLVE(gtk, g_object_unref);
  gtk.resolved = 1;
  return 1;
}

// libwayland-client ABI (wayland-util.h, wayland-client-core.h).

struct wl_interface;

struct wl_message {
  const char* name;
  const char* signature;
  const struct wl_interface** types;
};

struct wl_interface {
  const char* name;
  int version;
  int method_count;
  const struct wl_message* methods;
  int event_count;
  const struct wl_message* events;
};

typedef void wl_proxy;
typedef int32_t wl_fixed_t;

#define WL_MARSHAL_FLAG_DESTROY (1 << 0)

static struct {
  int resolved;
  void* (*gdk_wayland_display_get_wl_display)(void* display);
  void* (*gdk_wayland_window_get_wl_surface)(void* window);
  void* (*gdk_wayland_device_get_wl_pointer)(void* device);
  void* (*wl_display_create_queue)(void* display);
  void* (*wl_proxy_create_wrapper)(void* proxy);
  void (*wl_proxy_wrapper_destroy)(void* proxy_wrapper);
  void (*wl_proxy_set_queue)(wl_proxy* proxy, void* queue);
  wl_proxy* (*wl_proxy_marshal_flags)(wl_proxy* proxy, uint32_t opcode,
                                      const struct wl_interface* interface,
                                      uint32_t version, uint32_t flags, ...);
  int (*wl_proxy_add_listener)(wl_proxy* proxy, void (**implementation)(void),
                               void* data);
  uint32_t (*wl_proxy_get_version)(wl_proxy* proxy);
  int (*wl_display_roundtrip_queue)(void* display, void* queue);
  int (*wl_display_dispatch_queue_pending)(void* display, void* queue);
  const struct wl_interface* wl_registry_interface;
  const struct wl_interface* wl_surface_interface;
  const struct wl_interface* wl_pointer_interface;
  const struct wl_interface* wl_region_interface;
} wl;

static int ResolveWayland(void) {
  if (wl.resolved != 0) return wl.resolved > 0;
  wl.resolved = -1;
  RESOLVE(wl, gdk_wayland_display_get_wl_display);
  RESOLVE(wl, gdk_wayland_window_get_wl_surface);
  RESOLVE(wl, gdk_wayland_device_get_wl_pointer);
  RESOLVE(wl, wl_display_create_queue);
  RESOLVE(wl, wl_proxy_create_wrapper);
  RESOLVE(wl, wl_proxy_wrapper_destroy);
  RESOLVE(wl, wl_proxy_set_queue);
  RESOLVE(wl, wl_proxy_marshal_flags);
  RESOLVE(wl, wl_proxy_add_listener);
  RESOLVE(wl, wl_proxy_get_version);
  RESOLVE(wl, wl_display_roundtrip_queue);
  RESOLVE(wl, wl_display_dispatch_queue_pending);
  RESOLVE(wl, wl_registry_interface);
  RESOLVE(wl, wl_surface_interface);
  RESOLVE(wl, wl_pointer_interface);
  RESOLVE(wl, wl_region_interface);
  wl.resolved = 1;
  return 1;
}

// Protocol tables, transcribed from pointer-constraints-unstable-v1.xml and
// relative-pointer-unstable-v1.xml. The core interface pointers are only
// known at runtime, so the type arrays are filled in by InitProtocols.

static const struct wl_message kDestroyOnly[] = {{"destroy", "", NULL}};

static const struct wl_interface zwp_confined_pointer_v1 = {
    "zwp_confined_pointer_v1", 1, 1, kDestroyOnly, 0, NULL};

static const struct wl_message kLockedPointerEvents[] = {
    {"locked", "", NULL},
    {"unlocked", "", NULL},
};
static const struct wl_interface* kSetRegionTypes[1];
static struct wl_message kLockedPointerRequests[] = {
    {"destroy", "", NULL},
    {"set_cursor_position_hint", "ff", NULL},
    {"set_region", "?o", kSetRegionTypes},
};
static const struct wl_interface zwp_locked_pointer_v1 = {
    "zwp_locked_pointer_v1", 1, 3, kLockedPointerRequests,
    2, kLockedPointerEvents};

static const struct wl_interface* kLockTypes[5];
static const struct wl_interface* kConfineTypes[5];
static const struct wl_message kConstraintsRequests[] = {
    {"destroy", "", NULL},
    {"lock_pointer", "noo?ou", kLockTypes},
    {"confine_pointer", "noo?ou", kConfineTypes},
};
static const struct wl_interface zwp_pointer_constraints_v1 = {
    "zwp_pointer_constraints_v1", 1, 3, kConstraintsRequests, 0, NULL};

static const struct wl_message kRelativePointerEvents[] = {
    {"relative_motion", "uuffff", NULL},
};
static const struct wl_interface zwp_relative_pointer_v1 = {
    "zwp_relative_pointer_v1", 1, 1, kDestroyOnly, 1, kRelativePointerEvents};

static const struct wl_interface* kGetRelativeTypes[2];
static const struct wl_message kRelativeManagerRequests[] = {
    {"destroy", "", NULL},
    {"get_relative_pointer", "no", kGetRelativeTypes},
};
static const struct wl_interface zwp_relative_pointer_manager_v1 = {
    "zwp_relative_pointer_manager_v1", 1, 2, kRelativeManagerRequests, 0,
    NULL};

enum { kLifetimeOneshot = 1 };
enum { kRegistryBind = 0, kDisplayGetRegistry = 1 };
enum { kLockPointer = 1, kGetRelativePointer = 1, kDestroy = 0 };

static void InitProtocols(void) {
  kSetRegionTypes[0] = wl.wl_region_interface;
  kLockTypes[0] = &zwp_locked_pointer_v1;
  kLockTypes[1] = wl.wl_surface_interface;
  kLockTypes[2] = wl.wl_pointer_interface;
  kLockTypes[3] = wl.wl_region_interface;
  kLockTypes[4] = NULL;
  kConfineTypes[0] = &zwp_confined_pointer_v1;
  kConfineTypes[1] = wl.wl_surface_interface;
  kConfineTypes[2] = wl.wl_pointer_interface;
  kConfineTypes[3] = wl.wl_region_interface;
  kConfineTypes[4] = NULL;
  kGetRelativeTypes[0] = &zwp_relative_pointer_v1;
  kGetRelativeTypes[1] = wl.wl_pointer_interface;
}

typedef enum { kBackendNone, kBackendX11, kBackendWayland } Backend;

static int gLocked = 0;
static void* gSeat = NULL;
static void* gPointer = NULL;
static void* gScreen = NULL;
static void* gToplevel = NULL;
static unsigned long gFocusHandler = 0;
static int gLockX = 0;
static int gLockY = 0;
static int gWarpUnreliable = 0;
static double gLastX = 0.0;
static double gLastY = 0.0;
static double gDx = 0.0;
static double gDy = 0.0;
static void (*gLossCallback)(int32_t) = NULL;

static void* gWlDisplay = NULL;
static void* gWlQueue = NULL;
static wl_proxy* gConstraints = NULL;
static wl_proxy* gRelativeManager = NULL;
static wl_proxy* gLockedPointer = NULL;
static wl_proxy* gRelativePointer = NULL;
static int gWlLockActive = 0;
static int gWlLockEnded = 0;
static unsigned gWlPollSource = 0;

static Backend CurrentBackend(void) {
  if (!ResolveGtk()) return kBackendNone;
  void* display = gtk.gdk_display_get_default();
  if (display == NULL) return kBackendNone;
  const char* type = gtk.g_type_name_from_instance(display);
  if (type == NULL) return kBackendNone;
  if (strcmp(type, "GdkX11Display") == 0) return kBackendX11;
  if (strcmp(type, "GdkWaylandDisplay") == 0) return kBackendWayland;
  return kBackendNone;
}

static void EndLock(int notify);

// --- Wayland ---

static void RegistryGlobal(void* data, wl_proxy* registry, uint32_t name,
                           const char* interface, uint32_t version) {
  const struct wl_interface* wanted = NULL;
  wl_proxy** slot = NULL;
  if (strcmp(interface, zwp_pointer_constraints_v1.name) == 0) {
    wanted = &zwp_pointer_constraints_v1;
    slot = &gConstraints;
  } else if (strcmp(interface, zwp_relative_pointer_manager_v1.name) == 0) {
    wanted = &zwp_relative_pointer_manager_v1;
    slot = &gRelativeManager;
  }
  if (wanted == NULL || *slot != NULL) return;
  *slot = wl.wl_proxy_marshal_flags(registry, kRegistryBind, wanted, 1, 0,
                                    name, wanted->name, 1, NULL);
}

static void RegistryGlobalRemove(void* data, wl_proxy* registry,
                                 uint32_t name) {}

static void (*kRegistryListener[])(void) = {
    (void (*)(void))RegistryGlobal,
    (void (*)(void))RegistryGlobalRemove,
};

// Binds the two protocol globals once. Returns whether both exist.
static int BindWaylandGlobals(void) {
  static int bound = 0;
  if (bound != 0) return bound > 0;
  bound = -1;
  if (!ResolveWayland()) return 0;
  InitProtocols();
  gWlDisplay = wl.gdk_wayland_display_get_wl_display(
      gtk.gdk_display_get_default());
  if (gWlDisplay == NULL) return 0;
  gWlQueue = wl.wl_display_create_queue(gWlDisplay);
  if (gWlQueue == NULL) return 0;
  wl_proxy* wrapper = wl.wl_proxy_create_wrapper(gWlDisplay);
  if (wrapper == NULL) return 0;
  wl.wl_proxy_set_queue(wrapper, gWlQueue);
  wl_proxy* registry = wl.wl_proxy_marshal_flags(
      wrapper, kDisplayGetRegistry, wl.wl_registry_interface,
      wl.wl_proxy_get_version(wrapper), 0, NULL);
  // The wrapper only exists to create the registry on the private queue.
  wl.wl_proxy_wrapper_destroy(wrapper);
  if (registry == NULL) return 0;
  wl.wl_proxy_add_listener(registry, kRegistryListener, NULL);
  wl.wl_display_roundtrip_queue(gWlDisplay, gWlQueue);
  if (gConstraints == NULL || gRelativeManager == NULL) return 0;
  bound = 1;
  return 1;
}

static void LockedPointerLocked(void* data, wl_proxy* locked) {
  gWlLockActive = 1;
}

static void LockedPointerUnlocked(void* data, wl_proxy* locked) {
  // A oneshot lock is spent once it deactivates; the object is inert.
  gWlLockEnded = 1;
}

static void (*kLockedPointerListener[])(void) = {
    (void (*)(void))LockedPointerLocked,
    (void (*)(void))LockedPointerUnlocked,
};

static void RelativeMotion(void* data, wl_proxy* relative, uint32_t utime_hi,
                           uint32_t utime_lo, wl_fixed_t dx, wl_fixed_t dy,
                           wl_fixed_t dx_unaccel, wl_fixed_t dy_unaccel) {
  if (!gLocked || !gWlLockActive) return;
  gDx += dx / 256.0;
  gDy += dy / 256.0;
}

static void (*kRelativePointerListener[])(void) = {
    (void (*)(void))RelativeMotion,
};

static void DispatchWayland(void) {
  if (gWlDisplay == NULL || gWlQueue == NULL) return;
  wl.wl_display_dispatch_queue_pending(gWlDisplay, gWlQueue);
  if (gLocked && gWlLockEnded) EndLock(1);
}

// Keeps lock loss prompt when nothing is reading movement.
static int PollWayland(void* data) {
  DispatchWayland();
  return gLocked;
}

static void DestroyProxy(wl_proxy** proxy) {
  if (*proxy == NULL) return;
  wl.wl_proxy_marshal_flags(*proxy, kDestroy, NULL,
                            wl.wl_proxy_get_version(*proxy),
                            WL_MARSHAL_FLAG_DESTROY);
  *proxy = NULL;
}

static int LockWayland(void* window) {
  if (!BindWaylandGlobals()) return 0;
  void* surface = wl.gdk_wayland_window_get_wl_surface(window);
  void* pointer = wl.gdk_wayland_device_get_wl_pointer(gPointer);
  if (surface == NULL || pointer == NULL) return 0;

  gWlLockActive = 0;
  gWlLockEnded = 0;
  gLockedPointer = wl.wl_proxy_marshal_flags(
      gConstraints, kLockPointer, &zwp_locked_pointer_v1, 1, 0, NULL, surface,
      pointer, NULL, (uint32_t)kLifetimeOneshot);
  gRelativePointer = wl.wl_proxy_marshal_flags(
      gRelativeManager, kGetRelativePointer, &zwp_relative_pointer_v1, 1, 0,
      NULL, pointer);
  if (gLockedPointer == NULL || gRelativePointer == NULL) {
    DestroyProxy(&gLockedPointer);
    DestroyProxy(&gRelativePointer);
    return 0;
  }
  wl.wl_proxy_add_listener(gLockedPointer, kLockedPointerListener, NULL);
  wl.wl_proxy_add_listener(gRelativePointer, kRelativePointerListener, NULL);

  // The compositor activates the lock only while the pointer is over the
  // surface, and says so before answering the roundtrip.
  wl.wl_display_roundtrip_queue(gWlDisplay, gWlQueue);
  if (!gWlLockActive || gWlLockEnded) {
    DestroyProxy(&gLockedPointer);
    DestroyProxy(&gRelativePointer);
    return 0;
  }
  gWlPollSource = gtk.g_timeout_add(100, PollWayland, NULL);
  return 1;
}

static void UnlockWayland(void) {
  if (gWlPollSource != 0) {
    gtk.g_source_remove(gWlPollSource);
    gWlPollSource = 0;
  }
  DestroyProxy(&gLockedPointer);
  DestroyProxy(&gRelativePointer);
  gWlLockActive = 0;
  gWlLockEnded = 0;
}

// --- X11 ---

static void HandleX11Event(GdkEvent* event, void* data) {
  int type = gtk.gdk_event_get_event_type(event);
  if (gLocked && type == kGdkMotionNotify) {
    double x = 0.0;
    double y = 0.0;
    if (!gtk.gdk_event_get_root_coords(event, &x, &y)) return;
    double sinceLastX = x - gLastX;
    double sinceLastY = y - gLastY;
    gLastX = x;
    gLastY = y;
    if (gWarpUnreliable) {
      // Measure from the previous event instead, without warping.
      gDx += sinceLastX;
      gDy += sinceLastY;
      return;
    }
    double dx = x - gLockX;
    double dy = y - gLockY;
    if (fabs(dx) > kUnwarpedJump || fabs(dy) > kUnwarpedJump) {
      // Two consecutive far events close to each other mean the last warp did
      // not move the pointer. Either way this event is not a hand movement.
      if (fabs(sinceLastX) < kUnwarpedJump && fabs(sinceLastY) < kUnwarpedJump) {
        gWarpUnreliable = 1;
      }
      return;
    }
    if (dx == 0.0 && dy == 0.0) return;
    gDx += dx;
    gDy += dy;
    gtk.gdk_device_warp(gPointer, gScreen, gLockX, gLockY);
    gLastX = gLockX;
    gLastY = gLockY;
    return;
  }
  gtk.gtk_main_do_event(event);
  if (gLocked && type == kGdkGrabBroken) EndLock(1);
}

static int LockX11(void* window) {
  gtk.gdk_device_get_position(gPointer, &gScreen, &gLockX, &gLockY);
  // A lock taken from the keyboard can find the pointer outside the window;
  // hold it at the window's center instead.
  int originX = 0;
  int originY = 0;
  gtk.gdk_window_get_origin(window, &originX, &originY);
  int width = gtk.gdk_window_get_width(window);
  int height = gtk.gdk_window_get_height(window);
  if (gLockX < originX || gLockY < originY || gLockX >= originX + width ||
      gLockY >= originY + height) {
    gLockX = originX + width / 2;
    gLockY = originY + height / 2;
    gtk.gdk_device_warp(gPointer, gScreen, gLockX, gLockY);
  }
  gLastX = gLockX;
  gLastY = gLockY;
  gWarpUnreliable = 0;
  // TODO(pointer-lock): this replaces GTK's event handler outright, so a
  // plugin that installed its own loses it after unlock. GTK 3 has no getter
  // to chain to it.
  gtk.gdk_event_handler_set(HandleX11Event, NULL, NULL);
  return 1;
}

static void UnlockX11(void) {
  // GTK installs gtk_main_do_event the same way, ignoring the data argument.
  gtk.gdk_event_handler_set((GdkEventFunc)(void (*)(void))gtk.gtk_main_do_event,
                            NULL, NULL);
  if (!gWarpUnreliable) {
    gtk.gdk_device_warp(gPointer, gScreen, gLockX, gLockY);
  }
}

// --- Shared ---

static Backend gLockBackend = kBackendNone;

static int HandleFocusOut(void* widget, GdkEvent* event, void* data) {
  EndLock(1);
  return 0;
}

static void EndLock(int notify) {
  if (!gLocked) return;
  gLocked = 0;
  if (gLockBackend == kBackendX11) UnlockX11();
  if (gLockBackend == kBackendWayland) UnlockWayland();
  gtk.gdk_seat_ungrab(gSeat);
  if (gFocusHandler != 0) {
    gtk.g_signal_handler_disconnect(gToplevel, gFocusHandler);
    gFocusHandler = 0;
  }
  gToplevel = NULL;
  gLockBackend = kBackendNone;
  gDx = 0.0;
  gDy = 0.0;
  if (notify && gLossCallback != NULL) {
    gLossCallback(FS_POINTER_LOCK_LOSS_FOCUS);
  }
}

int32_t fs_pointer_lock_supported(void) {
  switch (CurrentBackend()) {
    case kBackendX11:
      return 1;
    case kBackendWayland:
      return BindWaylandGlobals();
    default:
      return 0;
  }
}

int32_t fs_pointer_lock_request(void) {
  if (gLocked) return 1;
  Backend backend = CurrentBackend();
  if (backend == kBackendNone) return 0;
  if (!gtk.g_main_context_is_owner(gtk.g_main_context_default())) return 0;

  void* toplevel = NULL;
  GList* toplevels = gtk.gtk_window_list_toplevels();
  for (GList* item = toplevels; item != NULL; item = item->next) {
    if (gtk.gtk_window_is_active(item->data)) {
      toplevel = item->data;
      break;
    }
  }
  gtk.g_list_free(toplevels);
  if (toplevel == NULL) return 0;
  void* window = gtk.gtk_widget_get_window(toplevel);
  if (window == NULL) return 0;

  void* display = gtk.gdk_display_get_default();
  void* seat = gtk.gdk_display_get_default_seat(display);
  void* pointer = gtk.gdk_seat_get_pointer(seat);
  if (pointer == NULL) return 0;
  gSeat = seat;
  gPointer = pointer;

  void* cursor = gtk.gdk_cursor_new_for_display(display, kGdkBlankCursor);
  int status = gtk.gdk_seat_grab(seat, window, kGdkSeatCapabilityAllPointing,
                                 1, cursor, NULL, NULL, NULL);
  if (cursor != NULL) gtk.g_object_unref(cursor);
  if (status != 0) return 0;

  int locked = backend == kBackendX11 ? LockX11(window) : LockWayland(window);
  if (!locked) {
    gtk.gdk_seat_ungrab(seat);
    return 0;
  }

  gToplevel = toplevel;
  gLockBackend = backend;
  gDx = 0.0;
  gDy = 0.0;
  gFocusHandler = gtk.g_signal_connect_data(toplevel, "focus-out-event",
                                            HandleFocusOut, NULL, NULL, 0);
  gLocked = 1;
  return 1;
}

void fs_pointer_lock_release(void) { EndLock(0); }

FsPointerLockMovement fs_pointer_lock_take_movement(void) {
  if (gLockBackend == kBackendWayland) DispatchWayland();
  FsPointerLockMovement movement = {gDx, gDy};
  gDx = 0.0;
  gDy = 0.0;
  return movement;
}

void fs_pointer_lock_set_loss_callback(void (*callback)(int32_t reason)) {
  gLossCallback = callback;
}
