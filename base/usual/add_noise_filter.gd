## Filter > Add Noise: white, film grain, a camera sensor's and salt and pepper,
## one filter with a type, a Monochrome switch, a colour, an amount, a size for
## film grain, how far the grain keeps to the darks, and a seed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `run` serves both forms, the one-shot from the dialog and the filter
## attached under a node of the layer tree. It records a neighbourhood pass of
## radius zero rather than a point pass, because the noise is drawn from the
## document pixel and the seed alone and only the neighbourhood runner tells a
## kernel where its chunk sits in the document. Noise drawn from the chunk-local
## pixel would crawl as an attached filter is evaluated over one dirty
## rectangle and then another. The kernel is `base/shaders/add_noise.gmacs`.
##
## Film grain was a filter of its own, Filter > Noise > Grain, and Random was a
## type of its own, White with one grain for the three channels. Both are read
## through [method record_from], so a document saved with either loads as this
## filter and paints the pixels it painted.
##
## The push constant holds the type, the seed, the switch and the document's
## colour space, which fill its 128 bytes, so the amount, the size, the darks
## and the colour go in a storage buffer of six floats, one per distinct set of
## them, kept as the LUT filter keeps its tables.
class_name SaAddNoiseFilter
extends SaFilter

## The types, in the order the dropdown lists them. The index is what the
## kernel's `kind` reads, and the word is what a record keeps, so a list that
## grows or reorders later still loads an old document's choice.
const KINDS: Array[String] = ["white", "film_grain", "cmos", "salt_and_pepper"]
const KIND_TITLES: Array[String] = ["White", "Film grain", "Sensor (CMOS)", "Salt and pepper"]
## What each type looks like and where it comes from, the dropdown's tooltip
## for its row, in the order of [const KINDS].
const KIND_TOOLTIPS: Array[String] = [
    "Add a fine, even grain, a new value in every pixel, the hiss of a signal with nothing behind it.",
    "Add soft clumps of grain of the size you set, the silver crystals of a film negative, strongest in the midtones.",
    "Add a digital camera's noise, stronger where more light fell, with a faint stripe down each column of pixels.",
    "Scatter single pixels of the grain's colour and of black, the stuck and dead pixels of a faulty sensor.",
]
const SALT_AND_PEPPER := "salt_and_pepper"
const FILM_GRAIN := "film_grain"

const SHADER := "add_noise"
const KERNEL := "add_noise"

## The id Filter > Noise > Grain was registered under, whose records this
## filter reads, and the defaults that filter gave a record that left one out.
const GRAIN_ID: StringName = &"grain"
const GRAIN_DEFAULTS := {"kind": "monochrome", "amount": 30.0, "size": 2.0, "seed": 1.0}
## The id this filter has always had, whose own older records said `random`.
const OWN_ID: StringName = &"add_noise"

## The largest clump a typed value may ask for, in document pixels. The grain
## needs no halo, so this is a painter's bound and not a chunk's.
const HARD_SIZE := 256.0
const DEFAULTS := {
    "kind": "white",
    "monochrome": false,
    "color": Color(1.0, 1.0, 1.0, 1.0),
    "amount": 20.0,
    "size": 2.0,
    "darks": 0.0,
    "seed": 1.0,
}

## Where the storage buffer is bound, the next slot after the target.
const SETTINGS_BINDING := 3
## How many sets of settings are kept, so a slider dragged back and forth
## binds a buffer it has already made.
const KEPT := 8

## How many floats `SaColorSpacePushConstant` writes, and how many are one matrix.
const TAIL_FLOATS := 24
const MATRIX_FLOATS := 9

## The settings buffer of each distinct set of settings, by its floats.
var _buffers: Dictionary[String, SaCompute.Buffer] = {}


func title() -> String:
    return "Add Noise"


## Listed under Noise in the Filter menu and the browser.
func family() -> StringName:
    return &"noise"


func sentence() -> String:
    return (
        "Grain over the paint: white, film grain, a camera sensor's, or salt and pepper,"
        + " in colour or grey, the same pattern for the same seed."
    )


func reads_records_of() -> Array[StringName]:
    return [GRAIN_ID, OWN_ID]


## A record of Grain, or of this filter from before Random left the list, as a
## record of today's rows that paints the same pixels.
func record_from(former_id: StringName, values: Dictionary) -> Dictionary:
    return upgraded(former_id, values)


## *values*, a record of the filter *former_id*, in this filter's own rows. A
## Grain's Monochrome or Colour type is Film grain with the switch on or off,
## and Random is White with the switch on. Anything else is left as it came.
static func upgraded(former_id: StringName, values: Dictionary) -> Dictionary:
    var out := values.duplicate(true)
    if former_id == GRAIN_ID:
        for key: String in GRAIN_DEFAULTS:
            if not out.has(key):
                out[key] = GRAIN_DEFAULTS[key]
        out["monochrome"] = String(out["kind"]) != "color"
        out["kind"] = FILM_GRAIN
    elif String(out.get("kind", "")) == "random":
        out["kind"] = "white"
        out["monochrome"] = true
    return out


