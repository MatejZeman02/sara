## The `find` step: which pixels hold a colour, the other way round from
## `texel`, which says what colour a pixel holds.
##
## This answers the count and the bounding box in one line, and writes the
## mask as a picture when asked, so a client reads where a colour is without
## exporting the canvas and building masks of colour ranges in its own code.
##
## **The colour is the one a painter sees**, eight bits a channel in sRGB, as
## `look` writes it and as a hex code names it. The composite is read through
## `SaExport.get_preview_image`, the readback `look` already makes, and a layer
## through `SaExportGamut.encoded_byte_image` into sRGB from the document's own
## space, so a default Oklab document is searched in the colours on screen and
## not in its stored numbers. A layer's texel matches only when it is at least
## half opaque: a layer keeps its colour in straight alpha, so the faint rim of
## a soft stroke holds the stroke's own colour at an alpha nobody sees, and
## counting it would find several times the texels the composite shows.
##
## **A layer's count is not the composite's, and that is no fault.** Half
## opacity still leaves the layer counting about three times the texels the
## composite shows, because the composite's matches lie on layer texels close
## to opaque. Below that the rim is blended with the grey ground, which moves
## it more than six steps. A layer search says where the stroke reaches, from
## half opacity up, and a composite search where its colour is seen.
##
## **A readback, asked for by name.** Hard rule 1 keeps the canvas in VRAM
## during a stroke, and this runs between steps, once, the allowance `texel`
## and `look` take. A layer is gathered over the rect only, chunk by chunk on
## the graphics card, the way `read_pixels` gathers it. The match is counted on
## the processor over the bytes already read, because the answer is a handful of
## numbers and a mask, and the rect bounds what is read.
##
## Reached by path from the step table, not by class name, so no editor rescan
## stands between a fresh checkout and a step.
extends RefCounted

const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")

## The least alpha, in eight bits, at which a layer's texel can match.
const LEAST_ALPHA := 128

## What the answer names as the layer when the composite was searched.
const COMPOSITE := "composite"

## The run, read for its tree and for the folder a mask is written into.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Finds a colour: the count and box of pixels near `color`,
## `{"find": {"color": "#3a5f8c", "tolerance": 12, "mask": "m.png"}}`, where a
## layer counts a soft stroke's rim from half opacity up and the composite only
## where that rim, blended with what lies under it, still shows the colour, so a
## layer's count over a soft stroke runs well above the composite's.
##
## **Arguments.**
## - `color` a hex code `"#rrggbb"`, or an array `[r, g, b]` of numbers from 0 to
##   1, in sRGB.
## - `tolerance` integer, in steps of eight bits, 0 by default: a pixel matches
##   when each of its three channels is within it of the colour's.
## - `rect` array `[x, y, w, h]` in document pixels, cut to the canvas. The whole
##   canvas when absent.
## - `layer` a layer's name or its index from the bottom, 0 the lowest, where a
##   texel matches only when at least half opaque. The composite when absent.
## - `mask` string, a `.png` written the rect's size, white where a pixel
##   matches and black elsewhere, in the run's folder when bare. None when
##   absent.
##
## The answer is one line, `SaCapture: find <json>`, carrying `count`, `box`
## as `[x, y, w, h]` or null when nothing matched, the `rect` searched, the
## `layer`, and `mask`, the machine's own path, when one was written. A refusal
## is the same line with an `error`.
func find(spec: Dictionary) -> Dictionary:
    var answer := find_in(CanvasDriver.main_canvas(), spec, _run.out_dir)
    print("SaCapture: find %s" % JSON.stringify(answer))
    return answer


