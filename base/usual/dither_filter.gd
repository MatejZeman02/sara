## Filter > Stylize > Dither, the first finishing effect.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Quantises each channel to a few even steps and spreads the error as a
## pattern, for the print, retro and pixel-art look. The steps are even in the
## encoding the Encoding row picks, the document's own by default, or linear
## light, or a pure gamma, and the choice is
## the record's, so two Dithers in one document can differ. Every
## output texel reads only its own input texel, so this is a point filter: the
## kernel is `dither.gmacs` and keeps the contract on `SaPointPass`.
##
## A finishing filter: [method finishes] answers true, so an attached chain runs
## it after every other record of its node whatever the array order, and it
## quantises the picture the others made rather than being blurred by one.
##
## The pattern is computed in document pixels from the chunk's corner the point
## pass hands its kernel, so it does not swim under a stroke and does not start
## again at a chunk border. Three patterns behind one choice, Bayer's ordered
## grid, interleaved gradient noise and the blue noise tile, and one kernel
## with the pattern as a number rather than three kernels, because a uniform
## set has to cover every binding a compiled kernel keeps and the tile is
## bound on every dispatch anyway. A new Dither starts with interleaved
## gradient noise, which is even and costs a few multiply-adds and no memory,
## and a record saved with a pattern keeps the one it names, so a document
## saved with Bayer reopens with Bayer.
##
## The blue noise tile beside this file is 64 by 64 thresholds made by Ulichney's
## void and cluster, a Gaussian of sigma 1.5 on the torus, ten percent initial
## points from a seeded generator, each rank scaled to 0 to 255 so every grey
## holds sixteen texels. It is this project's own and ships under its licence.
class_name SaDitherFilter
extends SaFilter

const SHADER := "dither"
const KERNEL := "dither"

## The ids of the choice row, in the order the kernel numbers them.
const PATTERNS: Array[String] = ["bayer", "gradient", "blue"]
const PATTERN_TITLES: Array[String] = ["Bayer 8 × 8", "Interleaved gradient noise", "Blue noise"]

## The ids of the Encoding row, the spacing the levels are even steps of. The
## first is the document's own encoding, which a record that names none
## takes, and each other id is a pure power curve of
## `SaTransferFunction`, whose exponent is the one number the kernel is handed.
const ENCODINGS: Array[String] = ["document", "linear", "gamma22", "gamma30"]
const ENCODING_TITLES: Array[String] = ["Document's encoding", "Linear light", "Gamma 2.2", "Gamma 3.0 (cube root)"]

const DEFAULTS := {"levels": 4, "pattern": "gradient", "encoding": "document", "strength": 100}

## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 4
## Where the push constant keeps the spacing's exponent, the last float, which
## the colour space's tail leaves as padding. Nought is the document's own.
const ENCODING_SLOT := 31
## The binding the kernel reads the blue noise tile at.
const TILE_BINDING := 2
## The side of the shipped tile, which the kernel's `TILE` repeats.
const TILE := 64
const TILE_FILE := "dither_blue_noise.png"

## The tile as a storage buffer of floats, made on the first run and shared by
## every record, since nothing ever writes it.
var _tile: SaCompute.Buffer = null


func title() -> String:
    return "Dither"


## Listed under Stylize, beside Edge Detection.
func family() -> StringName:
    return &"stylize"


func sentence() -> String:
    return "Few levels per channel with a pattern between them, for a print or pixel-art look. Always runs last."


func finishes() -> bool:
    return true


func build(ui: SaDialog) -> void:
    var patterns: Array = []
    for index in PATTERNS.size():
        patterns.append({"id": PATTERNS[index], "label": PATTERN_TITLES[index]})
    ui.slider("Levels", 2, 16, DEFAULTS["levels"], {"hard_max": 256})
    ui.dropdown("Pattern", patterns, DEFAULTS["pattern"])
    var encodings: Array = []
    for index in ENCODINGS.size():
        encodings.append({"id": ENCODINGS[index], "label": ENCODING_TITLES[index]})
    ui.dropdown("Encoding", encodings, DEFAULTS["encoding"])
    ui.slider("Strength", 0, 100, DEFAULTS["strength"], {"suffix": "%"})


func run(ctx: SaFilterContext) -> void:
    var tile := _tile_buffer()
    if tile == null:
        return
    var space := ctx.document.color_space if ctx.document != null else null
    var scale := ctx.layer.resolution_scale if ctx.layer != null else 1.0
    ctx.point_pass(SHADER, KERNEL, push_for(parameters(), space, scale), {TILE_BINDING: tile}, ORIGIN_SLOT)


## The 128-byte push constant `dither.gmacs` reads, from *values* in the record's
## own units, on a document stored in *space*, over a node of *scale* texels per
## document pixel. The origin and the corner are zero here, and the runner
## writes them.
static func push_for(values: Dictionary, space: SaColorSpace, scale: float = 1.0) -> PackedFloat32Array:
    var levels := clampf(float(values.get("levels", DEFAULTS["levels"])), 2.0, 256.0)
    var pattern := maxi(PATTERNS.find(String(values.get("pattern", DEFAULTS["pattern"]))), 0)
    var strength := clampf(float(values.get("strength", DEFAULTS["strength"])), 0.0, 100.0) / 100.0
    var push := PackedFloat32Array([levels, strength, float(pattern), scale, 0.0, 0.0, 0.0, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    push[ENCODING_SLOT] = spacing_exponent(String(values.get("encoding", DEFAULTS["encoding"])))
    return push


## The exponent of the pure power curve the Encoding id *encoding* names, the
## gamma the levels are even steps of, or nought for the document's own
## encoding and for an id this build does not offer.
static func spacing_exponent(encoding: String) -> float:
    if ENCODINGS.find(encoding) <= 0:
        return 0.0
    var curve := SaTransferFunction.from_id(StringName(encoding))
    return curve.exponent if curve != null else 0.0


## The shipped tile's thresholds, each rank's grey over 256 plus half a step so
## no threshold sits on zero, TILE by TILE in rows. Empty when the file is not
## there or is not the size the kernel indexes.
static func thresholds() -> PackedFloat32Array:
    var path := (SaDitherFilter as Script).resource_path.get_base_dir().path_join(TILE_FILE)
    var image := Image.new()
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK or image.get_size() != Vector2i(TILE, TILE):
        return PackedFloat32Array()
    image.convert(Image.FORMAT_L8)
    var grey := image.get_data()
    var out := PackedFloat32Array()
    out.resize(grey.size())
    for index in grey.size():
        out[index] = (float(grey[index]) + 0.5) / 256.0
    return out


func _tile_buffer() -> SaCompute.Buffer:
    if _tile != null:
        return _tile
    var values := thresholds()
    if values.is_empty():
        SaProblems.report("SaDitherFilter", "the blue noise tile %s is missing or not %d square." % [TILE_FILE, TILE])
        return null
    var made := SaCompute.Buffer.new(values.to_byte_array())
    if not made.rid.is_valid():
        return null
    _tile = made
    return _tile
