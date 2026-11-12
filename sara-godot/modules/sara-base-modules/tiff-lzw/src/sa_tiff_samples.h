// SaTiffSamples, the passes SaTiffReader makes over every sample of a TIFF
// once its strips are unpacked, in native code.
//
// The native half of the reader's per-sample loops, which it asks for by name
// and keeps its GDScript for as the fallback. Each pass is the GDScript's step
// for step, with the same arithmetic in the same widths, so a picture reads to
// the same floats to the bit either way. It holds no state.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class SaTiffSamples : public RefCounted {
	GDCLASS(SaTiffSamples, RefCounted)

protected:
	static void _bind_methods();

public:
	// *raw*, *height* rows of *width* pixels of *samples* samples of *size*
	// bytes, turned little-endian when *big* and with the horizontal
	// differencing undone when *predicted*: SaTiffReader._swap and
	// SaTiffReader._undo_predictor.
	static PackedByteArray undone(const PackedByteArray &raw, int64_t width, int64_t height, int64_t samples,
			int64_t size, bool big, bool predicted);
	// Little-endian unsigned samples of *size* bytes, one or two, as fractions
	// of their full range: SaTiffReader._sixteen and the first loop of
	// SaTiffReader._byte_image.
	static PackedFloat32Array fractions(const PackedByteArray &raw, int64_t size);
	// Samples already scaled, *samples* a pixel, as straight RGBA: the
	// pixel walk of SaTiffReader._float_image.
	static PackedFloat32Array straight(const PackedFloat32Array &values, int64_t pixels, int64_t samples,
			bool colour, bool associated);
	// Floats clamped to one and rounded to eight bits: the last loop of
	// SaTiffReader._byte_image.
	static PackedByteArray rounded(const PackedFloat32Array &floats);
};

} // namespace godot
