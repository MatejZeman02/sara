## Levels' three eyedroppers: a press arms one, and the next click on the
## canvas hands the panel the place it landed, which reads the level there and
## writes it into the black point, the gamma or the white point.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The click.** While one is armed the door's `SaPickHold` puts the
## Eyedropper in the painter's hand, the hold Select > Colour Range takes for
## its Pick from canvas box, so a click on the canvas picks rather than paints,
## and the tool and the foreground come back once the pick has landed. The
## Eyedropper says it picked through `EventBus.color_picked`, but the colour it
## picked is not the one wanted: it is the composite, with this Levels' own
## preview drawn over it. So the bus says when, the view's pointer says where,
## and [method read_texel] reads what Levels reads there.
##
## **The texel.** One texel of what this Levels filters, which is the active
## layer's paint in the Filter menu's dialog and the record's input from the
## door's `SaNodeInput` for an attached one, copied out and read back the way
## the Eyedropper reads one. That is the readback hard rule 1 allows a pick, at
## a click and never in a frame.
##
## **The level.** Where the handles act, which [method level_of] mirrors from
## the `levels` kernel: equalized first when a map is held, then Oklab L for
## Lightness, the channel's own value for a colour channel and Rec. 709 luma for
## Master, the luma the Master histogram counts. On an RGB document that is the
## stored triple, and on an Oklab one the document's transfer over linear sRGB,
## the view the kernel moves the handles in.
##
## **Escape** puts an armed eyedropper away. The key reaches the root window's
## `window_input` before the engine hands it on to the focused dialog, and the
## dialog would hear it as Cancel, so the dialog's focus is let go of first,
## the way `DockerFocus.release` lets a docker's go, and the edit stays open.
class_name SaLevelsSampler
extends RefCounted

## A pick landed at *at*, in document coordinates, for the eyedropper *kind*.
signal sampled(kind: String, at: Vector2)

## The armed eyedropper changed to *kind*, empty when none is.
signal armed_changed(kind: String)

## The three, in the order their buttons stand.
const KINDS: Array[String] = ["black", "grey", "white"]

## Rec. 709 luma, as `graph.gmacs` weighs the Master row.
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

## The armed eyedropper, empty when none is.
var kind: String = ""
## True from the moment a pick landed until the hold goes at the end of the
## frame, so a drag of the same press picks nothing more.
var _landed: bool = false
var _hold := SaPickHold.new()
## The main canvas's tool machine, untyped as a surface holds it, or null.
var _machine: Variant = null
## The window the panel stands in, whose focus an Escape lets go of, and the
## root window whose keys are heard.
var _window: Window = null
var _root: Window = null
var _readback: SaTexture = null


## Arms the eyedropper *armed* over the canvas *machine* drives, for the panel
## in *window*. Another armed one is put away first.
func arm(armed: String, machine: Variant, window: Window) -> void:
    disarm()
    if not KINDS.has(armed):
        return
    kind = armed
    _machine = machine
    _window = window
    _hold.take(machine)
    EventBus.color_picked.connect(_on_color_picked)
    _root = window.get_tree().root if window != null and window.is_inside_tree() else null
    if _root != null:
        _root.window_input.connect(_on_root_input)
    armed_changed.emit(armed)


## Puts the armed eyedropper away and gives back the tool and the foreground.
## Safe to call when none is armed.
func disarm() -> void:
    var was := kind
    kind = ""
    _landed = false
    if EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.disconnect(_on_color_picked)
    if is_instance_valid(_root) and _root.window_input.is_connected(_on_root_input):
        _root.window_input.disconnect(_on_root_input)
    _root = null
    _hold.let_go()
    if not was.is_empty():
        armed_changed.emit("")


## The pick was taken, so the eyedropper goes, at the end of the frame: the
## Eyedropper is still inside the press that picked, and the foreground store
## is still hearing the same pick, which the hold's foreground has to follow.
func land() -> void:
    _landed = true
    disarm.call_deferred()


## The stored colour under *at* in *input*, straight and in the document's
## own encoding, or `SaFieldSpec.NO_PAINT` off the canvas of *canvas_size* or
## where the input holds nothing. One texel copied out and read back.
func read_texel(input: SaNodeInput, at: Vector2, canvas_size: Vector2i) -> Color:
    var place := Vector2i(floori(at.x), floori(at.y))
    if not Rect2i(Vector2i.ZERO, canvas_size).has_point(place):
        return SaFieldSpec.NO_PAINT
    var grid := Vector2i(floori(float(place.x) / SaChunk.SIZE), floori(float(place.y) / SaChunk.SIZE))
    var source := input.at(grid)
    if source == null or not source.rid.is_valid():
        return SaFieldSpec.NO_PAINT
    # A layer at another resolution keeps more or fewer texels a chunk, so the
    # place is scaled by the texture's own edge.
    var local := place - grid * SaChunk.SIZE
    var texel := Vector2i((Vector2(local * source.size) / float(SaChunk.SIZE)).floor())
    if _readback == null or _readback.format != source.format:
        _readback = SaTexture.new(Vector2i.ONE, source.format)
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_copy(source.rid, _readback.rid, Vector3(texel.x, texel.y, 0), Vector3.ZERO, Vector3.ONE, 0, 0, 0, 0)
    var data: PackedByteArray = rd.texture_get_data(_readback.rid, 0)
    if data.size() < int(SaFieldSpec.BYTES_PER_TEXEL.get(source.format, 16)):
        return SaFieldSpec.NO_PAINT
    return SaFieldSpec.decode_texel(data, source.format)