func build(ui: SaDialog) -> void:
    var kinds: Array = []
    for index in KINDS.size():
        kinds.append({"id": KINDS[index], "label": KIND_TITLES[index], "tooltip": KIND_TOOLTIPS[index]})
    var kind := ui.dropdown("Type", kinds, DEFAULTS["kind"]).named(&"kind")
    var monochrome := ui.checkbox("Monochrome", DEFAULTS["monochrome"]).named(&"monochrome")
    monochrome.explain("Draw one grain for all three channels, so the grain is grey or the colour below.")
    var others: Array = KINDS.filter(func(word: String) -> bool: return word != SALT_AND_PEPPER)
    kind.dims(monochrome, others)
    # Salt and pepper is grey whatever the switch says, so the switch shows on
    # while it is picked and comes back to where it stood when another is.
    var held := {"was": DEFAULTS["monochrome"]}
    kind.changed.connect(func(picked: Variant) -> void: _show_monochrome(monochrome, String(picked), held))
    ui.color("Colour", DEFAULTS["color"]).named(&"color").explain(
        "Tint the grain. White leaves it as drawn, and a colour keeps its hue in the darks and the lights."
    )
    ui.slider("Amount", 0, 100, int(DEFAULTS["amount"]), {"suffix": "%"})
    var size := ui.slider("Size", 1.0, 16.0, float(DEFAULTS["size"]), {"hard_max": HARD_SIZE, "suffix": " px"})
    kind.hides(size, FILM_GRAIN)
    ui.slider("Keep to darks", 0, 100, int(DEFAULTS["darks"]), {"suffix": "%"}).named(&"darks").explain(
        "Fade the grain out towards the light, as film grain and a camera's noise show most in the shadows."
    )
    ui.slider("Seed", 0, 9999, int(DEFAULTS["seed"]))


## Shows *monochrome* on while *picked* is Salt and pepper, keeping in *held*
## where it stood, and puts that back once another type is picked.
static func _show_monochrome(monochrome: SaPageRow, picked: String, held: Dictionary) -> void:
    if picked == SALT_AND_PEPPER:
        if not held.has("salt"):
            held["was"] = bool(monochrome.read())
            held["salt"] = true
        monochrome.drive(true)
    elif held.has("salt"):
        held.erase("salt")
        monochrome.drive(held["was"])


func run(ctx: SaFilterContext) -> void:
    var space := ctx.document.color_space if ctx.document != null else null
    var values := parameters()
    var buffer := _buffer_for(settings_floats(values))
    if buffer == null:
        return
    ctx.neighbourhood_pass(SHADER, KERNEL, pass_params(values, space), 0, {SETTINGS_BINDING: buffer})


## *values*, the record's own units, as the kernel's params over a document
## stored in *space*, or gamma sRGB when it is null. `origin`, `halo`, `chunk`
## and `scale` are the runner's and are written per dispatch.
static func pass_params(values: Dictionary, space: SaColorSpace = null) -> Dictionary:
    var params := {
        "kind": maxi(KINDS.find(String(values.get("kind", DEFAULTS["kind"]))), 0),
        "seed": clampi(int(values.get("seed", DEFAULTS["seed"])), 0, 9999),
        "monochrome": 1 if bool(values.get("monochrome", DEFAULTS["monochrome"])) else 0,
    }
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    if tail.size() < TAIL_FLOATS:
        return params
    params["doc_to_linear_srgb"] = tail.slice(0, MATRIX_FLOATS)
    params["linear_srgb_to_doc"] = tail.slice(MATRIX_FLOATS, MATRIX_FLOATS * 2)
    params["transfer_slope"] = tail[18]
    params["transfer_threshold"] = tail[19]
    params["transfer_gain"] = tail[20]
    params["transfer_exponent"] = tail[21]
    params["coordinates"] = tail[22]
    return params


## The six floats of the settings buffer for *values*: the amount and the darks
## as fractions, the size in document pixels, then the grain's colour in linear
## light, the picked colour being one a painter saw in sRGB. White is exactly
## one, which the kernel reads as the grain left as it was drawn.
static func settings_floats(values: Dictionary) -> PackedFloat32Array:
    var picked := colour_of(values.get("color", DEFAULTS["color"]))
    var colour := Color(1.0, 1.0, 1.0) if picked.is_equal_approx(Color.WHITE) else picked.srgb_to_linear()
    return PackedFloat32Array(
        [
            clampf(float(values.get("amount", DEFAULTS["amount"])), 0.0, 100.0) / 100.0,
            clampf(float(values.get("size", DEFAULTS["size"])), 1.0, HARD_SIZE),
            clampf(float(values.get("darks", DEFAULTS["darks"])), 0.0, 100.0) / 100.0,
            colour.r,
            colour.g,
            colour.b,
        ]
    )


## *value*, a colour as a record or a row holds it, a `Color` or its text.
static func colour_of(value: Variant) -> Color:
    if value is Color:
        return value
    return Color.from_string(str(value), DEFAULTS["color"])


func _buffer_for(floats: PackedFloat32Array) -> SaCompute.Buffer:
    var key := str(floats)
    if _buffers.has(key):
        return _buffers[key]
    var made := SaCompute.Buffer.new(floats.to_byte_array())
    if not made.rid.is_valid():
        return null
    if _buffers.size() >= KEPT:
        _buffers.erase(_buffers.keys()[0])
    _buffers[key] = made
    return made
