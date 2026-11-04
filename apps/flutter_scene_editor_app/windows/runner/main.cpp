#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "resource.h"
#include "utils.h"

namespace {

HWINEVENTHOOK host_window_hook = nullptr;

// Gives the windowing API's window class the app icon at both sizes. The
// engine registers it with only a large icon, and the small one Windows
// derives (the title bar's) comes out as a warning glyph.
// TODO(windowing): drop once the engine sets hIconSm for host windows.
void CALLBACK OnWindowCreated(HWINEVENTHOOK hook, DWORD event, HWND window,
                              LONG object, LONG child, DWORD thread,
                              DWORD time) {
  if (object != OBJID_WINDOW || window == nullptr) {
    return;
  }
  wchar_t class_name[64];
  if (!::GetClassName(window, class_name, 64) ||
      wcscmp(class_name, L"FLUTTER_HOST_WINDOW") != 0) {
    return;
  }
  HINSTANCE instance = ::GetModuleHandle(nullptr);
  auto load = [instance](int metric_x, int metric_y) {
    return reinterpret_cast<LONG_PTR>(::LoadImage(
        instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
        ::GetSystemMetrics(metric_x), ::GetSystemMetrics(metric_y),
        LR_SHARED));
  };
  ::SetClassLongPtr(window, GCLP_HICONSM, load(SM_CXSMICON, SM_CYSMICON));
  ::SetClassLongPtr(window, GCLP_HICON, load(SM_CXICON, SM_CYICON));
  // The class is shared, so every later host window has the icon too.
  ::UnhookWinEvent(hook);
  host_window_hook = nullptr;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  // Release engines ignore FLUTTER_ENGINE_SWITCH_* environment switches, so
  // the editor enables Impeller and Flutter GPU on the project itself.
  project.set_impeller_switch(flutter::ImpellerSwitch::Enabled);
  project.set_enable_flutter_gpu(true);

  host_window_hook = ::SetWinEventHook(
      EVENT_OBJECT_CREATE, EVENT_OBJECT_CREATE, nullptr, OnWindowCreated,
      ::GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"flutter_scene_editor_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (host_window_hook != nullptr) {
    ::UnhookWinEvent(host_window_hook);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
