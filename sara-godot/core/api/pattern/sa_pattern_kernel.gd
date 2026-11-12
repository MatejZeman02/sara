## The kernel loader for a pattern: a `.gmacs` pixel function run through the
## pixel-function door into an `r32f` texture of a chosen size.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The door is `core/custom-shader/compiler/sa_pixel_function.gd`, which wraps
## `def pixel(ivec2 at) -> vec4` in the two images, the params block and the dispatch.
## A pattern kernel is that function with no source to read: it answers a texel from
## `at` and its uniforms alone, so the source image is the one by one stand-in every
## unused binding takes and the target is the tile. The dispatch is the tile's
## rectangle and nothing else, and the storage format follows the bound
## textures, so a kernel written for the canvas's `rgba32f` writes the red channel of
## an `r32f` tile here.
##
## **`tile` and `zoom` are the two uniforms the loader writes.** A kernel that
## declares `uniform float tile` is handed the texture's width, so a lattice or
## a thread count can wrap at the edge and the pattern tiles seamlessly at any
## size it is generated at. A kernel that declares `uniform float zoom` is
## handed how many texels of the texture one texel of the pattern's own tile
## spans, which is one for a chooser's cell and the brush's texture scale for
## the tile a dab reads. A kernel that sizes its features as a share of `tile`,
## as Canvas Weave counts its threads, grows with the tile and needs no zoom.
## One that sizes them in texels, as Paper Grain sizes its cells, multiplies
## its widths by the zoom, or a texture scale of a half lays the same cells over
## a tile half the size and a painter sees no change. A kernel
## that declares neither is run as written.
##
## **One loader per file, owned by the pattern that reads it.** The wrapper
## writes the generated kernel under `user://`, compiles it once and has to
## outlive the compile because it holds the body's include registration, so
## it lives here for as long as the pattern does. Not in a static cache,
## because a static outlives the rendering device at exit and its compute would
## free its pipelines into a device already gone. The SPIR-V cache makes a
## second compile of the same text a read.
##
## **[method picture] is a readback, and where it runs is written down.** It
## runs when
## the stamp's pattern chooser draws a cell, and when the noise brush's settings
## name a generated pattern for its Picture field, from a row, a preset loaded
## or a preset's thumbnail, for the grey mask its texture sensor reads on the
## CPU. Never at a press, where the read would stall the stroke, a megabyte at
## the default tile and 256 MB at 4096. A tile of
## pattern and never the canvas, and never during a stroke. [member reads]
## counts the reads, so a suite can hold a press to none.
class_name SaPatternKernel
extends RefCounted

## Preloaded by path, the way the compiler's own halves reach each other.
const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

## The readback the export path does, by script rather than through the
## autoload, because the read is a static function of the script.
const ExportScript = preload("res://core/export/sa_export.gd")

## The uniform the loader fills with the texture's width.
const TILE_UNIFORM: String = "tile"

## The uniform the loader fills with the zoom [method generate] is asked for.
const ZOOM_UNIFORM: String = "zoom"

## How many times [method picture] has read a tile back since the program
## started, for a suite that holds a press to none. An int, so a static is safe
## here where a compute is not.
static var reads: int = 0

## The pixel function file this runs.
var source: String = ""

## Why the last ask answered nothing, or empty when it did not.
var error: String = ""

## The compiled wrapper, made on the first ask. Untyped because the script is
## preloaded by path and has no static type to infer.
var _function: PixelFunction = null
var _compiled: bool = false


func _init(source_path: String) -> void:
    source = source_path


## A texture *size* across, the kernel run over every texel of it with *values*
## over the declared defaults, or null with [member error] saying why. `r32f`
## unless *format* says otherwise: a thumbnail asks for the colour format so
## the export path can read it, and the dab's tile is the one-channel default.
## *zoom* is the pattern's own tile drawn that many texels to one of its own,
## which reaches a kernel that declares the uniform.
func generate(
    size: Vector2i, values: Dictionary = {}, format: int = RenderingDevice.DATA_FORMAT_R32_SFLOAT, zoom: float = 1.0
) -> SaTexture:
    if size.x <= 0 or size.y <= 0:
        error = "a pattern needs a size, and %s was asked for %s." % [source.get_file(), str(size)]
        return null
    if _compile() == null:
        return null
    var target := SaTexture.new(size, format)
    if target.rd == null or not target.rid.is_valid():
        error = "no texture could be made for %s." % source.get_file()
        return null
    var params := SaTyped.strings(values)
    if declares(TILE_UNIFORM):
        params[TILE_UNIFORM] = float(size.x)
    if declares(ZOOM_UNIFORM):
        params[ZOOM_UNIFORM] = zoom
    _function.run(SaBrushTipMask.stand_in(), target, Rect2i(Vector2i.ZERO, size), params)
    error = ""
    return target


## The kernel run *size* texels across and brought back as an 8-bit grey
## picture, for a chooser's cell. Null with [member error] set when it does
## not run.
##
## Generated in the colour format rather than the tile's `r32f`, because the
## one readback Sara has outside a stroke is the export path's, which reads
## a colour texture and nothing narrower, and a pattern kernel writes the
## same value to every channel anyway. The read is the one this file's
## header lists, with no stroke and no canvas involved.
##
## **The image comes back as it was read, not as `FORMAT_L8`.** The convert is
## in `SaPatternChooser`, where the tile is made and where both paths meet, so
## a generated and an imported pattern come out in one format.
func picture(size: Vector2i, values: Dictionary[String, Variant] = {}) -> Image:
    var texture := generate(size, values, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    if texture == null:
        return null
    reads += 1
    var floats: Image = ExportScript.get_texture_image_float(texture)
    if floats == null:
        error = "%s ran but could not be read back." % source.get_file()
        return null
    return floats


## The `uniform` lines the file declares, as the wrapper reads them: name,
## type, default, minimum, maximum and whether a range comment was written.
## What a page of sliders is built from, and empty for a file that does not
## open.
func uniforms() -> Array:
    var function: PixelFunction = _compile()
    return function.uniforms if function != null else []


## Whether the file declares a uniform called *uniform_name*.
func declares(uniform_name: String) -> bool:
    for raw_field: Variant in uniforms():
        if SaTyped.text_at(SaTyped.strings(raw_field), "name", "") == uniform_name:
            return true
    return false


## The wrapper, compiled on the first ask and null with [member error] set
## when it will not.
func _compile() -> Variant:
    if _compiled:
        return _function
    _compiled = true
    var function := PixelFunction.new(source)
    if not function.compile():
        var reason: String = function.first_error()
        if reason.is_empty():
            reason = ", ".join(function.problems) if not function.problems.is_empty() else "the kernel did not compile."
        error = "%s: %s" % [source.get_file(), reason]
        return null
    _function = function
    return function
