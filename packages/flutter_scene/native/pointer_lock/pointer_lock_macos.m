// macOS backend. The cursor is dissociated from the mouse (frozen in place,
// so it reappears where it was locked) and hidden, and a local event monitor
// accumulates each move's delta and swallows the event so Flutter sees no
// motion.

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include "pointer_lock.h"

// Re-associating the cursor or a warp can surface as one huge synthetic delta
// on the next real event; no hand movement produces this much in one event.
static const CGFloat kSyntheticJumpPoints = 300.0;

static BOOL gLocked = NO;
static double gDx = 0.0;
static double gDy = 0.0;
static id gMonitor = nil;
static id gResignObserver = nil;
static id gDeactivateObserver = nil;
static void (*gLossCallback)(int32_t) = NULL;

static void EndLock(BOOL notify) {
  if (!gLocked) return;
  gLocked = NO;
  if (gMonitor != nil) {
    [NSEvent removeMonitor:gMonitor];
    gMonitor = nil;
  }
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  if (gResignObserver != nil) {
    [center removeObserver:gResignObserver];
    gResignObserver = nil;
  }
  if (gDeactivateObserver != nil) {
    [center removeObserver:gDeactivateObserver];
    gDeactivateObserver = nil;
  }
  CGAssociateMouseAndMouseCursorPosition(true);
  [NSCursor unhide];
  gDx = 0.0;
  gDy = 0.0;
  if (notify && gLossCallback != NULL) {
    gLossCallback(FS_POINTER_LOCK_LOSS_FOCUS);
  }
}

int32_t fs_pointer_lock_supported(void) { return 1; }

int32_t fs_pointer_lock_request(void) {
  if (![NSThread isMainThread]) return 0;
  if (gLocked) return 1;
  NSWindow* window = [NSApp keyWindow];
  if (window == nil || ![NSApp isActive]) return 0;

  gDx = 0.0;
  gDy = 0.0;
  NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
                     NSEventMaskRightMouseDragged |
                     NSEventMaskOtherMouseDragged;
  gMonitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:mask
                                   handler:^NSEvent*(NSEvent* event) {
                                     if (!gLocked) return event;
                                     CGFloat dx = event.deltaX;
                                     CGFloat dy = event.deltaY;
                                     if (fabs(dx) < kSyntheticJumpPoints &&
                                         fabs(dy) < kSyntheticJumpPoints) {
                                       gDx += dx;
                                       gDy += dy;
                                     }
                                     return nil;
                                   }];

  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  gResignObserver =
      [center addObserverForName:NSWindowDidResignKeyNotification
                          object:window
                           queue:nil
                      usingBlock:^(NSNotification* note) {
                        EndLock(YES);
                      }];
  gDeactivateObserver =
      [center addObserverForName:NSApplicationDidResignActiveNotification
                          object:nil
                           queue:nil
                      usingBlock:^(NSNotification* note) {
                        EndLock(YES);
                      }];

  CGAssociateMouseAndMouseCursorPosition(false);
  [NSCursor hide];
  gLocked = YES;
  return 1;
}

void fs_pointer_lock_release(void) {
  if (![NSThread isMainThread]) return;
  EndLock(NO);
}

FsPointerLockMovement fs_pointer_lock_take_movement(void) {
  FsPointerLockMovement movement = {gDx, gDy};
  gDx = 0.0;
  gDy = 0.0;
  return movement;
}

void fs_pointer_lock_set_loss_callback(void (*callback)(int32_t reason)) {
  gLossCallback = callback;
}
