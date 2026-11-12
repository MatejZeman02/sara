## The engine of the six point adjustments: brightness and contrast, hue
## saturation lightness and colour balance, Levels and Curves, and the
## colour lookup.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What a kind's controls mean to the kernel, the 128-byte push constant the
## kernel reads, and the one buffer the curves' lookups, colour balance's nine
## amounts and the lookup's palette ride in. It came out of the skeleton's
## `SaAdjustments` with the filters that use it, because a module implements
## what it registers and the skeleton keeps only what two features share.
##
## The kernels are `base/shaders/adjust.gmacs`, beside the six, so the layout
## constants below have one file to agree with.
## `base/tests/test_color_balance.gd` holds the two together.
##
## One instance per filter, because the buffer is state: it is one fixed size
## and written in place, so the uniform set built against it stays valid
## across every frame of a drag.
class_name SaPointAdjust
extends RefCounted

const BRIGHTNESS_CONTRAST: StringName = &"brightness_contrast"
const HUE_SATURATION_LIGHTNESS: StringName = &"hue_saturation_lightness"
const COLOR_BALANCE: StringName = &"color_balance"
const LEVELS: StringName = &"levels"
const CURVES: StringName = &"curves"
## The colour lookup, whose kernel, step and command read `palette` where the
## painter reads "Colour Lookup".
const PALETTE: StringName = &"palette"

## The kinds this class serves. The name of a kind is the name of its kernel.
const KINDS: Array = [BRIGHTNESS_CONTRAST, HUE_SATURATION_LIGHTNESS, COLOR_BALANCE, LEVELS, CURVES, PALETTE, &"exposure"]

## The channels Levels and Curves act on, in the order the dropdowns show them
## and the order the kernel numbers them. Master is every RGB channel at once,
## and Lightness is Oklab L rather than a fourth RGB one.
const CHANNELS: Array[String] = ["master", "red", "green", "blue", "lightness"]

## What a painter reads for each channel.
const CHANNEL_TITLES := {
    "master": "Master",
    "red": "Red",
    "green": "Green",
    "blue": "Blue",
    "lightness": "Lightness (Oklab)",
}

## The shader file, by the key the shader index files it under: the module's
## folder and the file's name.
const SHADER := "sara-base-modules/adjust"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 5
## Where the buffer is bound, matching adjust.gmacs.
const TABLE_BINDING := 2
## Where the guard buffer is bound, `store_guard` in adjust.gmacs: the largest
## magnitude the document's depth stores, a float, then a word the kernel sets
## to one once a texel came out NaN. Eight bytes.
const GUARD_BINDING := 3
const GUARD_BYTES := 8

## The largest finite number a half float holds, which an F16 document's
## kernels store a larger one as. An F32 document's is the float's own largest.
const F16_LARGEST := 65504.0
const F32_LARGEST := 3.4028234663852886e38

## What the painter calls each kind, for the notice a record gives when its
## kernel wrote a NaN. The filters' own titles, which a record has no way to.
const TITLES := {
    BRIGHTNESS_CONTRAST: "Brightness/Contrast",
    HUE_SATURATION_LIGHTNESS: "Hue/Saturation/Lightness",
    COLOR_BALANCE: "Colour Balance",
    LEVELS: "Levels",
    CURVES: "Curves",
    PALETTE: "Colour Lookup",
}

## The three bands colour balance shifts, darkest first, and the three axes
## inside each. The keys are `<band>_<axis>` in the values a filter sends, so
## "shadows_cr" is the cyan-red amount for the shadows.
const BALANCE_BANDS: Array[String] = ["shadows", "midtones", "highlights"]
const BALANCE_AXES: Array[String] = ["cr", "mg", "yb"]

## Where colour balance's nine amounts sit in the buffer, and how many: above
## the five lookups of `SaCurveEditor.SAMPLES` entries each, one per channel,
## which the curves kernel reads from zero.
##
## Nine numbers plus a toggle do not fit in the push constant: the block is at
## the 128 bytes Vulkan guarantees, five parameter slots are taken by the other
## kinds, two carry the origin, and Levels already took the sixth. So they ride
## the buffer the file binds on every dispatch anyway, above the five lookups
## of 256 samples the curves kernel reads, which is where the kernel looks for
## them. The toggle rides the sixth slot, because one bit does fit.
const BALANCE_BASE := 5 * 256
const BALANCE_FLOATS := 9

