## Filter > Tone > Tonemap: the view's rolloff written into a layer, and a
## display transform made for photographs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two methods behind one Method row. **Paper** is the view's operator written
## into the paint: the peak channel brought to
## white and no further, chroma given up in Oklab above the knee with the hue
## held, and the same gamut map. **OpenDRT** is a photographic display transform,
## Jed Smith's OpenDRT v1.1.0, ported to `opendrt.gmacs` and driven by the row
## set `SaOpenDrtParameters` owns.
##
## **A record saved before the Method row opens as Paper**, since the row's
## default is Paper and a record that names no method reads that default. This
## is also why Knee and Desaturation keep their keys and their ranges.
##
## **Paper is the view's operator and keeps the view's two numbers.** They sit
## in the filter's own record and are not read from Preferences > Display, so a
## saved document looks the same on another machine whichever way that
## machine's view is tuned. The kernel is `tonemap.gmacs`, which says how it
## reads the document's encoding.
##
## **OpenDRT forms the picture**, a display transform and not a change to the
## paint, so `forms_the_picture` answers true and the view does not lay its own
## rolloff over the result. Paper answers true as well, because at its defaults
## it is the same operator, and a rolloff over it would give up the chroma
## between the knee and white twice, which is the double rolloff the View menu's
## row steps aside from. A Tonemap on one layer leaves the view alone, since
## the other layers still need it, and the dialog says so in a muted line.
##
## Every output texel of either method reads only its own input texel, so this
## is a point filter with no halo: it records a point pass, the compositor
## previews it and Apply walks it, and it declares no radius.
##
## The DCTL's own banner stands verbatim at the head of `opendrt.gmacs` with
## Sara's licence line beside it, and THIRDPARTY.txt at the root of the source
## names the port.
class_name SaTonemapFilter
extends SaFilter

## The shader files, by the key the shader index files them under, and the entry
## point each one runs.
const SHADER := "tonemap"
const KERNEL := "tonemap"
const OPENDRT_SHADER := "opendrt"
const OPENDRT_KERNEL := "opendrt"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0
## Where the OpenDRT push constant keeps whether Oklab carries the hue.
const OKLAB_SLOT := 2
## The binding `opendrt.gmacs` reads its parameter block at: the third resource
## after the canvas and the mask.
const SETTINGS_BINDING := 2

## The view's own defaults, the knee and desaturation Preferences > Display
## starts at, and the ranges its sliders hold them in.
const DEFAULTS := {"knee": 1.0, "desaturation": 0.15}
## The knee's ends, as two floats and not a `Vector2`: a Vector2 holds 32-bit
## floats, and a slider whose bottom was 0.05 in 32 bits dragged to
## 1.00000000075 rather than to the default. The top is the view's own, a knee
## of 4.0 in light, because a knee higher than that would leave the rolloff
## nearly nothing to give up on the lights a painter stacking passes reaches.
const KNEE_LOW := 0.05
const KNEE_TOP := 4.0
const DESATURATION_RANGE := Vector2(0.0, 1.0)

## The parameter block the OpenDRT kernel reads, made on the first OpenDRT run
## and rewritten in place: a preview reruns on every slider frame, and a fresh
## 288-byte buffer each time would churn the rendering device for nothing.
var _settings: SaCompute.Buffer = null


func title() -> String:
    return "Tonemap"


## Listed under Tone, beside the adjustments a painter sets by hand.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return (
        "Bring the highlights above the knee under white with their hue held, as Tonemap Highlights shows them,"
        + " in the paint, or form the picture with OpenDRT, which clips to the display's range as Resolve's does"
        + " when Oklab hue is off."
    )


## Yes at either method, and why is on the class.
func forms_the_picture() -> bool:
    return true


func build(ui: SaDialog) -> void:
    var head := ui.section("Method")
    head.note(
        tr(
            (
                "A Tonemap on one layer, or attached to one, shapes that layer alone,"
                + " so the view still lays its own rolloff over the picture."
            )
        )
    )
    store.declare_choice(&"method", SaOpenDrtParameters.METHOD_PAPER, SaOpenDrtParameters.METHOD_IDS)
    var method := SaOpenDrtParameters.bound(head.choice("Method", SaOpenDrtParameters.METHODS), store, &"method")
    store.declare_number(&"knee", float(DEFAULTS["knee"]), KNEE_LOW, KNEE_TOP)
    var knee := SaOpenDrtParameters.bound(head.slider("Knee", KNEE_LOW, KNEE_TOP).step(0.01).decimals(2), store, &"knee")
    knee.explain("Where the highlight rolloff begins, in linear light. Under it the paint is left as stored.")
    store.declare_number(&"desaturation", float(DEFAULTS["desaturation"]), DESATURATION_RANGE.x, DESATURATION_RANGE.y)
    var desaturation := SaOpenDrtParameters.bound(
        head.slider("Desaturation", DESATURATION_RANGE.x, DESATURATION_RANGE.y).step(0.01).decimals(2), store, &"desaturation"
    )
    desaturation.explain("How much chroma a colour above the knee gives up on its way to white, its hue held.")
    # The two pictures Preferences > Display draws the view's roll-off with,
    # since Paper is that roll-off written into a layer.
    var pictures := ui.rolloff(head, knee, desaturation)

    var rows := SaOpenDrtParameters.declare_rows(ui, store)
    # A row is shown while the Method row holds the entry named here, so the
    # OpenDRT rows belong to OpenDRT and the Paper rows and pictures to Paper. A
    # section left with no row on screen goes with them, which `SaPage` does.
    for key: StringName in rows:
        method.hides(rows[key], SaOpenDrtParameters.METHOD_OPENDRT)
    method.hides(knee, SaOpenDrtParameters.METHOD_PAPER)
    method.hides(desaturation, SaOpenDrtParameters.METHOD_PAPER)
    for picture: SaPageRow in pictures:
        method.hides(picture, SaOpenDrtParameters.METHOD_PAPER)

    rows[&"look_preset"].explain(
        "Fill every slider with a look preset's values, the DCTL's own seven. A slider moved afterwards keeps its own."
    )
    rows[&"tonescale_preset"].explain(
        "Fill the tonescale rows with a tonescale preset's values. The first entry leaves the look preset's own."
    )
    # Named so a scenario can rest the pointer on the switch and photograph its
    # tooltip, which says that the switch off clips the paint as Resolve does.
    rows[&"oklab_hue"].node("OklabHueSwitch").explain(
        tr(
            (
                "Find the hue windows by Oklab hue angle and fit what purity compression leaves outside the "
                + "display's cube with the Oklab gamut map. Off computes what OpenDRT's DCTL computes, so a preset "
                + "can be matched against Resolve, and like Resolve's it clips every channel to the display's range, "
                + "0 to 1, in the layer."
            )
        )
    )

    # A preset writes the whole parameter set at once rather than a slider at a
    # time, which is one `changed` and one re-read of the dialog.
    ui.row_changed.connect(_preset_moved)


