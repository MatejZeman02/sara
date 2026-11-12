## One pattern: a name, a texture in VRAM, where it comes from and how many
## document texels one repeat spans.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its source is one of three things, decided by the file's extension:
## a picture, `.png` or `.exr`, read as a grey mask by [SaPatternImage], a
## `.pat`, GIMP's own format and what Krita's bundled papers are, decoded by
## [SaPatternPat] and then read by that same mask rule, or a `.gmacs` pixel
## function run through the pixel-function door by [SaPatternKernel] into a
## texture of whatever size is asked. The patterns Sara ships in
## `res://patterns` are kernels. Both brush engines read them,
## which is why this is the door's and not the stamp's.
##
## **The texture is coverage, `r32f`, one where a dab paints in full.** The
## same format and the same polarity as the tip mask in `sa_brush_tip_mask.gd`
## and the one by one stand-in binding 4 of `dab.gmacs` holds without a
## pattern, so the multiply reads a pattern the way it reads the stand-in and
## a texture four times smaller than a colour one.
##
## **Made when asked, once.** A store lists dozens of patterns and a painter
## picks one, so nothing is compiled, read or uploaded until [method texture]
## is called, and the answer is kept for as long as this object lives. A
## generated pattern answers a second size through [method generate] without
## touching the cache, which is what a chooser draws its thumbnails from.
##
## A preset carries a pattern by its name, as an additive key on the settings
## resource, and asks the store for the object: nothing here is a `Resource`,
## because a texture cannot be saved into a `.tres` and a path inside one would
## break the moment a painter renamed a file.
##
## **A file that could not be read is read once**. The refusal is kept on this
## object, so the second ask answers the first ask's null with no file open,
## and it is told to the store this came from, which remembers it against the
## file on disk and hands it back to the pattern made for the same path after a
## rescan. A pattern built without a store, which is a test over a scratch
## folder, keeps its own refusal and tells nobody.
class_name SaPattern
extends RefCounted

## What the source is, read off its extension at construction.
enum Kind { IMAGE, KERNEL }

## How many document texels one repeat of a pattern spans when its file does
## not say, which is one chunk. Also the size a generated pattern's own texture
## is made at, so a pattern tiles at one texel per texel by default.
const DEFAULT_TILE: int = 256

## The extensions each loader takes, lower case.
const IMAGE_EXTENSIONS: Array[String] = ["png", "exr"]
const KERNEL_EXTENSION: String = "gmacs"

## GIMP's own pattern format, which Godot's `Image` cannot decode and
## [SaPatternPat] reads instead. It is a picture like the other two, so
## it takes the [enum Kind] IMAGE branch and the same mask rule, and only
## the decoding differs.
const PAT_EXTENSION: String = "pat"

## What a chooser and a preset call it.
var name: String = ""

## The file the texture comes from, a picture or a pixel function.
var source: String = ""

var kind: Kind = Kind.KERNEL

## The kernel's values over its declared defaults, empty for a picture and for
## a kernel run as written.
var uniforms: Dictionary[String, Variant] = {}

## Document texels one repeat spans.
var tile: int = DEFAULT_TILE

## Why there is no texture. Empty until a load or a generation failed, and the
## only thing worth reading when it is not.
var error: String = ""

## The texture at the tile size, made on the first ask and kept.
var _texture: SaTexture = null

## The picture a file source decoded to, kept so a thumbnail is a resize
## rather than a second read.
var _mask: Image = null

## The kernel loader for a `.gmacs` source, made on the first ask and kept,
## because it holds the compiled wrapper.
var _kernel: SaPatternKernel = null

## The store this was listed by, told when the file cannot be read and asked
## whether it already knows. Weak, because the store holds this object and a
## strong back-pointer to an owner is a ring, two `RefCounted`s that never
## reach nought. Null for a pattern made
## by hand.
var _store: WeakRef = null

## Whether the file was asked for and refused, so no ask after the first opens
## it again. Separate from [member error], which [method generate] also writes
## for a picture asked for a second size, and that is no reason to stop
## reading the picture.
var _refused: bool = false


func _init(
    pattern_name: String,
    source_path: String,
    tile_size: int = DEFAULT_TILE,
    values: Dictionary[String, Variant] = {},
    store: SaPatternStore = null
) -> void:
    name = pattern_name
    source = source_path
    tile = maxi(tile_size, 1)
    uniforms = values.duplicate()
    kind = Kind.KERNEL if source_path.get_extension().to_lower() == KERNEL_EXTENSION else Kind.IMAGE
    _store = weakref(store) if store != null else null


## Whether the texture comes out of a kernel rather than a file.
func is_generated() -> bool:
    return kind == Kind.KERNEL


