## Filter > Gradient Map, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## How a painter colours a value study: the darks take one colour, the lights
## another and the midtones the ramp between. Each texel's lightness, Oklab L
## read in the document's own space, picks a colour from a ramp, and an amount
## blends the result over the original. The ramp is `SaColorRamp`, the type the
## gradient tool draws with, edited by the same control, so a ramp is at least
## two colours and a stop's alpha is how much of the map applies at that
## lightness. The texel's own alpha is never touched.
##
## It is a point filter. The run records the `gradient_map` point pass, so the
## compositor previews it, Apply walks it as one history step, and attached to a
## layer, a group or the root it runs live while the painting underneath changes.
## The kernel is `gradient_map.gmacs`, beside this file, and the table it reads
## the ramp from is built here at [constant SAMPLES] colours.
##
## **The ramp is the picked pair until the painter edits it.** An empty "ramp"
## value, which is what a dialog opens on, reads as the foreground colour at the
## dark end and the background colour at the light end whenever it is read, so a
## colour picked after the program started is the colour the map opens on. The
## record an Attach files holds the ramp as it was then, never the empty one,
## because a layer's look must not move when the foreground does.
##
## This filter is the facade of `filters/gradient_map`, the feature folder the
## map lives in: the panel and the kernel sit beside it, and the module preloads
## this file only.
class_name SaGradientMapFilter
extends SaFilter

## The shader file, by the key the shader index files it under: the module's
## folder and the file's name.
const SHADER := "sara-base-modules/gradient_map"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 1
## Where the kernel binds the ramp's table.
const TABLE_BINDING := 2
## How many colours the table holds, the first on the ramp's first stop and the
## last on its last. Two hundred and fifty-six steps are under a hundredth of
## the lightness each, and the kernel reads between neighbours.
const SAMPLES := 256
## The key the ramp is kept under: an empty list for the picked pair, otherwise
## `SaColorRamp.to_array`.
const RAMP_KEY := &"ramp"
## The key of the amount, a percentage as the slider shows it.
const AMOUNT_KEY := &"amount"
const AMOUNT_DEFAULT := 100.0


func title() -> String:
    return "Gradient Map"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Colour a picture by its lightness: darks take a ramp's first colour, lights its last, midtones what lies between."


func id() -> StringName:
    return &"gradient_map"


func action_name() -> StringName:
    return &"filter_gradient_map"


func build(ui: SaDialog) -> void:
    # An empty list is the picked pair, and a record that never named a ramp
    # reads the same, so an older file or a bare Attach asks nothing of it.
    ui.parameter_value(RAMP_KEY, [], [])
    ui.custom("", _make_panel).named(&"ramp")
    ui.slider("Amount", 0, 100, int(AMOUNT_DEFAULT), {"suffix": "%"})
    ui.thumbnail()
    ui.canvas_preview()
    ui.apply_cancel()
    ui.cancel_button.tooltip_text = tr("Close and leave the layer as it was. The preview goes with it.")
    ui.apply_button.tooltip_text = tr("Apply to the active layer.")