## Where the lookup's colours sit in the buffer, above colour balance's nine:
## one float that is the count, then up to `PALETTE_MAX` colours as Oklab L,
## a and b. Thirty-two is more than any palette a painter picks and fewer
## than the swatch strip holds at its widest, and the kernel loops over the
## count rather than the room.
const PALETTE_BASE := BALANCE_BASE + BALANCE_FLOATS
const PALETTE_MAX := 32

## Where each palette colour's own bands sit, after the room for every colour
## rather than interleaved with them, so a colour's offset is three floats on
## from the one before it whatever its bands hold: shadows, midtones,
## highlights and influence, four floats a colour.
const PALETTE_BANDS := PALETTE_BASE + 1 + PALETTE_MAX * 3
const PALETTE_FLOATS := 1 + PALETTE_MAX * 3 + PALETTE_MAX * 4

## Where Levels' Equalize map sits, above the palette: one float that is the
## index in `CHANNELS` of the channel the map was taken from, minus one when
## there is no map, then the map's `EQUALIZE_SAMPLES` entries from input level
## 0 to 1. The `levels` kernel runs it before the handles, so the handles move
## over an equalized layer.
const EQUALIZE_BASE := PALETTE_BASE + PALETTE_FLOATS
const EQUALIZE_SAMPLES := 256
const EQUALIZE_FLOATS := 1 + EQUALIZE_SAMPLES

## What a colour's bands are when nothing names them: no pull in any band and
## the influence every colour starts at.
const BAND_KEYS: Array[String] = ["shadows", "midtones", "highlights", "influence"]
const BAND_DEFAULTS := {"shadows": 0.0, "midtones": 0.0, "highlights": 0.0, "influence": 1.0}
## How far an influence can go, as a factor: twice the reach of a colour at one.
const INFLUENCE_MAX := 2.0

## The Oklab chroma Colorize's saturation names at 100 percent: a strong
## colour at mid lightness, near the edge of sRGB for most hues at L 0.6,
## and past it for a few, which nothing clamps.
const COLORIZE_CHROMA := 0.15

## The record's key for how Hue/Saturation/Lightness scales saturation, and
## its two values. A record that names none scales Oklab a and b at a fixed
## Oklab L, which makes a colour that gains chroma look brighter. One that
## names CAM16 scales CAM16 chroma at a fixed J_HK, the lightness the colour
## shows with the Helmholtz-Kohlrausch effect counted, through
## `shaders/compute/libs/cam16_hellwig.gmacs`. Hue and lightness are Oklab's in
## both, and so is Colorize.
const SATURATION_MODEL := "saturation_model"
const SATURATION_IN_OKLAB := 0.0
const SATURATION_IN_CAM16 := 1.0

## The watches over every guard buffer alive in a debug build. See
## [SaPointAdjust.Watch].
static var _watches: Array[Watch] = []


