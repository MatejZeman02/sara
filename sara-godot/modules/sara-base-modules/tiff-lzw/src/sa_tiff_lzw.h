// SaTiffLzw, one strip of a TIFF unpacked from LZW in native code.
//
// The native half of SaTiffUnpacker's LZW, which asks for it by name and keeps
// its GDScript as the fallback. It holds no state, so strips may be unpacked
// from every worker thread at once.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class SaTiffLzw : public RefCounted {
	GDCLASS(SaTiffLzw, RefCounted)

protected:
	static void _bind_methods();

public:
	// The strip *packed* unpacked to at most *most* bytes, as
	// {"bytes": PackedByteArray, "fault": String}. The bytes are empty when
	// the fault is not, and the fault is the clause SaTiffUnpacker's GDScript
	// gives for the same strip, word for word.
	static Dictionary unpack(const PackedByteArray &packed, int64_t most);
};

} // namespace godot