func run(ctx: SaFilterContext) -> void:
    var doc := ctx.document
    var space := doc.color_space if doc != null else null
    var white := doc.blend_reference_white if doc != null else 1.0
    var values := parameters()
    if int(values.get("method", SaOpenDrtParameters.METHOD_PAPER)) == SaOpenDrtParameters.METHOD_OPENDRT:
        var settings := _settings_buffer(values)
        if settings == null:
            return
        ctx.point_pass(
            OPENDRT_SHADER, OPENDRT_KERNEL, open_drt_push(values, space, white), {SETTINGS_BINDING: settings}, ORIGIN_SLOT
        )
        return
    ctx.point_pass(SHADER, KERNEL, push_for(values, space, white), {}, ORIGIN_SLOT)


## The OpenDRT parameter block, 72 floats, at the binding the kernel reads.
##
## One buffer over the filter's life and `update` rather than a new one each
## run, because the uniform set the pass built stays valid against a buffer of
## the same size.
func _settings_buffer(values: Dictionary) -> SaCompute.Buffer:
    var bytes := SaOpenDrtParameters.pack(values).to_byte_array()
    if _settings == null:
        var made := SaCompute.Buffer.new(bytes)
        if not made.rid.is_valid():
            SaProblems.report("SaTonemapFilter", tr("the OpenDRT parameter block could not be made."))
            return null
        _settings = made
        return _settings
    _settings.update(bytes)
    return _settings


## A preset was picked, so its own rows are written and everything else is left
## where it was. The DCTL's look preset carries its tonescale, so picking one
## puts the Tonescale Preset row back to its first entry, which writes nothing
## of its own.
func _preset_moved(key: StringName, value: Variant) -> void:
    if key == &"look_preset":
        _fill(SaOpenDrtParameters.look_values(int(value)))
        store.write(&"tonescale_preset", SaOpenDrtParameters.TONESCALE_FROM_LOOK)
        return
    if key == &"tonescale_preset":
        _fill(SaOpenDrtParameters.tonescale_values(int(value)))


## *values* written over every parameter the store holds, in one `take`, so a
## preset is one change for the dialog to re-read.
func _fill(values: Dictionary) -> void:
    if values.is_empty():
        return
    var whole := store.all()
    for name: String in values:
        whole[name] = values[name]
    store.take(whole)


## The 128-byte push constant `tonemap.gmacs` reads, from *values* in the
## record's own units, on a document stored in *space* whose reference white is
## *white*: the region's origin, which the runner writes at
## [constant ORIGIN_SLOT], the knee, the desaturation, the white, three spares,
## then the colour space tail exactly as `SaColorSpacePushConstant` writes it.
static func push_for(values: Dictionary, space: SaColorSpace, white: float) -> PackedFloat32Array:
    var knee := clampf(float(values.get("knee", DEFAULTS["knee"])), KNEE_LOW, KNEE_TOP)
    var desaturation := clampf(
        float(values.get("desaturation", DEFAULTS["desaturation"])), DESATURATION_RANGE.x, DESATURATION_RANGE.y
    )
    var push := PackedFloat32Array([0.0, 0.0, knee, desaturation, white, 0.0, 0.0, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push


## The 128-byte push constant `opendrt.gmacs` reads: the region's origin, which
## the runner writes at [constant ORIGIN_SLOT], whether Oklab carries the hue,
## the white, four spares, then the colour space tail. The seventy-two sliders
## are the storage buffer, which a push constant is too small for.
static func open_drt_push(values: Dictionary, space: SaColorSpace, white: float) -> PackedFloat32Array:
    var push := PackedFloat32Array([0.0, 0.0, 1.0 if bool(values.get("oklab_hue", true)) else 0.0, white, 0.0, 0.0, 0.0, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push
