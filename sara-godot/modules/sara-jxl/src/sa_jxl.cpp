#include "sa_jxl.h"

#include <jxl/decode.h>
#include <jxl/encode.h>

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cstring>
#include <vector>

using namespace godot;

void SaJxl::_bind_methods() {
	ClassDB::bind_static_method("SaJxl",
			D_METHOD("encode", "texels", "width", "height", "channels", "bytes_per_channel", "effort", "options"),
			&SaJxl::encode);
	ClassDB::bind_static_method("SaJxl",
			D_METHOD("encode_for_save", "texels", "width", "height", "channels", "bytes_per_channel"),
			&SaJxl::encode_for_save);
	ClassDB::bind_static_method("SaJxl",
			D_METHOD("decode", "stream", "width", "height", "channels", "bytes_per_channel"), &SaJxl::decode);
	ClassDB::bind_static_method("SaJxl", D_METHOD("libjxl_version"), &SaJxl::libjxl_version);
}

static bool shape_ok(int width, int height, int channels, int bytes_per_channel) {
	return width > 0 && height > 0 && (channels == 1 || channels == 4) &&
			(bytes_per_channel == 2 || bytes_per_channel == 4);
}

// The bits a full float of one channel needs. A save that rounds colour to 12
// significant bits leaves the low 11 bits of every mantissa zero, and a stream
// that declared 32 bits would carry them and lose most of its gain. So the
// mantissa is declared only as wide as its widest value, at least the 2 bits
// libjxl takes with 8 of exponent. A subnormal keeps all 32, since libjxl
// narrows only normal floats exactly.
static uint32_t float_bits(const uint8_t *bytes, int64_t count, int stride) {
	uint32_t used = 0;
	for (int64_t i = 0; i < count; i += stride) {
		uint32_t w;
		memcpy(&w, bytes + 4 * i, 4);
		if ((w & 0x7f800000u) == 0 && (w & 0x007fffffu) != 0) {
			return 32;
		}
		used |= w;
	}
	uint32_t zeros = 0;
	while (zeros < 21 && (used & (1u << zeros)) == 0) {
		zeros++;
	}
	return 32 - zeros;
}

PackedByteArray SaJxl::encode(const PackedByteArray &texels, int width, int height, int channels,
		int bytes_per_channel, int effort, const Dictionary &options) {
	PackedByteArray out;
	if (!shape_ok(width, height, channels, bytes_per_channel) ||
			texels.size() != int64_t(width) * height * channels * bytes_per_channel) {
		return out;
	}
	JxlEncoder *enc = JxlEncoderCreate(nullptr);
	JxlEncoderUseContainer(enc, JXL_FALSE);
	JxlBasicInfo info;
	JxlEncoderInitBasicInfo(&info);
	info.xsize = width;
	info.ysize = height;
	// The sample is the float's own bit pattern: half has 5 exponent bits and
	// 10 of mantissa, full 8 and up to 23, so every value comes back exact.
	info.exponent_bits_per_sample = bytes_per_channel == 4 ? 8 : 5;
	info.bits_per_sample = 16;
	info.uses_original_profile = JXL_TRUE;
	info.num_color_channels = channels == 4 ? 3 : 1;
	info.num_extra_channels = channels == 4 ? 1 : 0;
	info.alpha_bits = channels == 4 ? 16 : 0;
	info.alpha_exponent_bits = channels == 4 ? info.exponent_bits_per_sample : 0;
	if (bytes_per_channel == 4) {
		// Colour and alpha each as wide as they need. An extra channel takes
		// a depth of its own, and the three colour channels share one.
		const uint8_t *bytes = texels.ptr();
		const int64_t count = int64_t(width) * height * channels;
		uint32_t colour_bits = 11;
		for (int c = 0; c < (channels == 4 ? 3 : 1); c++) {
			colour_bits = std::max(colour_bits, float_bits(bytes + 4 * c, count - c, channels));
		}
		info.bits_per_sample = colour_bits;
		info.alpha_bits = channels == 4 ? float_bits(bytes + 12, count - 3, 4) : 0;
	}
	info.alpha_premultiplied = JXL_FALSE;
	JxlColorEncoding colour;
	// No colour management happens on a lossless stream with the original
	// profile kept. The tag only says the samples are linear and unbounded.
	JxlColorEncodingSetToLinearSRGB(&colour, channels == 1);
	JxlEncoderFrameSettings *settings = nullptr;
	bool ok = JxlEncoderSetCodestreamLevel(enc, 10) == JXL_ENC_SUCCESS &&
			JxlEncoderSetBasicInfo(enc, &info) == JXL_ENC_SUCCESS &&
			JxlEncoderSetColorEncoding(enc, &colour) == JXL_ENC_SUCCESS;
	if (ok) {
		settings = JxlEncoderFrameSettingsCreate(enc, nullptr);
		ok = JxlEncoderSetFrameLossless(settings, JXL_TRUE) == JXL_ENC_SUCCESS &&
				JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, effort) == JXL_ENC_SUCCESS;
	}
	const Array keys = options.keys();
	for (int i = 0; ok && i < keys.size(); i++) {
		const JxlEncoderFrameSettingId id = JxlEncoderFrameSettingId(int(keys[i]));
		const Variant value = options[keys[i]];
		ok = (value.get_type() == Variant::FLOAT
						? JxlEncoderFrameSettingsSetFloatOption(settings, id, float(double(value)))
						: JxlEncoderFrameSettingsSetOption(settings, id, int64_t(value))) == JXL_ENC_SUCCESS;
	}
	const JxlPixelFormat format = { uint32_t(channels), bytes_per_channel == 4 ? JXL_TYPE_FLOAT : JXL_TYPE_FLOAT16,
		JXL_LITTLE_ENDIAN, 0 };
	ok = ok && JxlEncoderAddImageFrame(settings, &format, texels.ptr(), texels.size()) == JXL_ENC_SUCCESS;
	if (ok) {
		JxlEncoderCloseInput(enc);
		std::vector<uint8_t> buffer(texels.size() / 4 + 4096);
		uint8_t *next = buffer.data();
		size_t avail = buffer.size();
		JxlEncoderStatus status;
		while ((status = JxlEncoderProcessOutput(enc, &next, &avail)) == JXL_ENC_NEED_MORE_OUTPUT) {
			const size_t used = next - buffer.data();
			buffer.resize(buffer.size() * 2);
			next = buffer.data() + used;
			avail = buffer.size() - used;
		}
		if (status == JXL_ENC_SUCCESS) {
			out.resize(next - buffer.data());
			memcpy(out.ptrw(), buffer.data(), out.size());
		}
	}
	JxlEncoderDestroy(enc);
	return out;
}

