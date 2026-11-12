## What one brush binds for its field: the numbers in a storage buffer, and the
## picture or a white stand-in. Held by the state for as long as its kernel may
## run, because a buffer or a texture collected under a uniform set leaves a
## set that will not build.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside the stretch's own buffer, because the two are what every dispatch of
## the list reads: the path, and the field the path is read through.
extends RefCounted

const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

## The kernel that reads the field without painting, for a suite.
const PROBE_KERNEL: String = "noise_field_probe"

## The numbers the last stroke was laid with, in the buffer's order, which
## a suite reads.
var values: PackedFloat32Array = PackedFloat32Array()
## The picture bound, or null while the field is not one or the pattern
## could not be made, with [member error] saying which.
var picture: SaTexture = null
## The same picture as a grey mask on the CPU, which the texture sensor
## reads at a dab's centre, or null while the field is not one.
var mask: Image = null
var error: String = ""

var _buffer: SaCompute.Buffer = null
var _stand_in: SaTexture = null
## The kernel every stand-in is blanked by, one for every binding.
static var _blanker: SaCompute = null
var _tone: Vector2 = Vector2(0.0, 1.0)
var _tone_of: Image = null


## Both readings of the field this binds over *region* of document pixels, the
## pressure map in red and the lightness in green, for a straight stroke
## through *start* along *direction*, *along* its travelled length there less
## the drift, whose tip reaches *half_width* pixels either side of it. Here
## beside the binding, since the binding is all the probe reads. The readings
## stay in VRAM, and only a suite reads them back, since hard rule 1 (no CPU-GPU ping-pong) keeps a
## readback out of the engine.
func probe(region: Rect2i, start: Vector2, direction: Vector2, along: float, half_width: float) -> SaTexture:
    var readings := SaTexture.new(region.size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    var kernel := SaCompute.new(PROBE_KERNEL)
    kernel.set_image("readings", readings)
    bind(kernel)
    (
        kernel
        . set_params(
            {
                "origin": Vector2(region.position),
                "start": start,
                "direction": direction.normalized(),
                "along": along,
                "half_width": maxf(half_width, 0.5),
            }
        )
    )
    kernel.dispatch_kernel(PROBE_KERNEL, ceili(region.size.x / 8.0), ceili(region.size.y / 8.0), 1)
    return readings


## Makes the numbers' buffer and the stand-in picture, so the first stroke does
## not. Made once and kept, the way [method bind] keeps them.
func warm() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    _make_ready()


## Writes the field's numbers for a stroke. Made once, and written in place
## after, so the uniform sets built against the buffer stay valid.
func write(numbers: PackedFloat32Array) -> void:
    values = numbers
    var bytes := numbers.to_byte_array()
    if _buffer == null or _buffer.size != bytes.size():
        _buffer = SaCompute.Buffer.new(bytes)
    else:
        _buffer.update(bytes)


## Binds *chosen*, the settings' picture, when it was made for *pattern_name*,
## and answers its texture. Reads nothing: a press calls this, and a picture
## the settings never made for that name, because they had no store when it
## was named, is null here and paints as if solid, with [member error] saying
## why.
func pick(chosen: NoiseFieldsScript.Picture, pattern_name: String) -> SaTexture:
    if chosen == null or chosen.pattern_name != pattern_name:
        clear_picture()
        error = "'%s' was never chosen in settings with a pattern store." % pattern_name
        return null
    picture = chosen.texture if chosen.holds(pattern_name) else null
    mask = chosen.mask if picture != null else null
    error = chosen.error if picture == null else ""
    if picture == null and error.is_empty():
        error = "the texture of '%s' is gone." % pattern_name
    return picture


## *numbers* with the picture's tone range in its two last slots, measured
## once a mask and kept, or nought to one while there is no mask, which
## leaves the grey as it is.
##
## **A picture field with no picture reads its stand-in inverted.** The
## stand-in is white, which the pressure map reads as the full pressure, so
## a Picture field whose pattern could not be made would paint only under a
## full press. Read inverted it needs none, and the stroke paints as if
## solid at any pressure while its lightness stays the stand-in's one.
func with_picture(numbers: PackedFloat32Array) -> PackedFloat32Array:
    if mask == null:
        if picture != null or numbers.size() < NoiseFieldsScript.SLOT_COUNT or int(numbers[0]) != NoiseFieldsScript.SLOT_PICTURE:
            return numbers
        var solid := numbers.duplicate()
        solid[NoiseFieldsScript.SLOT_INVERT] = 1.0
        return solid
    if mask != _tone_of:
        _tone_of = mask
        _tone = tone_of(mask)
    var out := numbers.duplicate()
    out[NoiseFieldsScript.SLOT_TONE_LOW] = _tone.x
    out[NoiseFieldsScript.SLOT_TONE_HIGH] = _tone.y
    return out


## The grey *image*'s darkest and lightest texels sit at, as x and y, less
## `NoiseFieldsScript.TONE_TAIL` of them at each end, read off a grid of at
## most `NoiseFieldsScript.TONE_SAMPLES` texels a side. Nought to one for a
## picture of one flat grey, which has no range to spread.
static func tone_of(image: Image) -> Vector2:
    if image == null or image.is_empty():
        return Vector2(0.0, 1.0)
    var size := image.get_size()
    var step_x := maxi(1, ceili(float(size.x) / NoiseFieldsScript.TONE_SAMPLES))
    var step_y := maxi(1, ceili(float(size.y) / NoiseFieldsScript.TONE_SAMPLES))
    var greys := PackedFloat32Array()
    for y in range(0, size.y, step_y):
        for x in range(0, size.x, step_x):
            greys.append(clampf(image.get_pixel(x, y).r, 0.0, 1.0))
    greys.sort()
    var last := greys.size() - 1
    var tail := floori(last * NoiseFieldsScript.TONE_TAIL)
    var low := greys[tail]
    var high := greys[last - tail]
    if high - low < 0.01:
        return Vector2(0.0, 1.0)
    return Vector2(low, high)


## Drops the picture, for a field that is not one.
func clear_picture() -> void:
    picture = null
    mask = null
    error = ""


## Binds the numbers and the picture to *compute*'s `field` buffer and
## `field_image` sampler, the stand-in when there is no picture.
func bind(compute: SaCompute) -> void:
    _make_ready()
    compute.set_storage("field", _buffer.rid)
    var texture := picture
    if texture == null or not texture.rid.is_valid():
        texture = _stand_in
    compute.set_sampler(
        "field_image", texture.rid, RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
    )


## The buffer at `NoiseFieldsScript.blank` until a stroke writes its own, and the
## stand-in picture, each made when it is missing.
func _make_ready() -> void:
    if _buffer == null:
        write(NoiseFieldsScript.blank())
    if _stand_in == null or not _stand_in.rid.is_valid():
        _stand_in = _solid_stand_in()


## One texel at one, which the kernel samples where a Picture could not be
## made, so the stroke paints as if solid. Blanked by the `blank` kernel
## rather than a transfer clear: the dab that samples it
## is dispatched at once, and a transfer is not ordered against the
## compute that follows it, so a stroke could read the allocation's leftovers
## and paint as if empty.
static func _solid_stand_in() -> SaTexture:
    var made := SaTexture.new(Vector2i(1, 1), RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    if _blanker == null:
        _blanker = SaCompute.new("blank")
    _blanker.use_storage_format(made.format)
    _blanker.set_texture(0, made.rid)
    _blanker.set_push_constant_float_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0]))
    _blanker.dispatch_kernel("blank_region", 1, 1, 1)
    return made