func run(ctx: SaFilterContext) -> void:
    var recorded := record(values(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## What the dialog holds as the pass takes it, which is what a read prints and
## what Apply commits: the ramp as a list of stops, the picked pair when the
## painter has not edited it, and the amount as a percentage.
func values() -> Dictionary:
    var out := parameters()
    out[String(RAMP_KEY)] = ramp_of(out).to_array()
    return out


## An Attach files the ramp as it stands, so the foreground colour moving later
## does not move the layer.
func filed_as(own_key: StringName) -> SaAttachedFilter:
    return SaAttachedFilter.new(own_key, values())


## The `adjust` step's door, over *document*'s active layer as one step with no
## dialog. *spec* names the ramp as `"ramp"`, a list of stops, or as `"colours"`,
## hex strings spread evenly from the dark end to the light, and `"amount"` is a
## percentage. Reached by name so the harness names no module class.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null or document.active_layer == null or GlobalShaderCompiler.get_rd() == null:
        return false
    var recorded := record(spec_values(spec), document.color_space)
    if recorded == null:
        return false
    # The walk asks each chunk's texture for its format, so none is set here.
    return SaFilterApply.apply_point(document, document.active_layer, recorded, SaCompute.new(SHADER), title())


## The values a step's *spec* names, the ramp as stops whichever way it was
## written and the amount defaulting to all of it.
static func spec_values(spec: Dictionary) -> Dictionary:
    var ramp: SaColorRamp = null
    if spec.has("colours"):
        ramp = evenly(spec["colours"] as Array)
    else:
        ramp = ramp_of(spec)
    return {String(RAMP_KEY): ramp.to_array(), String(AMOUNT_KEY): float(spec.get("amount", AMOUNT_DEFAULT))}


## The ramp *held_values* holds under [constant RAMP_KEY]: its stops, or the picked
## pair when it holds none that read as a ramp.
static func ramp_of(held_values: Dictionary) -> SaColorRamp:
    var held: Variant = held_values.get(String(RAMP_KEY), [])
    if held is Array and not (held as Array).is_empty():
        return SaColorRamp.from_array(held as Array, picked_pair())
    return picked_pair()


## The foreground colour at the dark end and the background colour at the light
## end, both opaque: what the gradient tool opens with, without its remembered
## alphas, since a map's alpha is how much of it applies and a fade is not the
## default of one.
static func picked_pair() -> SaColorRamp:
    return SaColorRamp.from_pair(Color(SaInHand.Pair.foreground(), 1.0), Color(SaInHand.Pair.background(), 1.0))


## A ramp through *colours*, hex strings or colours, spread evenly from 0 to 1.
## One colour is the pair of it and itself, so a ramp always has two stops.
static func evenly(colours: Array) -> SaColorRamp:
    var picked: Array[Color] = []
    for entry: Variant in colours:
        if entry is Color:
            picked.append(entry)
        elif entry is String and Color.html_is_valid(String(entry)):
            picked.append(Color.html(String(entry)))
    if picked.is_empty():
        return picked_pair()
    if picked.size() == 1:
        return SaColorRamp.from_pair(picked[0], picked[0])
    var ramp := SaColorRamp.new()
    for i in picked.size():
        ramp.stops.append({"position": float(i) / float(picked.size() - 1), "color": picked[i]})
    return ramp


## *ramp* run end to end, its stops' positions mirrored and their colours kept,
## so the dark end takes what the light end had.
static func reversed(ramp: SaColorRamp) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for i in range(ramp.size() - 1, -1, -1):
        out.append({"position": 1.0 - ramp.position_of(i), "color": ramp.color_of(i)})
    return out


## The table the kernel reads: [constant SAMPLES] colours of *ramp* from its
## start to its end, each as Oklab L, a and b and then alpha, in *space*'s gamut.
static func table_for(ramp: SaColorRamp, space: SaColorSpace) -> PackedFloat32Array:
    return ramp.oklab_samples(SAMPLES, space)


## The 112-byte push constant `gradient_map.gmacs` reads: *percent* as the
## amount, a fraction of one, the region's origin, which the runner writes at
## [constant ORIGIN_SLOT], the table's length, then the colour space tail
## exactly as `SaColorSpacePushConstant` writes it.
static func push_for(percent: float, space: SaColorSpace) -> PackedFloat32Array:
    var push := PackedFloat32Array([clampf(percent, 0.0, 100.0) / 100.0, 0.0, 0.0, float(SAMPLES)])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push


## *held_values* on a document stored in *space*, as the point pass the compositor
## previews and Apply walks. Null when the table's buffer could not be made.
##
## Every record gets a buffer of its own, because the filter chain keeps a
## record per attached filter and the registry has one instance of each filter,
## so a buffer written in place would show the last layer's ramp on every layer.
static func record(held_values: Dictionary, space: SaColorSpace) -> SaPointPass:
    var table := SaCompute.Buffer.new(table_for(ramp_of(held_values), space).to_byte_array())
    if not table.rid.is_valid():
        return null
    var percent := float(held_values.get(String(AMOUNT_KEY), AMOUNT_DEFAULT))
    return SaPointPass.new(SHADER, "gradient_map", push_for(percent, space), {TABLE_BINDING: table}, ORIGIN_SLOT)


## What `ui.custom` calls: the panel, which writes the ramp and asks for a rerun
## whenever it moves.
func _make_panel(rerun: Callable) -> Control:
    var panel := SaGradientMapPanel.new()
    panel.set_ramp(ramp_of(parameters()))
    panel.changed.connect(
        func() -> void:
            write_parameter(RAMP_KEY, panel.ramp.to_array())
            rerun.call()
    )
    return panel