PackedByteArray SaJxl::encode_for_save(const PackedByteArray &texels, int width, int height, int channels,
		int bytes_per_channel) {
	Dictionary lean;
	lean[int(JXL_ENC_FRAME_SETTING_PATCHES)] = 0;
	lean[int(JXL_ENC_FRAME_SETTING_MODULAR_PREDICTOR)] = 5;
	lean[int(JXL_ENC_FRAME_SETTING_MODULAR_MA_TREE_LEARNING_PERCENT)] = 10.0;
	lean[int(JXL_ENC_FRAME_SETTING_DECODING_SPEED)] = 1;
	return encode(texels, width, height, channels, bytes_per_channel, 8, lean);
}

PackedByteArray SaJxl::decode(const PackedByteArray &stream, int width, int height, int channels,
		int bytes_per_channel) {
	PackedByteArray out;
	if (!shape_ok(width, height, channels, bytes_per_channel)) {
		return out;
	}
	out.resize(int64_t(width) * height * channels * bytes_per_channel);
	JxlDecoder *dec = JxlDecoderCreate(nullptr);
	JxlDecoderSubscribeEvents(dec, JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE);
	JxlDecoderSetInput(dec, stream.ptr(), stream.size());
	JxlDecoderCloseInput(dec);
	const JxlPixelFormat format = { uint32_t(channels), bytes_per_channel == 4 ? JXL_TYPE_FLOAT : JXL_TYPE_FLOAT16,
		JXL_LITTLE_ENDIAN, 0 };
	bool ok = false;
	// A stream has one frame, so a few events end it. The bound stops a
	// broken stream from looping.
	for (int guard = 0; guard < 16; guard++) {
		const JxlDecoderStatus status = JxlDecoderProcessInput(dec);
		if (status == JXL_DEC_BASIC_INFO) {
			JxlBasicInfo info;
			if (JxlDecoderGetBasicInfo(dec, &info) != JXL_DEC_SUCCESS || info.xsize != uint32_t(width) ||
					info.ysize != uint32_t(height) ||
					info.num_color_channels + info.num_extra_channels != uint32_t(channels == 4 ? 4 : 1)) {
				break;
			}
		} else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
			if (JxlDecoderSetImageOutBuffer(dec, &format, out.ptrw(), out.size()) != JXL_DEC_SUCCESS) {
				break;
			}
		} else if (status == JXL_DEC_FULL_IMAGE) {
			continue;
		} else {
			ok = status == JXL_DEC_SUCCESS;
			break;
		}
	}
	JxlDecoderDestroy(dec);
	if (!ok) {
		out.clear();
	}
	return out;
}

int SaJxl::libjxl_version() {
	return int(JxlEncoderVersion());
}