## The kernel's parameters for *kind* from *values* in the units the passes
## take: brightness and contrast with the formula they are for, or hue in degrees
## with saturation as a factor and lightness as an offset, or Levels' five
## numbers and its channel. One place, so the preview and Apply cannot disagree
## about what a control means.
static func params_for(kind: StringName, values: Dictionary) -> Array:
    if kind == PALETTE:
        # The three amounts, 0 to 1, in the first three slots. The kernel
        # reads each colour's own bands from the buffer instead, and these
        # are the ones a colour with no bands of its own takes, kept here so
        # a dump of the push constant still says what the whole palette was
        # asked for.
        return [
            clampf(float(values.get("shadows", 0.0)), 0.0, 1.0),
            clampf(float(values.get("midtones", 0.0)), 0.0, 1.0),
            clampf(float(values.get("highlights", 0.0)), 0.0, 1.0),
            0.0,
            0.0,
        ]
    if kind == LEVELS:
        # Six numbers, the channel's index in the sixth slot. An unknown word
        # is the master rather than an index from the end. The two inputs are
        # held a gap apart first, so a record that carries them crossed never
        # hands the kernel a zero or inverted span.
        values = SaLevelsGap.held(values)
        return [
            float(values.get("in_black", 0.0)),
            float(values.get("gamma", 1.0)),
            float(values.get("in_white", 1.0)),
            float(values.get("out_black", 0.0)),
            float(values.get("out_white", 1.0)),
            float(maxi(CHANNELS.find(String(values.get("channel", "master"))), 0)),
        ]
    if kind == CURVES:
        # Only the sixth is read: the lookups themselves ride in the buffer,
        # and this says whether the Oklab pass is worth its round trip.
        return [0.0, 0.0, 0.0, 0.0, 0.0, 1.0 if _has_oklab_curve(values) else 0.0]
    if kind == COLOR_BALANCE:
        # Only the sixth is read. The nine amounts ride the buffer, for the
        # reason BALANCE_BASE gives.
        return [0.0, 0.0, 0.0, 0.0, 0.0, 1.0 if bool(values.get("preserve_luminosity", false)) else 0.0]
    if kind == HUE_SATURATION_LIGHTNESS:
        # With `colorize` the hue is an absolute Oklab hue and the saturation
        # a fraction of COLORIZE_CHROMA, sent as the chroma itself, and the
        # sixth slot tells the kernel to set a and b rather than turn them.
        # Without it the sixth is two when the saturation is CAM16's.
        var colorize := bool(values.get("colorize", false))
        var amount := float(values.get("saturation", 1.0))
        var in_cam16 := float(values.get(SATURATION_MODEL, SATURATION_IN_OKLAB)) == SATURATION_IN_CAM16
        var sixth := 1.0 if colorize else (2.0 if in_cam16 else 0.0)
        return [
            0.0,
            1.0,
            deg_to_rad(float(values.get("hue", 0.0))),
            amount * COLORIZE_CHROMA if colorize else amount,
            float(values.get("lightness", 0.0)),
            sixth,
        ]
    # The sixth says which formula, and a record that names none runs the old one.
    var formula := float(values.get("formula", 0.0))
    return [float(values.get("brightness", 0.0)), float(values.get("contrast", 1.0)), 0.0, 1.0, 0.0, formula]


## The 128-byte push constant adjust.gmacs reads: the five parameters, the
## origin of the region being dispatched, which the runner writes, a sixth
## parameter, then the colour space tail exactly as SaColorSpace writes it.
static func push_constant(params: Array, space: SaColorSpace) -> PackedFloat32Array:
    var push := PackedFloat32Array(params)
    var sixth: float = push[5] if push.size() > 5 else 0.0
    push.resize(5)
    push.append(0.0)
    push.append(0.0)
    push.append(sixth)
    push.append_array((space if space != null else SaColorSpace.srgb()).to_push_constant())
    return push


## What the buffer holds for *values*: the five lookups laid out as `CHANNELS`
## orders them, then the nine amounts, band by band, then the lookup's palette,
## its count, its colours in Oklab and each colour's own bands, then Levels'
## Equalize map with the channel it belongs to.
##
## *values*' "curves" key holds channel id -> samples, and a channel it does
## not name is the identity, so a filter that only shaped the master sends one
## array. An amount *values* does not name is zero, which is no shift. Both
## Every part is written whatever the kind, because a kernel that ignores part
## of the buffer costs nothing to hand the whole, and one size means the buffer
## is written in place whichever kind made it. A palette *values* does not name
## is a count of zero, which the kernel reads as nothing to pull towards.
static func table(values: Dictionary) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(EQUALIZE_BASE + EQUALIZE_FLOATS)
    var samples_per := SaCurveEditor.SAMPLES
    var shaped: Dictionary = values.get("curves", {}) as Dictionary
    for channel in range(CHANNELS.size()):
        var samples: PackedFloat32Array = shaped.get(CHANNELS[channel], PackedFloat32Array())
        for i in range(samples_per):
            var identity := float(i) / float(samples_per - 1)
            out[channel * samples_per + i] = samples[i] if samples.size() == samples_per else identity
    for band in range(BALANCE_BANDS.size()):
        for axis in range(BALANCE_AXES.size()):
            var key := "%s_%s" % [BALANCE_BANDS[band], BALANCE_AXES[axis]]
            out[BALANCE_BASE + band * BALANCE_AXES.size() + axis] = float(values.get(key, 0.0))
    var chips := palette_chips(values)
    out[PALETTE_BASE] = float(chips.size())
    for i in chips.size():
        var color: Color = chips[i]["color"]
        var lab := OkhsvConversions.linear_srgb_to_oklab(
            OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
        )
        out[PALETTE_BASE + 1 + i * 3] = lab.x
        out[PALETTE_BASE + 2 + i * 3] = lab.y
        out[PALETTE_BASE + 3 + i * 3] = lab.z
        for band in BAND_KEYS.size():
            out[PALETTE_BANDS + i * BAND_KEYS.size() + band] = float(chips[i][BAND_KEYS[band]])
    var map := equalize_map(values)
    out[EQUALIZE_BASE] = float(CHANNELS.find(String(values.get("equalize_channel", "")))) if not map.is_empty() else -1.0
    for i in map.size():
        out[EQUALIZE_BASE + 1 + i] = map[i]
    return out


