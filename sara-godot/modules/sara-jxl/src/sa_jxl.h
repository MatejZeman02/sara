// SaJxl, one chunk field to a JPEG XL lossless codestream and back.
//
// The native half of File > Save as JPEG XL. It holds no state, so a save may
// call it from every worker thread at once, one chunk a call.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class SaJxl : public RefCounted {
	GDCLASS(SaJxl, RefCounted)

protected:
	static void _bind_methods();

public:
	// The texels of a field, row by row from the top, 1 or 4 channels of half
	// (bytes_per_channel 2) or full (4) floats, little endian, alpha straight.
	// Returns the codestream, or an empty array if libjxl refused. Options
	// maps a JxlEncoderFrameSettingId to its value, a float value set as one.
	static PackedByteArray encode(const PackedByteArray &texels, int width, int height, int channels,
			int bytes_per_channel, int effort, const Dictionary &options);
	// The same at the save's setting, lean effort 8: effort 8 with patches
	// off, the gradient predictor, the tree learnt from 10% of the texels and
	// decoding speed 1, and effort 7's grouping, table search and colour
	// transforms, which the build fixes in libjxl.
	static PackedByteArray encode_for_save(const PackedByteArray &texels, int width, int height, int channels,
			int bytes_per_channel);
	// The texels back, or an empty array if the stream is not a lossless
	// image of that size and those channels.
	static PackedByteArray decode(const PackedByteArray &stream, int width, int height, int channels,
			int bytes_per_channel);
	// The libjxl version linked in, as major * 1000000 + minor * 1000 + patch.
	static int libjxl_version();
};

} // namespace godot