## The level the handles of *channel* see in the stored colour *stored* of a
## document in *space*, after the Equalize *map* when it holds one.
static func level_of(stored: Color, space: SaColorSpace, channel: String, map: Array) -> float:
    var base := Vector3(stored.r, stored.g, stored.b)
    if map.size() == SaPointAdjust.EQUALIZE_SAMPLES:
        base = _equalized(base, space, map)
    if channel == "lightness":
        return _to_oklab(base, space).x
    var rgb := _to_handles(base, space)
    match channel:
        "red":
            return rgb.x
        "green":
            return rgb.y
        "blue":
            return rgb.z
    return rgb.dot(LUMA)


## The kernel's `equalized`: the map over Oklab L alone, a and b kept.
static func _equalized(base: Vector3, space: SaColorSpace, map: Array) -> Vector3:
    var lab := _to_oklab(base, space)
    return _from_oklab(Vector3(_equalize_at(map, lab.x), lab.y, lab.z), space)


## The kernel's `equalize_at`: the map read between its entries, and past
## either end along the end's own slope, or one where the end is flat.
static func _equalize_at(map: Array, x: float) -> float:
    var last := map.size() - 1
    if x < 0.0:
        return float(map[0]) + x * _end_slope(map, 0, 1)
    if x > 1.0:
        return float(map[last]) + (x - 1.0) * _end_slope(map, last - 1, last)
    var at := x * float(last)
    var index := mini(floori(at), last - 1)
    return lerpf(float(map[index]), float(map[index + 1]), at - float(index))


static func _end_slope(map: Array, low: int, high: int) -> float:
    var slope := (float(map[high]) - float(map[low])) * float(map.size() - 1)
    return slope if slope > 0.0 else 1.0


static func _is_oklab(space: SaColorSpace) -> bool:
    return space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB


static func _curve(space: SaColorSpace) -> SaTransferFunction:
    return space.transfer if space != null and space.transfer != null else SaTransferFunction.srgb()


## The kernel's `document_to_rgb`, the view the handles act in.
static func _to_handles(base: Vector3, space: SaColorSpace) -> Vector3:
    if not _is_oklab(space):
        return base
    return _encode(space.from_linear_srgb_matrix() * SaOklab.to_linear_srgb(base), _curve(space))


static func _to_oklab(base: Vector3, space: SaColorSpace) -> Vector3:
    if _is_oklab(space):
        return base
    var gamut: Basis = space.to_linear_srgb_matrix() if space != null else Basis.IDENTITY
    return SaOklab.from_linear_srgb(gamut * _decode(base, _curve(space)))


static func _from_oklab(lab: Vector3, space: SaColorSpace) -> Vector3:
    if _is_oklab(space):
        return lab
    var gamut: Basis = space.from_linear_srgb_matrix() if space != null else Basis.IDENTITY
    return _encode(gamut * SaOklab.to_linear_srgb(lab), _curve(space))


static func _encode(light: Vector3, curve: SaTransferFunction) -> Vector3:
    return Vector3(curve.encode(light.x), curve.encode(light.y), curve.encode(light.z))


static func _decode(value: Vector3, curve: SaTransferFunction) -> Vector3:
    return Vector3(curve.decode(value.x), curve.decode(value.y), curve.decode(value.z))


## A pick arrived on the bus. Read only while the hold stands with the
## Eyedropper in the hand, so the hold's own write of the foreground and a
## swatch clicked meanwhile are not taken for the canvas.
func _on_color_picked(_color: Color) -> void:
    if kind.is_empty() or _landed or _hold._restoring or not _hold.is_picking():
        return
    var surface: Variant = _machine.surface
    if surface == null or surface.view == null:
        return
    sampled.emit(kind, surface.view.get_document_mouse_position())


func _on_root_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if kind.is_empty() or key == null or key.keycode != KEY_ESCAPE or not key.pressed or key.echo:
        return
    if is_instance_valid(_window) and _window != _root and _window.has_focus():
        _window.unfocusable = true
        _window.grab_focus()
        _window.unfocusable = false
    disarm()