## The pattern's texture: a generated one at its tile size, a picture at the
## picture's own size. Null when the source cannot be read or compiled, with
## [member error] saying why. The second call answers the first call's texture.
func texture() -> SaTexture:
    if _texture != null and _texture.rid.is_valid():
        return _texture
    if is_generated():
        _texture = generate(Vector2i(tile, tile))
    else:
        _texture = SaPatternImage.upload(_read_mask())
    return _texture


## The pixel size of the texture [method texture] answers, without making it
## for a picture and only after making it for a kernel. Zero when there is none.
func texture_size() -> Vector2i:
    if is_generated():
        return Vector2i(tile, tile)
    var decoded := _read_mask()
    return decoded.get_size() if decoded != null else Vector2i.ZERO


## The decoded picture, one float per texel, read once and kept. Null for a
## kernel and for a file that cannot be read, with [member error] saying why.
##
## Public because the dab resamples a picture for a scale other than one, and
## the picture importer it would otherwise read the file through does not know
## GIMP's `.pat`, so a scaled Krita paper would never bind. The pattern is the
## one place that knows how its source is decoded.
func mask() -> Image:
    return _read_mask()


## A fresh texture of *size* from the kernel, outside the cache, so a chooser
## can draw a small one and the dab can sample a large one from one file. Null
## with [member error] set for a picture, which has one size, and for a kernel
## that does not compile.
##
## *zoom* is how many of the texture's texels one texel of [member tile] spans.
## A chooser's cell leaves it at one and shows the paper's own cells, and the
## dab passes its texture scale, so a kernel that sizes its cells in texels
## draws them that much larger, as a picture resampled by the scale would be.
func generate(size: Vector2i, zoom: float = 1.0) -> SaTexture:
    if not is_generated():
        error = "%s is a picture and has the one size it was drawn at." % source.get_file()
        return null
    var made := _loader().generate(size, uniforms, RenderingDevice.DATA_FORMAT_R32_SFLOAT, zoom)
    if made == null:
        error = _loader().error
    return made


## A CPU picture of the pattern *size* texels across, for a chooser's cell.
##
## A kernel is generated at that size and read back through the export path,
## which is the one place a pattern leaves VRAM. It is not a breach of hard
## rule 1: that rule is about the canvas during a stroke, this is a tile of
## texture read once when a chooser opens, with no stroke and no canvas
## involved, the way `core/presets/sa_preset_thumbs.gd` reads a throwaway document
## through the same door. A picture is its own mask, resized. Null when the
## pattern has no texture.
func image_at(size: int) -> Image:
    var wanted := maxi(size, 1)
    if is_generated():
        var made := _loader().picture(Vector2i(wanted, wanted), uniforms)
        if made == null:
            error = _loader().error
        return made
    var decoded := _read_mask()
    if decoded == null:
        return null
    var copy := decoded.duplicate() as Image
    copy.resize(wanted, wanted, Image.INTERPOLATE_BILINEAR)
    return copy


## The `uniform` lines a kernel source declares, for the sliders the
## Texture page builds, and empty for a picture.
func kernel_uniforms() -> Array:
    return _loader().uniforms() if is_generated() else []


## The kernel loader, made once.
func _loader() -> SaPatternKernel:
    if _kernel == null:
        _kernel = SaPatternKernel.new(source)
    return _kernel


## The decoded picture, read once.
##
## A `.pat` is decoded by [SaPatternPat] and then handed to the picture
## loader's mask rule, which is where every source's polarity is decided, so
## GIMP's format arrives as a paper the way a PNG does. Its refusal is quoted
## as the reader wrote it, because a truncated header and a wrong magic word
## are different faults and "could not be read" tells a painter neither.
func _read_mask() -> Image:
    if _mask != null or is_generated():
        return _mask
    if _refused:
        return null
    var store := _listed_by()
    if store != null:
        var known := store.known_failure(source)
        if not known.is_empty():
            _refuse(known, false)
            return null
    if source.get_extension().to_lower() == PAT_EXTENSION:
        var pat := SaPatternPat.read_file(source)
        if pat.image == null:
            _refuse(pat.error, true)
            return null
        _mask = SaPatternImage.mask_of(pat.image)
        return _mask
    _mask = SaPatternImage.read_mask(source)
    if _mask == null:
        _refuse("%s could not be read as a pattern." % source.get_file(), true)
    return _mask


## Keeps *reason* as the answer to every ask after this one, and tells the
## store when the refusal is this object's own rather than one the store
## already held.
func _refuse(reason: String, tell_store: bool) -> void:
    error = reason
    _refused = true
    var store := _listed_by()
    if tell_store and store != null:
        store.refused(source, reason)


## The store behind the weak reference, or null for a pattern made by hand or
## one whose store has gone.
func _listed_by() -> SaPatternStore:
    if _store == null:
        return null
    var held: Variant = _store.get_ref()
    return held if held is SaPatternStore else null
