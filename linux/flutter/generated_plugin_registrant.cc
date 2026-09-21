//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audioplayers_linux/audioplayers_linux_plugin.h>
#include <flutter_paste_input/flutter_paste_input_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) audioplayers_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AudioplayersLinuxPlugin");
  audioplayers_linux_plugin_register_with_registrar(audioplayers_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter_paste_input_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterPasteInputPlugin");
  flutter_paste_input_plugin_register_with_registrar(flutter_paste_input_registrar);
}
