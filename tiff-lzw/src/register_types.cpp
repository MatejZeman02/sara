#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sa_tiff_lzw.h"
#include "sa_tiff_samples.h"

using namespace godot;

static void initialize_sara_tiff_lzw(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(SaTiffLzw);
		GDREGISTER_CLASS(SaTiffSamples);
	}
}

static void uninitialize_sara_tiff_lzw(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT sara_tiff_lzw_init(GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_sara_tiff_lzw);
	init.register_terminator(uninitialize_sara_tiff_lzw);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
}
