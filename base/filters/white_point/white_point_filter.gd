## Filter > White Point, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## How a painter takes a cast out of a picture: the dialog's eyedropper picks a
## texel that should have been neutral, a grey card or a white shirt in warm
## light, and every colour is moved by the change that makes that one a grey of
## its own luminance. A strength takes it part of the way. Auto, beside the
## eyedropper, finds that colour in the whole picture instead, from its
## surfaces or from its edges, through `SaWhitePointEstimate`, and writes it
## where a pick goes.
##
## **The change is a von Kries scaling in Bradford's cone space**, the white
## point adaptation a colour space conversion already does through
## `SaColorSpace.adaptation`, here from the picked colour's chromaticity to
## the document's white. The three cone responses of every colour are scaled
## by the gains that carry the picked colour's to those of the grey with its
## luminance, so the picked colour lands on that grey exactly, a white moves by
## the same three gains, and a colour keeps its luminance only as far as the
## cones say it should. It is done in linear light: the kernel decodes the
## document's curve, or reads Oklab back to linear sRGB, multiplies by one
## matrix and encodes again. Nothing clamps, so a colour above white is scaled
## like any other and a negative channel keeps its sign.
##
## **The picked colour is a parameter**, as light-linear sRGB under "picked",
## so a record keeps its correction while the picture under it changes, a
## saved document keeps it, and a document converted to another space reads
## the same colour. An empty list is nothing picked, which changes nothing, and
## so is a colour no cone sees, black above all, which no gain makes grey.
##
## **Two sliders move that colour by hand**, Blue to yellow along Oklab's b and
## Green to magenta along its a, in hundredths of Oklab. They start from the
## pick, or from the document's white when nothing usable is picked, so they
## work alone as a manual correction and as a fine tune of a pick or of what
## Auto found. A slider names where the picture goes, so towards yellow moves
## the colour made grey towards blue, and the picture warms. They are kept
## beside the pick and read nought when a record never named them, so a
## document saved before them draws as it did. The move is made at a luminance
## of one, so one step is one change of tint however bright the pick is, and
## the von Kries scaling then takes the moved colour to the grey of its own
## luminance as it takes a pick. Strength scales the whole of it.
##
## It is a point filter. The run records the `white_point` point pass, so the
## compositor previews it, Apply walks it as one history step, and attached to
## a layer, a group or the root it runs live. The kernel is `white_point.gmacs`
## beside this file.
##
## This filter is the facade of `filters/white_point`, the feature folder the
## filter lives in, beside Levels' and Gradient Map's: the panel, the estimate
## Auto makes and the two kernels sit beside it, and the module preloads this
## file only.
class_name SaWhitePointFilter
extends SaFilter

## The shader file, by the key the shader index files it under: the module's
## folder and the file's name.
const SHADER := "sara-base-modules/white_point"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0
## How many floats the push constant holds, 80 bytes.
const PUSH_FLOATS := 20
## The key the picked colour is kept under: three light-linear sRGB floats, or
## an empty list for none.
const PICKED_KEY := &"picked"
## The key of the strength, a percentage as the slider shows it.
const STRENGTH_KEY := &"strength"
const STRENGTH_DEFAULT := 100.0
## The keys of the two tint sliders, each in hundredths of Oklab, positive
## towards yellow along b and towards magenta along a.
const YELLOW_KEY := &"blue_to_yellow"
const MAGENTA_KEY := &"green_to_magenta"
## How far either slider reaches each side of nought, in hundredths of Oklab.
## A tungsten lamp's white stands 14.5 along b and 6.8 along a from D65's, so
## the reach takes such a cast out with nothing picked. It stops short of 24
## towards blue, where the blue cone of the white moved the other way sees
## nothing and no gain makes it grey.
const TINT_REACH := 20.0
## The smallest cone response a picked colour may have and still be made grey.
## Below it the gain would carry noise a thousandfold, so the filter leaves the
## picture alone rather than flood it.
const LEAST_RESPONSE := 1e-5

## A context holding the surfaces of the door the module was registered
## through and no registry, which the panel asks for the main canvas. Null in a
## suite that builds the filter bare.
var _surfaces: SaContext = null


## The filter, with *surfaces* a context that lists the surfaces.
func _init(surfaces: SaContext = null) -> void:
    _surfaces = surfaces


## The filter the module registers through *ctx*. Handed a context of the
## surface provider alone, as the stamp brush binds its eraser toggle to one,
## because *ctx* holds the filter registry, which would hold this filter, and
## the ring would never be freed.
static func over(ctx: SaContext) -> SaWhitePointFilter:
    return SaWhitePointFilter.new(SaContext.new(Callable(), ctx.surface_provider))


func title() -> String:
    return "White Point"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


