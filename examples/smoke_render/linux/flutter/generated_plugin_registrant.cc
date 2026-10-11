//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <gamepads_linux/gamepads_linux_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) gamepads_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GamepadsLinuxPlugin");
  gamepads_linux_plugin_register_with_registrar(gamepads_linux_registrar);
}
