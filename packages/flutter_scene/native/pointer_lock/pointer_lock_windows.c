// Windows backend. The focused Flutter view is subclassed; each mouse move is
// measured from the lock point, accumulated, and warped back, so the hidden
// cursor never leaves the lock point and reappears there on release. Moves
// are swallowed so Flutter sees no motion.
//
// TODO(pointer-lock): offer raw unaccelerated movement (RegisterRawInputDevices)
// as an opt-in; warping reports accelerated pixels, matching PointerEvent.delta.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>

#include "pointer_lock.h"

static const UINT_PTR kSubclassId = 0x46535054;  // "FSPT"

static BOOL gLocked = FALSE;
static HWND gView = NULL;
static POINT gLockPoint = {0, 0};
static double gDx = 0.0;
static double gDy = 0.0;
static void (*gLossCallback)(int32_t) = NULL;

static void EndLock(BOOL notify);

static double DipScale(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  return dpi == 0 ? 1.0 : (double)dpi / 96.0;
}

static void ClipToView(HWND hwnd) {
  RECT client;
  if (!GetClientRect(hwnd, &client)) return;
  POINT topLeft = {client.left, client.top};
  POINT bottomRight = {client.right, client.bottom};
  ClientToScreen(hwnd, &topLeft);
  ClientToScreen(hwnd, &bottomRight);
  RECT clip = {topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
  ClipCursor(&clip);
}

static LRESULT CALLBACK ViewProc(HWND hwnd, UINT message, WPARAM wparam,
                                 LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  switch (message) {
    case WM_MOUSEMOVE: {
      POINT point = {(short)LOWORD(lparam), (short)HIWORD(lparam)};
      ClientToScreen(hwnd, &point);
      if (point.x != gLockPoint.x || point.y != gLockPoint.y) {
        double scale = DipScale(hwnd);
        gDx += (point.x - gLockPoint.x) / scale;
        gDy += (point.y - gLockPoint.y) / scale;
        SetCursorPos(gLockPoint.x, gLockPoint.y);
      }
      return 0;
    }
    case WM_SETCURSOR:
      if (LOWORD(lparam) == HTCLIENT) {
        SetCursor(NULL);
        return TRUE;
      }
      break;
    case WM_SIZE:
    case WM_MOVE:
      ClipToView(hwnd);
      break;
    case WM_KILLFOCUS:
      EndLock(TRUE);
      break;
    case WM_NCDESTROY:
      EndLock(TRUE);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

static void EndLock(BOOL notify) {
  if (!gLocked) return;
  gLocked = FALSE;
  HWND view = gView;
  gView = NULL;
  ClipCursor(NULL);
  RemoveWindowSubclass(view, ViewProc, kSubclassId);
  SetCursorPos(gLockPoint.x, gLockPoint.y);
  gDx = 0.0;
  gDy = 0.0;
  // Let Flutter reapply its own cursor.
  SendMessageW(view, WM_SETCURSOR, (WPARAM)view,
               MAKELPARAM(HTCLIENT, WM_MOUSEMOVE));
  if (notify && gLossCallback != NULL) {
    gLossCallback(FS_POINTER_LOCK_LOSS_FOCUS);
  }
}

int32_t fs_pointer_lock_supported(void) { return 1; }

int32_t fs_pointer_lock_request(void) {
  if (gLocked) return 1;
  // GetFocus only reports windows owned by the calling thread, so this also
  // refuses calls off the platform thread.
  HWND view = GetFocus();
  if (view == NULL) return 0;
  if (GetAncestor(view, GA_ROOT) != GetForegroundWindow()) return 0;

  POINT cursor;
  if (!GetCursorPos(&cursor)) return 0;
  RECT client;
  GetClientRect(view, &client);
  POINT local = cursor;
  ScreenToClient(view, &local);
  if (!PtInRect(&client, local)) {
    // Hold the cursor at the view's center when it is outside the view.
    POINT center = {(client.left + client.right) / 2,
                    (client.top + client.bottom) / 2};
    ClientToScreen(view, &center);
    cursor = center;
  }

  if (!SetWindowSubclass(view, ViewProc, kSubclassId, 0)) return 0;
  gView = view;
  gLockPoint = cursor;
  gDx = 0.0;
  gDy = 0.0;
  gLocked = TRUE;
  ClipToView(view);
  SetCursorPos(gLockPoint.x, gLockPoint.y);
  SetCursor(NULL);
  return 1;
}

void fs_pointer_lock_release(void) { EndLock(FALSE); }

FsPointerLockMovement fs_pointer_lock_take_movement(void) {
  FsPointerLockMovement movement = {gDx, gDy};
  gDx = 0.0;
  gDy = 0.0;
  return movement;
}

void fs_pointer_lock_set_loss_callback(void (*callback)(int32_t reason)) {
  gLossCallback = callback;
}