## What a row's tooltip and the browser's detail say. It names white balance in
## words, the name Lightroom and Resolve give this control, so a search for it
## finds White Point and the painter reads that this is where it is set.
func sentence() -> String:
    return (
        "Sets the white balance: pick a colour that should be neutral, or let Auto find it, and the cast"
        + " it carries is taken out of the whole picture in linear light."
    )


func id() -> StringName:
    return &"white_point"


func action_name() -> StringName:
    return &"filter_white_point"


func build(ui: SaDialog) -> void:
    # An empty list is nothing picked, and a record that never named a colour
    # reads the same, so a bare Attach changes nothing until a pick.
    ui.parameter_value(PICKED_KEY, [], [])
    ui.custom("", _make_panel).named(&"white_point")
    var fine := {"step": 0.1, "decimals": 1}
    ui.slider("Blue to yellow", -TINT_REACH, TINT_REACH, 0.0, fine).named(YELLOW_KEY)
    ui.slider("Green to magenta", -TINT_REACH, TINT_REACH, 0.0, fine).named(MAGENTA_KEY)
    ui.slider("Strength", 0, 100, int(STRENGTH_DEFAULT), {"suffix": "%"})
    ui.thumbnail()
    ui.canvas_preview()
    ui.apply_cancel()
    ui.cancel_button.tooltip_text = tr("Close and leave the layer as it was. The preview goes with it.")
    ui.apply_button.tooltip_text = tr("Apply to the active layer.")


