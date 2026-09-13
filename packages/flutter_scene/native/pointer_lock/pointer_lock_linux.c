// Linux backend (GDK on X11). The pointer is grabbed with a blank cursor,
// every motion event is measured from the lock point, accumulated, and warped
// back, so the hidden cursor reappears where it was locked. Motion is
// swallowed so Flutter sees none.
//
// GTK and GDK are already loaded by the Flutter runner, so their symbols are
// resolved from the process with dlsym; the library needs no GTK headers or
// link flags, and a process without GTK simply reports unsupported.
//
// TODO(pointer-lock): Wayland does not allow warping. Support it with
// zwp_pointer_constraints_v1 and zwp_relative_pointer_manager_v1 on the
// view's wl_surface.

#define _GNU_SOURCE
#include <dlfcn.h>
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

// Enum values from gdkevents.h and gdkcursor.h (GTK 3 ABI).
enum { kGdkMotionNotify = 3, kGdkGrabBroken = 35 };
enum { kGdkBlankCursor = -2 };
enum { kGdkSeatCapabilityAllPointing = 7 };

static struct {
  int resolved;
  void* (*gdk_display_get_default)(void);
  const char* (*g_type_name_from_instance)(void* instance);
  void* (*g_main_context_default)(void);
  int (*g_main_context_is_owner)(void* context);
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
  unsigned long (*g_signal_connect_data)(void* instance, const char* signal,
                                         void* handler, void* data,
                                         void* destroy, int flags);
  void (*g_signal_handler_disconnect)(void* instance, unsigned long id);
  void (*g_object_unref)(void* object);
} gtk;

static int gLocked = 0;
static void* gSeat = NULL;
static void* gPointer = NULL;
static void* gScreen = NULL;
static void* gToplevel = NULL;
static unsigned long gFocusHandler = 0;
static int gLockX = 0;
static int gLockY = 0;
static double gDx = 0.0;
static double gDy = 0.0;
static void (*gLossCallback)(int32_t) = NULL;

#define RESOLVE(name)                                   \
  gtk.name = (__typeof__(gtk.name))dlsym(RTLD_DEFAULT, #name); \
  if (gtk.name == NULL) return 0;

static int Resolve(void) {
  if (gtk.resolved != 0) return gtk.resolved > 0;
  gtk.resolved = -1;
  RESOLVE(gdk_display_get_default);
  RESOLVE(g_type_name_from_instance);
  RESOLVE(g_main_context_default);
  RESOLVE(g_main_context_is_owner);
  RESOLVE(gtk_window_list_toplevels);
  RESOLVE(g_list_free);
  RESOLVE(gtk_window_is_active);
  RESOLVE(gtk_widget_get_window);
  RESOLVE(gdk_display_get_default_seat);
  RESOLVE(gdk_seat_get_pointer);
  RESOLVE(gdk_device_get_position);
  RESOLVE(gdk_cursor_new_for_display);
  RESOLVE(gdk_seat_grab);
  RESOLVE(gdk_seat_ungrab);
  RESOLVE(gdk_event_handler_set);
  RESOLVE(gtk_main_do_event);
  RESOLVE(gdk_event_get_event_type);
  RESOLVE(gdk_event_get_root_coords);
  RESOLVE(gdk_device_warp);
  RESOLVE(g_signal_connect_data);
  RESOLVE(g_signal_handler_disconnect);
  RESOLVE(g_object_unref);
  gtk.resolved = 1;
  return 1;
}

static void EndLock(int notify);

static void HandleEvent(GdkEvent* event, void* data) {
  int type = gtk.gdk_event_get_event_type(event);
  if (gLocked && type == kGdkMotionNotify) {
    double x = 0.0;
    double y = 0.0;
    if (gtk.gdk_event_get_root_coords(event, &x, &y)) {
      double dx = x - gLockX;
      double dy = y - gLockY;
      if (dx != 0.0 || dy != 0.0) {
        gDx += dx;
        gDy += dy;
        gtk.gdk_device_warp(gPointer, gScreen, gLockX, gLockY);
      }
    }
    return;
  }
  if (gLocked && type == kGdkGrabBroken) {
    gtk.gtk_main_do_event(event);
    EndLock(1);
    return;
  }
  gtk.gtk_main_do_event(event);
}

static int HandleFocusOut(void* widget, GdkEvent* event, void* data) {
  EndLock(1);
  return 0;
}

static void EndLock(int notify) {
  if (!gLocked) return;
  gLocked = 0;
  gtk.gdk_event_handler_set((GdkEventFunc)gtk.gtk_main_do_event, NULL, NULL);
  gtk.gdk_seat_ungrab(gSeat);
  if (gFocusHandler != 0) {
    gtk.g_signal_handler_disconnect(gToplevel, gFocusHandler);
    gFocusHandler = 0;
  }
  gtk.gdk_device_warp(gPointer, gScreen, gLockX, gLockY);
  gToplevel = NULL;
  gDx = 0.0;
  gDy = 0.0;
  if (notify && gLossCallback != NULL) {
    gLossCallback(FS_POINTER_LOCK_LOSS_FOCUS);
  }
}

int32_t fs_pointer_lock_supported(void) {
  if (!Resolve()) return 0;
  void* display = gtk.gdk_display_get_default();
  if (display == NULL) return 0;
  const char* type = gtk.g_type_name_from_instance(display);
  return type != NULL && strcmp(type, "GdkX11Display") == 0;
}

int32_t fs_pointer_lock_request(void) {
  if (gLocked) return 1;
  if (!fs_pointer_lock_supported()) return 0;
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

  void* cursor = gtk.gdk_cursor_new_for_display(display, kGdkBlankCursor);
  int status = gtk.gdk_seat_grab(seat, window, kGdkSeatCapabilityAllPointing,
                                 1, cursor, NULL, NULL, NULL);
  if (cursor != NULL) gtk.g_object_unref(cursor);
  if (status != 0) return 0;

  gSeat = seat;
  gPointer = pointer;
  gToplevel = toplevel;
  gtk.gdk_device_get_position(pointer, &gScreen, &gLockX, &gLockY);
  gDx = 0.0;
  gDy = 0.0;
  gFocusHandler = gtk.g_signal_connect_data(toplevel, "focus-out-event",
                                            HandleFocusOut, NULL, NULL, 0);
  gtk.gdk_event_handler_set(HandleEvent, NULL, NULL);
  gLocked = 1;
  return 1;
}

void fs_pointer_lock_release(void) { EndLock(0); }

FsPointerLockMovement fs_pointer_lock_take_movement(void) {
  FsPointerLockMovement movement = {gDx, gDy};
  gDx = 0.0;
  gDy = 0.0;
  return movement;
}

void fs_pointer_lock_set_loss_callback(void (*callback)(int32_t reason)) {
  gLossCallback = callback;
}