## The search under [method find], on *canvas*, a relative `mask` written into
## *folder*. Static, so a suite grades it on a canvas of its own with no run.
static func find_in(canvas: SaCanvas, spec: Dictionary, folder: String) -> Dictionary:
    var started := Time.get_ticks_usec()
    if canvas == null or canvas.easel == null or canvas.easel.document == null:
        return {"error": "there is no canvas to search"}
    var document := canvas.easel.document
    var wanted: Variant = color_of(spec.get("color", null))
    if wanted is String:
        return {"error": wanted}
    var tolerance := int(spec.get("tolerance", 0))
    if tolerance < 0:
        return {"error": "the tolerance is zero or more steps, not %s" % [spec["tolerance"]]}
    var whole := Rect2i(Vector2i.ZERO, document.canvas_size)
    var rect := whole
    if spec.has("rect"):
        var asked: Variant = spec["rect"]
        if not (asked is Array) or (asked as Array).size() != 4:
            return {"error": "a rectangle is [x, y, w, h], not %s" % [asked]}
        rect = Rect2i(int(asked[0]), int(asked[1]), int(asked[2]), int(asked[3])).intersection(whole)
        if rect.size.x <= 0 or rect.size.y <= 0:
            return {"error": "the rect %s misses the %dx%d canvas" % [spec["rect"], whole.size.x, whole.size.y]}
    var named := COMPOSITE
    var picture: Image = null
    if spec.get("layer", null) == null:
        var composite := SaExport.get_preview_image(canvas.easel)
        if composite != null:
            picture = composite if rect == whole else composite.get_region(rect)
    else:
        var layer: Variant = PixelDriver.layer_of(document, spec["layer"])
        if layer is String:
            return {"error": layer}
        named = String((layer as SaLayer).name)
        var texture := PixelDriver.assembled(layer as SaLayer, rect)
        if texture != null:
            picture = SaExportGamut.encoded_byte_image(texture, document.color_space, SaColorSpace.srgb())
    if picture == null:
        return {"error": "the pixels could not be read back"}
    var found := Match.new(picture, wanted as Color, tolerance, named != COMPOSITE, spec.has("mask"))
    var answer := {
        "count": found.count,
        "box": null,
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "layer": named,
    }
    if found.count > 0:
        var box := Rect2i(found.box.position + rect.position, found.box.size)
        answer["box"] = [box.position.x, box.position.y, box.size.x, box.size.y]
    if spec.has("mask"):
        var path := ScenarioDocument.look_path(folder, String(spec["mask"]))
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var error := found.mask.save_png(path)
        if error != OK:
            return {"error": "%s could not be written: %s" % [path, error_string(error)]}
        answer["mask"] = ProjectSettings.globalize_path(path)
    answer["ms"] = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.01)
    return answer


## *value* as a colour, from `"#rrggbb"` or `[r, g, b]`, or a String saying why
## it is not one.
static func color_of(value: Variant) -> Variant:
    if value is String and Color.html_is_valid(value):
        return Color.html(value)
    if value is Array and (value as Array).size() == 3:
        for part: Variant in value:
            if not (part is int or part is float):
                return 'a colour is "#rrggbb" or three numbers, not %s' % [value]
        return Color(float(value[0]), float(value[1]), float(value[2]))
    return 'a colour is "#rrggbb" or [r, g, b] from 0 to 1, not %s' % [value]


## The pixels of one picture that match one colour: their count, their bounding
## box in the picture's own pixels, and the mask when asked for. One pass over
## the bytes, which is all of the arithmetic.
class Match:
    var count := 0
    var box := Rect2i()
    var mask: Image = null

    func _init(picture: Image, color: Color, tolerance: int, needs_alpha: bool, wants_mask: bool) -> void:
        if picture.get_format() != Image.FORMAT_RGBA8:
            picture.convert(Image.FORMAT_RGBA8)
        var size := picture.get_size()
        var bytes := picture.get_data()
        var marks := PackedByteArray()
        if wants_mask:
            marks.resize(size.x * size.y)
        var r := color.r8
        var g := color.g8
        var b := color.b8
        var low := Vector2i(size.x, size.y)
        var high := Vector2i(-1, -1)
        var at := 0
        for y in size.y:
            for x in size.x:
                var i := at * 4
                at += 1
                if absi(bytes[i] - r) > tolerance or absi(bytes[i + 1] - g) > tolerance:
                    continue
                if absi(bytes[i + 2] - b) > tolerance or (needs_alpha and bytes[i + 3] < LEAST_ALPHA):
                    continue
                count += 1
                low = Vector2i(mini(low.x, x), mini(low.y, y))
                high = Vector2i(maxi(high.x, x), maxi(high.y, y))
                if wants_mask:
                    marks[at - 1] = 255
        if count > 0:
            box = Rect2i(low, high - low + Vector2i.ONE)
        if wants_mask:
            mask = Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, marks)
