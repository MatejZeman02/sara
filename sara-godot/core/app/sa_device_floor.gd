## What the current device supports of what Sara asks a GPU for.
##
## Reads limits and support bits the driver already knows, so a floor claim in
## the release notes can be checked against a running app rather than typed
## from memory. Asks the device and allocates nothing, dispatches nothing and reads
## nothing back: a machine that cannot paint should still be able to answer this.
class_name SaDeviceFloor
extends RefCounted

## The dab's push constant, the widest workgroup any shipped kernel declares and
## a 16384-wide canvas, the three numbers Sara's own kernels ask of a device.
## The workgroup is the magic wand's `@workgroup_size(256)` in
## modules/sara-base-modules/base/shaders/wand.gmacs, and
## test_no_kernel_outgrows_the_floor.gd fails the run when a kernel declares more
## than this, so the figure cannot fall behind the kernels again.
const NEEDS_PUSH_CONSTANT_BYTES: int = 128
const NEEDS_WORKGROUP_INVOCATIONS: int = 256
const NEEDS_TEXTURE_SIZE_2D: int = 16384

## Short names for the report, not a claim about what GLSL calls them.
## SaFieldSpec.BYTES_PER_TEXEL is keyed by format, so this stays in step with a
## sixth format the moment it is added there, and a name missing here is a typo
## rather than a silently dropped entry.
const FORMAT_NAMES := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: "RGBA32F",
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: "RGBA16F",
    RenderingDevice.DATA_FORMAT_R32_SFLOAT: "R32F",
    RenderingDevice.DATA_FORMAT_R32G32_SFLOAT: "RG32F",
    RenderingDevice.DATA_FORMAT_R16_SFLOAT: "R16F",
}


## The running app's own device, asked once.
static func check() -> Dictionary[String, Variant]:
    return describe(GlobalShaderCompiler.get_rd())


## `{"device": "none"}` for `rd == null`, which is a test's way to ask what a
## machine with no working driver would answer without unplugging a GPU.
## Otherwise the device's name and vendor, whether every
## SaFieldSpec.BYTES_PER_TEXEL format is a storage image the way SaTexture
## makes one, and the three limits beside what Sara needs of them.
static func describe(rd: RenderingDevice) -> Dictionary[String, Variant]:
    if rd == null:
        return {"device": "none"}

    var formats: Dictionary[int, bool] = {}
    for format: int in SaFieldSpec.BYTES_PER_TEXEL:
        formats[format] = rd.texture_is_format_supported_for_usage(format, SaTexture.USAGE_BITS)

    var limits: Dictionary[String, Dictionary] = {
        "push_constant_bytes": _limit(rd.limit_get(RenderingDevice.LIMIT_MAX_PUSH_CONSTANT_SIZE), NEEDS_PUSH_CONSTANT_BYTES),
        "workgroup_invocations":
        _limit(rd.limit_get(RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_INVOCATIONS), NEEDS_WORKGROUP_INVOCATIONS),
        "texture_size_2d": _limit(rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D), NEEDS_TEXTURE_SIZE_2D),
    }
    return {
        "device": rd.get_device_name(),
        "vendor": RenderingServer.get_video_adapter_vendor(),
        "formats": formats,
        "limits": limits,
    }


## One limit beside what Sara needs of it, typed here because a literal nested
## in another is built untyped.
static func _limit(limit: int, needs: int) -> Dictionary[String, int]:
    return {"limit": limit, "needs": needs}


## The running app's own summary.
static func summary() -> String:
    return summary_for(check())


## "met", "no device", or a comma list of what falls short, for the boot
## header's one line and the notes export beside it.
static func summary_for(result: Dictionary[String, Variant]) -> String:
    if result.get("device", "") == "none":
        return "no device"

    var missing: Array[String] = []
    var formats: Dictionary[int, bool] = result["formats"]
    for format: int in formats:
        if not formats[format]:
            missing.append(FORMAT_NAMES.get(format, str(format)))

    var limits: Dictionary[String, Dictionary] = result["limits"]
    for key: String in limits:
        var entry: Dictionary[String, int] = limits[key]
        if entry["limit"] < entry["needs"]:
            missing.append(key)

    return "met" if missing.is_empty() else ", ".join(missing)
