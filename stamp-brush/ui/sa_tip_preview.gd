## The tip the brush is holding, drawn as one dab at the top of the brush
## editor's tip page and its General page, and drawn again when an image tip
## is loaded.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is a `Kind.CUSTOM` row this module declares, built through the spec's
## factory, so the editor draws it as any row it did not write and needs to know
## nothing about brushes. Its value is the tool's `tip_loaded` signal, and when a
## tip lands it says so through the write it was handed.
##
## **It is a real dab, painted by the real tool.** `SaPresetThumbs.render_tip`
## runs the brush over an easel of this preview's own, 128 texels square, and
## reads the result. A preview that drew its own idea of a mask would be a second
## authority on the tip's shape. The read back is the preset thumbnail's, and
## happens when a row is written and not while a hand is painting (hard rule 1).
##
## **A drag is one draw, not one per tick**, so it asks the stroke strip's
## `SaPreviewCompressor` rather than reading back on every value a slider sends.
class_name SaTipPreview
extends CenterContainer

## The picture's side in logical units. Square, because a tip is, and small
## enough to leave the page's rows on screen under it.
const SIDE: int = 96

## How far from the card behind it a texel has to be to count as ink, per
## channel, for the coverage a dump reports.
##
## A distance from the background and not an alpha: `SaPresetThumbs` paints onto
## a real document, whose default background is opaque, so every texel of the
## picture has an alpha of one and a preview measured that way reads as a solid
## square whatever the tip is. The card is sampled from the corner, which no dab
## centred on the square reaches.
const INK_DISTANCE: float = 0.02

## The dab itself.
var picture: TextureRect = null

## What the run has drawn, for a dump. The claim is that the picture changed, and
## a screenshot of two round dabs cannot say it was drawn twice.
var renders: int = 0

## The rule that decides when the preview draws. Read from outside for its
## `coalesced` and `pending`, which a dump and a test report.
var compressor: SaPreviewCompressor = null

## The door that tells the surface drawing this row that a tip landed, handed
## over at construction.
var _write: Callable = Callable()

## The tool whose `tip_loaded` this row hears, or null before the first bind.
var _source: Object = null

var _tool_script: Script = null
var _settings: Resource = null
## The last dab as a number, so a scenario can say the preview changed without
## comparing two screenshots.
var _coverage: float = 0.0
var _ink: int = 0


func _init(write: Callable = Callable()) -> void:
    name = "TipPreview"
    _write = write
    picture = TextureRect.new()
    picture.name = "Picture"
    picture.custom_minimum_size = Vector2(SaUI.px(SIDE), SaUI.px(SIDE))
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.tooltip_text = tr("The tip this brush stamps, as one dab at full pressure.")
    add_child(picture)
    compressor = SaPreviewCompressor.new(_render)
    add_child(compressor)


## Points the row at the tool behind *loaded*, the tool's own `tip_loaded`,
## which is the value the row's spec reads. The binder calls it on every sync,
## so a second call for the same tool draws nothing.
##
## A value that is not a signal is a tool whose tip never changes behind the
## editor's back, and the ear comes off whatever it was on.
func follow(loaded: Variant) -> void:
    var tool: Object = (loaded as Signal).get_object() if loaded is Signal else null
    if tool == _source:
        return
    if _source != null and is_instance_valid(_source) and _source.tip_loaded.is_connected(_on_tip_loaded):
        _source.tip_loaded.disconnect(_on_tip_loaded)
    _source = tool
    if tool == null:
        return
    (loaded as Signal).connect(_on_tip_loaded)
    bind_source(tool.get_script() as Script, tool.get("settings") as Resource)
    render_now()


## What the preview draws from. The settings object is held rather than copied,
## so every later request reads whatever the painter has done to it since, which
## is the same contract `SaBrushPreviewStrip` has.
func bind_source(tool_script: Script, brush_settings: Resource) -> void:
    _tool_script = tool_script
    _settings = brush_settings


## Asks for the dab again. What every row write sends, through the compressor.
##
## The compressor is needed because even one dab is not a cheap render: it
## measures at about 110 ms, a fresh easel painted and read back whatever its
## size, so a drag without it would stall on every tick.
func request() -> void:
    compressor.request()


## The editor's door for a row of the page moving the settings, which is a
## request like any other.
func option_settings_moved() -> void:
    request()


## Draws the dab from the settings as they are now, whatever the compressor
## would have said. What a bind, a test and a scenario ask for.
func render_now() -> void:
    compressor.draw_now()