func run(ctx: SaFilterContext) -> void:
    var recorded := record(parameters(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## The `adjust` step's door, over *document*'s active layer as one step with no
## dialog. *spec* names the colour as `"picked"`, three light-linear sRGB
## floats, or as `"stored"`, the three numbers a texel of *document* holds,
## `"strength"` is a percentage, and `"blue_to_yellow"` and `"green_to_magenta"`
## are the two sliders. Reached by name so the harness names no module class.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null or document.active_layer == null or GlobalShaderCompiler.get_rd() == null:
        return false
    var recorded := record(spec_values(spec, document.color_space), document.color_space)
    if recorded == null:
        return false
    return SaFilterApply.apply_point(document, document.active_layer, recorded, SaCompute.new(SHADER), title())


## The values a step's *spec* names on a document in *space*, the colour as
## light-linear sRGB whichever way it was written, the strength defaulting to
## all of it and the sliders to nought.
static func spec_values(spec: Dictionary, space: SaColorSpace) -> Dictionary:
    var picked: Array = []
    if spec.has("stored"):
        var stored := spec["stored"] as Array
        if stored.size() >= 3:
            picked = as_list(linear_of(Color(float(stored[0]), float(stored[1]), float(stored[2])), space))
    else:
        picked = as_list(picked_of({String(PICKED_KEY): spec.get("picked", [])}))
    return {
        String(PICKED_KEY): picked,
        String(STRENGTH_KEY): float(spec.get("strength", STRENGTH_DEFAULT)),
        String(YELLOW_KEY): tint_of(spec, YELLOW_KEY),
        String(MAGENTA_KEY): tint_of(spec, MAGENTA_KEY),
    }


## The picked colour *held_values* holds, light-linear sRGB, or NAN in every
## channel when it holds none that reads as three numbers.
static func picked_of(held_values: Dictionary) -> Vector3:
    var held: Variant = held_values.get(String(PICKED_KEY), [])
    if not held is Array or (held as Array).size() < 3:
        return Vector3(NAN, NAN, NAN)
    var list := held as Array
    for channel in 3:
        if not (list[channel] is float or list[channel] is int):
            return Vector3(NAN, NAN, NAN)
    return Vector3(float(list[0]), float(list[1]), float(list[2]))


## The tint slider *key* of *held_values*, nought when it holds no number,
## which is what a record saved before the sliders reads.
static func tint_of(held_values: Dictionary, key: StringName) -> float:
    var held: Variant = held_values.get(String(key), 0.0)
    return float(held) if held is float or held is int else 0.0


## *colour* as the list a record keeps, empty for a colour that is not one.
static func as_list(colour: Vector3) -> Array:
    if not colour.is_finite():
        return []
    return [colour.x, colour.y, colour.z]


## The stored colour *stored* of a document in *space* as light-linear sRGB:
## the curve taken off and the gamut turned to sRGB's, or for an Oklab
## document its coordinates read back to light.
static func linear_of(stored: Color, space: SaColorSpace) -> Vector3:
    var base := Vector3(stored.r, stored.g, stored.b)
    if space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return SaOklab.to_linear_srgb(base)
    var curve := space.transfer if space != null and space.transfer != null else SaTransferFunction.srgb()
    var light := Vector3(curve.decode(base.x), curve.decode(base.y), curve.decode(base.z))
    return space.to_linear_srgb_matrix() * light if space != null else light


## The luminance of light-linear sRGB *colour*, CIE Y, which the grey the
## picked colour lands on keeps.
static func luminance(colour: Vector3) -> float:
    return (SaColorSpace.linear_srgb().rgb_to_xyz() * colour).y


## Whether *colour*, light-linear sRGB, can be made grey: every Bradford cone
## sees it, so each gain is a number and positive.
static func can_neutralise(colour: Vector3) -> bool:
    if not colour.is_finite():
        return false
    var xyz := SaColorSpace.linear_srgb().rgb_to_xyz() * colour
    if xyz.y < LEAST_RESPONSE:
        return false
    for row: Vector3 in SaColorSpace.BRADFORD_ROWS:
        if row.dot(xyz) < LEAST_RESPONSE:
            return false
    return true


## The colour the correction makes grey, light-linear sRGB: *picked* moved
## *yellow* hundredths along Oklab's b and *magenta* along its a, both the other
## way, so the picture goes the way the sliders name. From the document's
## white, linear sRGB's (1, 1, 1), when *picked* cannot be made grey. Moved at
## a luminance of one and handed back at the luminance it started at. With
## both sliders at nought it is *picked* itself, untouched, so a record that
## never named them dispatches the matrix it always did.
static func neutral(picked: Vector3, yellow: float, magenta: float) -> Vector3:
    if yellow == 0.0 and magenta == 0.0:
        return picked
    var start := picked if can_neutralise(picked) else Vector3.ONE
    var bright := luminance(start)
    var lab := SaOklab.from_linear_srgb(start / bright)
    lab.y -= magenta / 100.0
    lab.z -= yellow / 100.0
    var moved := SaOklab.to_linear_srgb(lab)
    var landed := luminance(moved)
    return moved * (bright / landed) if landed > LEAST_RESPONSE else moved


## The whole correction in light-linear sRGB: the von Kries scaling that takes
## *picked* to the grey of its own luminance, at *strength*, a fraction of one,
## the rest of the way the identity. The identity when nothing is picked or
## the colour cannot be made grey.
static func correction(picked: Vector3, strength: float) -> Basis:
    if not can_neutralise(picked):
        return Basis.IDENTITY
    var srgb := SaColorSpace.linear_srgb()
    var xyz := srgb.rgb_to_xyz() * picked
    var total := xyz.x + xyz.y + xyz.z
    var chromaticity := Vector2(xyz.x / total, xyz.y / total)
    var full := srgb.xyz_to_rgb() * SaColorSpace.adaptation(chromaticity, srgb.white) * srgb.rgb_to_xyz()
    var share := clampf(strength, 0.0, 1.0)
    var none := Basis.IDENTITY
    return Basis(none.x.lerp(full.x, share), none.y.lerp(full.y, share), none.z.lerp(full.z, share))


## The correction as the kernel multiplies by it on a document in *space*: in
## the document's own linear RGB for an RGB document, and in linear sRGB for an
## Oklab one, whose kernel reads its coordinates back to linear sRGB.
static func document_matrix(picked: Vector3, strength: float, space: SaColorSpace) -> Basis:
    var balance := correction(picked, strength)
    if space == null or space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return balance
    return space.from_linear_srgb_matrix() * balance * space.to_linear_srgb_matrix()


## The 80-byte push constant `white_point.gmacs` reads: the region's origin,
## which the runner writes at [constant ORIGIN_SLOT], the coordinate system and
## a spare, the matrix by column, the document's curve, and three spares.
static func push_for(matrix: Basis, space: SaColorSpace) -> PackedFloat32Array:
    var held := space if space != null else SaColorSpace.srgb()
    var push := PackedFloat32Array([0.0, 0.0, float(held.coordinates), 0.0])
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(matrix):
        push.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    var curve := held.transfer if held.transfer != null else SaTransferFunction.linear()
    push.append_array(curve.to_params())
    push.append_array(PackedFloat32Array([0.0, 0.0, 0.0]))
    assert(push.size() == PUSH_FLOATS, "the white point's push constant is the wrong size")
    return push


## *held_values* on a document stored in *space*, as the point pass the
## compositor previews and Apply walks.
static func record(held_values: Dictionary, space: SaColorSpace) -> SaPointPass:
    var percent := float(held_values.get(String(STRENGTH_KEY), STRENGTH_DEFAULT))
    var moved := neutral(picked_of(held_values), tint_of(held_values, YELLOW_KEY), tint_of(held_values, MAGENTA_KEY))
    var matrix := document_matrix(moved, percent / 100.0, space)
    return SaPointPass.new(SHADER, "white_point", push_for(matrix, space), {}, ORIGIN_SLOT)


## What `ui.custom` calls: the panel, which writes the picked colour and asks
## for a rerun whenever a pick lands.
func _make_panel(rerun: Callable) -> Control:
    var panel := SaWhitePointPanel.new(_surfaces)
    panel.show_picked(picked_of(parameters()))
    panel.changed.connect(
        func() -> void:
            write_parameter(PICKED_KEY, as_list(panel.picked))
            rerun.call()
    )
    return panel
