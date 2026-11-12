#include "sa_tiff_lzw.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>

using namespace godot;

// The TIFF 6.0 variant, as SaTiffUnpacker's comment tells it: codes most
// significant bit first, nine bits wide at the start and growing one code
// early to twelve, 256 clearing the table and 257 ending the strip.
static constexpr int LZW_CLEAR = 256;
static constexpr int LZW_END = 257;
static constexpr int LZW_FIRST_FREE = 258;
static constexpr int LZW_MIN_WIDTH = 9;
static constexpr int LZW_MAX_WIDTH = 12;
static constexpr int LZW_TABLE = 1 << LZW_MAX_WIDTH;
// What the output is grown by past the strip's most. Six codes can be unpacked
// between two asks of the bound, none longer than the table.
static constexpr int64_t LZW_SLACK = 7 * LZW_TABLE;

void SaTiffLzw::_bind_methods() {
	ClassDB::bind_static_method("SaTiffLzw", D_METHOD("unpack", "packed", "most"), &SaTiffLzw::unpack);
}

static Dictionary answer(const PackedByteArray &bytes, const String &fault) {
	Dictionary result;
	result["bytes"] = bytes;
	result["fault"] = fault;
	return result;
}

// The same steps as SaTiffUnpacker._lzw, one for one, so a strip gives the same
// bytes and a broken one the same fault: an entry is a start in the output and
// a length, a code is copied forward from what is already written, which also
// gives the code one past the table, the buffer fills six bytes at once while
// eight are left and byte by byte after, and the bound is asked once a fill.
Dictionary SaTiffLzw::unpack(const PackedByteArray &packed, int64_t most) {
	if (most < 0) {
		most = 0;
	}
	PackedByteArray out;
	out.resize(most + LZW_SLACK);
	uint8_t *o = out.ptrw();
	const uint8_t *p = packed.ptr();
	const int64_t end = packed.size();
	const int64_t room = most + LZW_SLACK;
	int64_t start[LZW_TABLE];
	int64_t length[LZW_TABLE];
	int64_t at = 0;
	// Bits read ahead of the code being built, the newest at the bottom.
	uint64_t held = 0;
	int ahead = 0;
	int width = LZW_MIN_WIDTH;
	uint64_t mask = (uint64_t(1) << width) - 1;
	// The width grows when the table reaches this, never past twelve bits.
	int grow = int(mask);
	int next = LZW_FIRST_FREE;
	// Where the previous code's string starts in the output, -1 after a clear.
	int64_t previous = -1;
	int64_t written = 0;
	const String more = "its LZW pixels unpack to more than their strip holds";
	while (true) {
		if (ahead < width) {
			if (written > most) {
				break;
			}
			if (at + 8 <= end) {
				const uint8_t *b = p + at;
				uint64_t six = (uint64_t(b[0]) << 40) | (uint64_t(b[1]) << 32) | (uint64_t(b[2]) << 24) |
						(uint64_t(b[3]) << 16) | (uint64_t(b[4]) << 8) | uint64_t(b[5]);
				held = ((held & 0xFFF) << 48) | six;
				at += 6;
				ahead += 48;
			} else {
				while (ahead < width && at < end) {
					held = ((held & 0xFFF) << 8) | p[at];
					at += 1;
					ahead += 8;
				}
				if (ahead < width) {
					break;
				}
			}
		}
		ahead -= width;
		const int code = int((held >> ahead) & mask);
		if (code < LZW_CLEAR) {
			if (previous >= 0 && next < LZW_TABLE) {
				start[next] = previous;
				length[next] = written - previous + 1;
				next += 1;
			}
			if (written >= room) {
				return answer(PackedByteArray(), more);
			}
			previous = written;
			o[written] = uint8_t(code);
			written += 1;
		} else if (code >= LZW_FIRST_FREE) {
			if (previous < 0) {
				return answer(PackedByteArray(),
						"its LZW pixels name code " + String::num_int64(code) + " before the table holds it");
			}
			if (next < LZW_TABLE) {
				start[next] = previous;
				length[next] = written - previous + 1;
				next += 1;
			}
			if (code >= next) {
				return answer(PackedByteArray(),
						"its LZW pixels name code " + String::num_int64(code) + ", which the table does not hold");
			}
			const int64_t from = start[code];
			const int64_t count = length[code];
			if (written + count > room) {
				return answer(PackedByteArray(), more);
			}
			// Byte by byte and forward, since the code one past the table
			// reads the byte this copy writes first.
			for (int64_t i = 0; i < count; i++) {
				o[written + i] = o[from + i];
			}
			previous = written;
			written += count;
		} else if (code == LZW_END) {
			break;
		} else {
			next = LZW_FIRST_FREE;
			width = LZW_MIN_WIDTH;
			mask = (uint64_t(1) << width) - 1;
			grow = int(mask);
			previous = -1;
			continue;
		}
		if (next >= grow) {
			width += 1;
			mask = (uint64_t(1) << width) - 1;
			grow = width < LZW_MAX_WIDTH ? int(mask) : LZW_TABLE + 1;
		}
	}
	if (written > most) {
		return answer(PackedByteArray(), more);
	}
	out.resize(written);
	return answer(out, "");
}