## A tip landed through the Load Tip action, which writes no option, so no row
## moved and nothing else on the page knows.
##
## The write is what tells the editor, which shows the page's rows the new
## selection, and the dab is asked for after it, because a page drawn again
## frees this row.
func _on_tip_loaded(_path: String) -> void:
    # A page drawn again queues its rows for freeing, and until the frame ends a
    # row that is going still hears the tool. The row that replaced it answers.
    if is_queued_for_deletion():
        return
    if _write.is_valid() and _source != null:
        _write.call(_source.get("tip_loaded"))
    if not is_queued_for_deletion():
        request()


func _render() -> void:
    if _tool_script == null or _settings == null:
        return
    # The tip and never its size, which is the point of the preview: what there
    # is to see is the shape, the hardness, the mirror and the rotation, and a
    # brush at two per cent draws a dab three texels across that says nothing
    # about any of them. Size is its own row and its own page.
    #
    # Framed the way the presets grid frames a tip cell, through `render_tip`. A
    # fixed radius alone was not enough: a Size option below full strength scales
    # every dab at full pressure, and so does an image tip whose picture leaves a
    # margin, and on the running app a Size option at 30 percent drew 23 texels
    # in the middle of the square where the plain tip drew
    # 72. `render_tip` paints on a deep copy at its own radius and frames what was
    # painted, so the painter's settings are never written on.
    var image := SaPresetThumbs.render_tip(_tool_script, _settings, Vector2i(SIDE, SIDE))
    if image == null:
        return
    picture.texture = ImageTexture.create_from_image(image)
    renders += 1
    _measure(image)


## The dab as two numbers: how many texels took ink and what share of the square
## that is. Both, because a shape that turns keeps its count and changes its
## spread while one that grows changes both.
func _measure(image: Image) -> void:
    var card := image.get_pixel(0, 0)
    var ink := 0
    for y in image.get_height():
        for x in image.get_width():
            if _is_ink(image.get_pixel(x, y), card):
                ink += 1
    _ink = ink
    _coverage = float(ink) / float(maxi(1, image.get_width() * image.get_height()))


## Whether *texel* is paint rather than the card it was painted on.
static func _is_ink(texel: Color, card: Color) -> bool:
    return (
        absf(texel.r - card.r) > INK_DISTANCE
        or absf(texel.g - card.g) > INK_DISTANCE
        or absf(texel.b - card.b) > INK_DISTANCE
        or absf(texel.a - card.a) > INK_DISTANCE
    )


## What the preview is showing, for a dump.
##
## `bounds` is the ink's own rectangle, which is the half that says a mirror or a
## rotation did something: a tip flipped about its centre keeps its coverage and
## moves its box.
func preview_report() -> Dictionary:
    var tip: Resource = _settings.get("tip") if _settings != null and "tip" in _settings else null
    return {
        "present": picture.texture != null,
        "renders": renders,
        # The asks folded into a later draw, beside the draws, because a drag
        # that costs one dab is only a claim while both numbers are read.
        "coalesced": compressor.coalesced,
        # Which file the dab was drawn from, so a dump can say the preview
        # followed a load rather than only that it was drawn again.
        "tip": String(tip.get("image_path")) if tip != null and "image_path" in tip else "",
        "ink": _ink,
        "coverage": snappedf(_coverage, 0.0001),
        "bounds": _bounds(),
    }


## The editor's dump door for a row it did not build: what the dump carried
## under `tip_preview` when the editor owned this row.
func capture_option_report() -> Dictionary:
    return preview_report()


## The capture door a module's widget answers, and the one way a scenario
## loads a tip, past the file dialog nobody can drive:
## `{"brush_editor": {"widget": {"load_tip": "res://tips/tree.png"}}}`.
func capture_option_edit(spec: Dictionary) -> String:
    if not spec.has("load_tip"):
        return "SaCapture: the tip preview takes load_tip and nothing else"
    if _source == null or not _source.has_method("load_tip"):
        return "SaCapture: the tip preview is bound to no tool that loads a tip"
    var path := String(spec["load_tip"])
    var loaded := bool(_source.call("load_tip", path))
    return "SaCapture: load_tip %s %s" % [path, "loaded" if loaded else "refused"]


func _bounds() -> Array:
    if picture.texture == null:
        return []
    var image := picture.texture.get_image()
    if image == null:
        return []
    var card := image.get_pixel(0, 0)
    var left := image.get_width()
    var top := image.get_height()
    var right := -1
    var bottom := -1
    for y in image.get_height():
        for x in image.get_width():
            if not _is_ink(image.get_pixel(x, y), card):
                continue
            left = mini(left, x)
            top = mini(top, y)
            right = maxi(right, x)
            bottom = maxi(bottom, y)
    return [] if right < 0 else [left, top, right - left + 1, bottom - top + 1]
