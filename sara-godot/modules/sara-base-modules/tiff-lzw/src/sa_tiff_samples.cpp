#include "sa_tiff_samples.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>

using namespace godot;

// What a stored 1.0 is at each integer depth, SaTiffReader's EIGHT_MAX and
// SIXTEEN_MAX. The GDScript divides in double and stores the quotient in a
// float, and so does every pass here.
static constexpr double EIGHT_MAX = 255.0;
static constexpr double SIXTEEN_MAX = 65535.0;

void SaTiffSamples::_bind_methods() {
	ClassDB::bind_static_method("SaTiffSamples",
			D_METHOD("undone", "raw", "width", "height", "samples", "size", "big", "predicted"),
			&SaTiffSamples::undone);
	ClassDB::bind_static_method("SaTiffSamples", D_METHOD("fractions", "raw", "size"), &SaTiffSamples::fractions);
	ClassDB::bind_static_method("SaTiffSamples",
			D_METHOD("straight", "values", "pixels", "samples", "colour", "associated"), &SaTiffSamples::straight);
	ClassDB::bind_static_method("SaTiffSamples", D_METHOD("rounded", "floats"), &SaTiffSamples::rounded);
}

static uint32_t load(const uint8_t *at, int64_t size) {
	if (size == 1) {
		return at[0];
	}
	if (size == 2) {
		return uint32_t(at[0]) | (uint32_t(at[1]) << 8);
	}
	return uint32_t(at[0]) | (uint32_t(at[1]) << 8) | (uint32_t(at[2]) << 16) | (uint32_t(at[3]) << 24);
}

static void store(uint8_t *at, int64_t size, uint32_t value) {
	at[0] = uint8_t(value);
	if (size >= 2) {
		at[1] = uint8_t(value >> 8);
	}
	if (size == 4) {
		at[2] = uint8_t(value >> 16);
		at[3] = uint8_t(value >> 24);
	}
}

// Only whole rows the bytes hold are touched, which for every strip the reader
// hands over is all of them, so a short array is never read past its end.
PackedByteArray SaTiffSamples::undone(const PackedByteArray &raw, int64_t width, int64_t height, int64_t samples,
		int64_t size, bool big, bool predicted) {
	PackedByteArray out = raw;
	if (size != 1 && size != 2 && size != 4) {
		return out;
	}
	uint8_t *bytes = out.ptrw();
	const int64_t total = out.size();
	if (big && size > 1) {
		for (int64_t at = 0; at + size <= total; at += size) {
			for (int64_t i = 0; i < (size >> 1); i++) {
				const uint8_t first = bytes[at + i];
				bytes[at + i] = bytes[at + size - 1 - i];
				bytes[at + size - 1 - i] = first;
			}
		}
	}
	if (!predicted) {
		return out;
	}
	const int64_t step = samples * size;
	const int64_t row_bytes = width * step;
	const uint32_t mask = size == 4 ? 0xFFFFFFFFu : (uint32_t(1) << (size * 8)) - 1;
	for (int64_t y = 0; y < height && (y + 1) * row_bytes <= total; y++) {
		uint8_t *row = bytes + y * row_bytes;
		for (int64_t at = step; at < row_bytes; at += size) {
			store(row + at, size, (load(row + at, size) + load(row + at - step, size)) & mask);
		}
	}
	return out;
}

PackedFloat32Array SaTiffSamples::fractions(const PackedByteArray &raw, int64_t size) {
	PackedFloat32Array out;
	if (size != 1 && size != 2) {
		return out;
	}
	const int64_t count = raw.size() / size;
	out.resize(count);
	float *values = out.ptrw();
	const uint8_t *bytes = raw.ptr();
	const double most = size == 1 ? EIGHT_MAX : SIXTEEN_MAX;
	for (int64_t i = 0; i < count; i++) {
		values[i] = float(double(load(bytes + i * size, size)) / most);
	}
	return out;
}

// A float as GDScript hands it back after holding it as a double. The widening
// quiets a signalling NaN, setting the top bit of its fraction, and a compiler
// may drop a widening and narrowing it can prove changes nothing else, so the
// bit is set here by hand. Any other value is left as it is.
static float quieted(float value) {
	if (!std::isnan(value)) {
		return value;
	}
	uint32_t bits;
	std::memcpy(&bits, &value, sizeof(bits));
	bits |= 0x00400000u;
	std::memcpy(&value, &bits, sizeof(bits));
	return value;
}

// A grey is copied into three channels, a file with no alpha is opaque,
// extras after the alpha are dropped, and an alpha multiplied in is divided
// back out, in double as GDScript's floats are.
PackedFloat32Array SaTiffSamples::straight(const PackedFloat32Array &values, int64_t pixels, int64_t samples,
		bool colour, bool associated) {
	PackedFloat32Array out;
	const int64_t base = colour ? 3 : 1;
	if (samples < base || values.size() < pixels * samples) {
		return out;
	}
	out.resize(pixels * 4);
	float *o = out.ptrw();
	const float *v = values.ptr();
	for (int64_t pixel = 0; pixel < pixels; pixel++) {
		const float *at = v + pixel * samples;
		double red = at[0];
		double green = colour ? double(at[1]) : red;
		double blue = colour ? double(at[2]) : red;
		const double alpha = samples > base ? double(at[base]) : 1.0;
		if (associated && alpha > 0.0) {
			red /= alpha;
			green /= alpha;
			blue /= alpha;
		}
		float *px = o + pixel * 4;
		px[0] = quieted(float(red));
		px[1] = quieted(float(green));
		px[2] = quieted(float(blue));
		px[3] = quieted(float(alpha));
	}
	return out;
}

// GDScript's clampf lets a NaN through and roundi rounds half away from zero,
// which std::round does too. Eight-bit samples divided by an alpha above zero
// are never NaN, so the first never matters here.
PackedByteArray SaTiffSamples::rounded(const PackedFloat32Array &floats) {
	PackedByteArray out;
	const int64_t count = floats.size();
	out.resize(count);
	uint8_t *o = out.ptrw();
	const float *f = floats.ptr();
	for (int64_t i = 0; i < count; i++) {
		double value = f[i];
		value = value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);
		o[i] = uint8_t(int64_t(std::round(value * EIGHT_MAX)));
	}
	return out;
}