## The Equalize map *values* carries under "equalize", as `EQUALIZE_SAMPLES`
## floats, or empty when it carries none, carries one of another length, or
## names no channel `CHANNELS` knows. A saved record reads its numbers back
## as an array of floats and a live one holds a packed array, and both land
## here the same.
static func equalize_map(values: Dictionary) -> PackedFloat32Array:
    var held: Variant = values.get("equalize", [])
    if not (held is Array or held is PackedFloat32Array or held is PackedFloat64Array):
        return PackedFloat32Array()
    var map := PackedFloat32Array(held)
    if map.size() != EQUALIZE_SAMPLES or not CHANNELS.has(String(values.get("equalize_channel", ""))):
        return PackedFloat32Array()
    return map


## The palette in *values* as chips, each its colour and its own bands, at most
## `PALETTE_MAX` of them. "palette" is a list whose entries are each a `Color`
## or a string `Color.html` reads, and anything else is skipped, so a list with
## a stray word in it loses the word and not the filter. "bands" is a list
## beside it, one dictionary per entry and in the same order, so a word skipped
## from the palette takes its bands with it. An entry with no bands of its own
## takes the top-level "shadows", "midtones" and "highlights", which is how a
## caller that knows one set of three for the whole palette still says so.
## Amounts are clamped to 0 and 1, influence to 0 and `INFLUENCE_MAX`.
static func palette_chips(values: Dictionary) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var entries := values.get("palette", []) as Array
    var bands := values.get("bands", []) as Array
    for index in entries.size():
        if out.size() >= PALETTE_MAX:
            break
        var entry: Variant = entries[index]
        var color := Color()
        if entry is Color:
            color = entry
        elif entry is String and Color.html_is_valid(String(entry)):
            color = Color.html(String(entry))
        else:
            continue
        var own: Dictionary = {}
        if index < bands.size() and bands[index] is Dictionary:
            own = bands[index]
        var chip := {"color": color}
        for key in BAND_KEYS:
            var wanted := float(own.get(key, values.get(key, BAND_DEFAULTS[key])))
            chip[key] = clampf(wanted, 0.0, INFLUENCE_MAX if key == "influence" else 1.0)
        out.append(chip)
    return out


## Whether the lightness curve is worth the Oklab round trip: only when the
## caller shaped it.
static func _has_oklab_curve(values: Dictionary) -> bool:
    var shaped: Dictionary = values.get("curves", {}) as Dictionary
    var samples: PackedFloat32Array = shaped.get("lightness", PackedFloat32Array())
    var samples_per := SaCurveEditor.SAMPLES
    if samples.size() != samples_per:
        return false
    for i in range(samples_per):
        if absf(samples[i] - float(i) / float(samples_per - 1)) > 1e-4:
            return true
    return false


## *kind* with *values* on a document stored in *space*, as the point pass the
## compositor previews and Apply walks. Null for a kind that is not one of
## `KINDS`, or when the buffer could not be made.
##
## The buffer is bound for every kind and not only for colour balance: a
## uniform set has to cover every binding the compiled kernel kept, so a kernel
## that never reads it is still dispatched with it there. A kind that reads
## neither half gets the identities and the zeros, which it never looks at.
##
## Every record gets a buffer of its own. The filter chain keeps a record per
## attached filter and the registry has one instance of each filter, so a
## buffer written in place would show the last layer's curve on every layer.
## The guard buffer is its own for the same reason, so a mark says which record
## made it.
func record(kind: StringName, values: Dictionary, space: SaColorSpace) -> SaPointPass:
    if not KINDS.has(kind):
        return null
    var made := SaCompute.Buffer.new(table(values).to_byte_array())
    var guard := SaCompute.Buffer.new(guard_bytes(space))
    if not made.rid.is_valid() or not guard.rid.is_valid():
        return null
    watch(guard, kind)
    return SaPointPass.new(
        SHADER,
        String(kind),
        push_constant(params_for(kind, values), space),
        {TABLE_BINDING: made, GUARD_BINDING: guard},
        ORIGIN_SLOT
    )


## The guard buffer a record starts with for a document stored in *space*: the
## depth's largest magnitude and no mark.
static func guard_bytes(space: SaColorSpace) -> PackedByteArray:
    var half := space != null and space.depth == SaColorSpace.Depth.F16
    var out := PackedByteArray()
    out.resize(GUARD_BYTES)
    out.encode_float(0, F16_LARGEST if half else F32_LARGEST)
    out.encode_u32(4, 0)
    return out


## The watch over one record's guard buffer, which tells the painter once when
## the record's kernel wrote a NaN.
##
## A NaN texel out of a point kernel draws as a black patch, and nothing on the
## screen says which filter wrote it. Each kernel marks its
## record's guard when it stores one. In a debug build, which the installed
## Sara is, every guard alive is asked for the mark after each frame is drawn,
## by an asynchronous read of eight bytes that stalls nothing, and never a
## second time while an answer is on its way. A mark sends one line through the
## notice door naming the filter, and that guard is not asked again. A release
## build watches nothing.
##
## The guard is watched rather than the record, because a filter hands its
## record's parts to `SaFilterContext.point_pass`, which builds a pass of its
## own from them. The record is dropped there and its buffers go on in the new
## pass, so a record that asked after each bind would never be bound in the
## running app. A watch holds its guard weakly, so a record dropped takes its guard
## with it and the watch goes at the next frame. An inner class rather than a
## file, because nothing else builds one.
class Watch:
    extends RefCounted

    ## The guard buffer, held weakly.
    var guard: WeakRef = null
    ## The filter's name as the painter reads it.
    var title: String = ""
    var _told := false
    var _asking := false

    func _init(buffer: SaCompute.Buffer, kind: StringName) -> void:
        guard = weakref(buffer)
        title = String(TITLES.get(kind, kind))

    ## Whether the guard is still there to ask and has not been found marked.
    func watching() -> bool:
        return not _told and guard.get_ref() != null

    ## Asks for the mark, unless an answer is on its way.
    func ask() -> void:
        var buffer := guard.get_ref() as SaCompute.Buffer
        if _told or _asking or buffer == null or buffer.rd == null or not buffer.rid.is_valid():
            return
        _asking = true
        buffer.rd.buffer_get_data_async(buffer.rid, heard, 0, GUARD_BYTES)

    ## Reads the guard's *bytes* and tells the notice door once when they hold
    ## the mark. The device's answer, handed to it as this method and never a
    ## lambda, because a method holds the watch by its id alone, so a watch let
    ## go meanwhile is not kept for an answer nobody needs, and an answer still
    ## owed at quit is dropped harmlessly in the engine's teardown, where a
    ## lambda aborts it, as `SaExport.ask_texture_bytes` tells.
    func heard(bytes: PackedByteArray) -> void:
        _asking = false
        if _told or bytes.size() < GUARD_BYTES or bytes.decode_u32(4) == 0:
            return
        _told = true
        EventBus.corner_notice.emit(
            tr("%s wrote a value that is not a number, which draws black. Please report it with the picture.") % title
        )


## Watches *guard*, the guard buffer of a record of *kind*, in a debug build.
static func watch(guard: SaCompute.Buffer, kind: StringName) -> void:
    if not OS.is_debug_build() or not guard.rid.is_valid():
        return
    _watches.append(Watch.new(guard, kind))
    if not RenderingServer.frame_post_draw.is_connected(SaPointAdjust._ask_guards):
        RenderingServer.frame_post_draw.connect(SaPointAdjust._ask_guards)


static func _ask_guards() -> void:
    var kept: Array[Watch] = []
    for watched: Watch in _watches:
        if watched.watching():
            watched.ask()
            kept.append(watched)
    _watches = kept


## *kind* with *values* over *layer* of *document*, as one history step called
## *step_name*. The door a suite or a capture step takes when no dialog is
## open, and the same walk Apply makes from one.
func apply(document: SaDocument, layer: SaLayer, kind: StringName, values: Dictionary, step_name: String) -> bool:
    if document == null or layer == null or GlobalShaderCompiler.get_rd() == null:
        return false
    var recorded := record(kind, values, document.color_space)
    if recorded == null:
        return false
    # The walk asks each chunk's texture for its format, so none is set here.
    return SaFilterApply.apply_point(document, layer, recorded, SaCompute.new(SHADER), step_name)
