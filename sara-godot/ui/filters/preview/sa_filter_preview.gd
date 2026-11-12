## The viewport a filter's dialog shows its result in.
##
## A filter's `preview()` is a viewport of the active layer showing the last
## texture handed to `show`. Both halves are the same picture at two moments:
## the dialog seeds it with the layer's own pixels over the run's rectangle
## before the first run, and every `ctx.show(texture)` after that replaces it.
##
## Nothing is read back. The texture stays in VRAM and a `Texture2DRD` bound to
## its RID is what the `TextureRect` draws, which is how the minimap and the
## layer thumbnails already show a chunk. The `SaTexture` is held here for as
## long as it is shown, because a `Texture2DRD` over a released RID is the crash
## `sa_easel.gd`'s header records.
##
## The picture is painted with the canvas's own material. A `Texture2DRD` under
## a bare `TextureRect` puts the document's stored texels on the screen, and
## Godot's 2D pipeline writes a canvas colour out with no encode of its own, so
## an Oklab document's preview drew L, a and b as red, green and blue while the
## canvas beside it drew the colour the painter picked. That is the layer
## thumbnail's Oklab fault one surface along. The layer thumbnail answered it
## with a kernel that leaves display values behind and the minimap by borrowing
## the canvas's material, and borrowing is the right answer here for the same
## reason it was there: the preview is a second view of one document, so the
## view transform, the exposure, the display profile, the proof and the transfer
## curve all have to read the same on both or the comparison the preview exists
## for is a lie.
##
## The picture sits in a frame drawn in the theme's border colour under a muted
## caption that says what it is. Without them the strip was a dark band that
## began and ended nowhere, and in Levels it read as one more empty part of the
## window rather than as the picture of what the numbers above it do.
##
## **The picture is drawn over the chequer the canvas draws under a transparent
## texel**, and only over the rectangle the picture itself covers. The frame is
## near black, so black strokes on a transparent layer, and the blackened shapes
## an edge detection leaves on one, vanished into it. The chequer is the canvas's
## own shader on a `ColorRect` behind the picture, so nothing is read back and a
## transparent texel looks here as it looks beside the dialog.
##
## **The picture answers a click once a filter asks for one**, so a filter
## that needs a pixel, the area aware fill's seed, takes it here and reruns
## from it rather than through a tool variant of its own. The dialog calls
## [method take_clicks] for a `build` that wrote `ui.click`, and from then on
## a press on the picture is [signal clicked] with the document pixel drawn
## under it, which the dialog keeps as the filter's parameter. A
## picture nobody asked answers no press, so every other dialog and the filter
## browser are as they were.
class_name SaFilterPreview
extends VBoxContainer

## A press of the left button on the picture, as the document pixel drawn
## under it. Only once [method take_clicks] has been called, and only for a
## press on the picture itself, never in the bands beside it.
signal clicked(pixel: Vector2i)

## How tall the picture asks to be, logical, under its caption. Tall enough
## that a blur at a small radius is visible, short enough that a dialog with
## four widgets over it still fits a laptop screen.
const PREVIEW_HEIGHT := 200

## The rectangle in document pixels the shown texture covers, so a dump can say
## where on the canvas the preview is looking.
var rect: Rect2i = Rect2i()

## How many textures have been shown, which is what a scenario counts either
## side of a drag.
var shows: int = 0

## The shader the canvas draws behind a transparent texel, which the picture is
## laid over so black and transparent both read.
const CHECKER_SHADER: Shader = preload("res://shaders/canvas/checkerboard.gdshader")

## The longest side, in texels, of the reduced copy of the layer a point pass is
## run over for the picture. Twice the preview's logical height, so the picture
## is not enlarged on a screen at twice the scale, and small enough that a run
## on every slider frame costs a fraction of the canvas preview beside it.
const REDUCED_SIDE := 400

## How many times a different texture was bound to the picture. What says the
## texture changed between two dumps, in a number every run of a scenario agrees
## on, where the texture's RID was a different handle in every process.
var textures_bound: int = 0

## How many pictures were made by running a point pass over the reduced copy,
## which is what a scenario reads to say the thumbnail took that path.
var point_runs: int = 0

## How many pictures were made by running a pass that reads the whole layer
## over every chunk it writes and reducing each answer, which is what a
## scenario reads to say the tile took that path.
var whole_runs: int = 0

## The word over the frame, and the frame the picture is drawn in.
var caption: Label = null
var frame: PanelContainer = null

## The chequer behind the picture. Hidden while there is no picture, so an empty
## strip stays the plain frame, and sized to the rectangle the picture covers
## and not to the frame, so a wide frame around a tall picture is not chequered
## where nothing is drawn.
var chequer: ColorRect = null

## Whether a press on the picture is a click a filter asked for, set by
## [method take_clicks] and never cleared, since a dialog is built for one
## filter and dropped with it.
var takes_clicks: bool = false

## How many clicks the picture has reported, and the document pixel of the
## last, `(-1, -1)` before the first. What a scenario reads to say a click
## landed on the pixel it aimed at.
var clicks: int = 0
var clicked_pixel: Vector2i = Vector2i(-1, -1)

var _picture: TextureRect = null
var _held: SaTexture = null
var _bound: RID = RID()
## What runs a point pass over the reduced copy, built the first time one is
## shown so a filter that shows a texture builds no kernel for it.
var _reducer: Reducer = null


func _init() -> void:
    name = "FilterPreview"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(4))

    caption = Label.new()
    caption.name = "PreviewCaption"
    caption.text = tr("Preview")
    SaTheme.bind_font(caption, "text_muted")
    add_child(caption)

    frame = PanelContainer.new()
    frame.name = "PreviewFrame"
    frame.custom_minimum_size = Vector2(0, SaUI.px(PREVIEW_HEIGHT))
    # Any height a dialog hands the preview is the picture's, not the caption's.
    frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var box := StyleBoxFlat.new()
    SaTheme.bind(box, {"bg_color": "preview_ground", "border_color": "border_primary"})
    box.set_border_width_all(1)
    box.set_content_margin_all(1)
    frame.add_theme_stylebox_override("panel", box)
    add_child(frame)

    _picture = TextureRect.new()
    _picture.name = "PreviewPicture"
    _picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    frame.add_child(_picture)
    # A child of the picture rather than of the frame, because the frame is a
    # container that would stretch it over the whole strip, and drawn behind its
    # parent so the picture lands on it.
    chequer = ColorRect.new()
    chequer.name = "PreviewChequer"
    chequer.show_behind_parent = true
    chequer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chequer.visible = false
    var chequer_material := ShaderMaterial.new()
    chequer_material.shader = CHECKER_SHADER
    chequer.material = chequer_material
    _picture.add_child(chequer)
    _picture.resized.connect(_fit_chequer)
    # Every frame the dialog is up, which is a pointer comparison: the canvas
    # rebuilds nothing per frame, but a view transform switched in the View menu
    # while a filter is open swaps the shader on that one material object, and a
    # File > New behind the dialog builds a new one. Reading it back is cheaper
    # than subscribing to the six signals that could have moved it.
    set_process(true)


func _process(_delta: float) -> void:
    _sync_material()


## Shows *texture* over *covering*, in document pixels.
##
## A null texture clears the picture rather than leaving the previous one up,
## because a filter whose run produced nothing must not look like one that
## produced the same thing again.
func show_texture(texture: SaTexture, covering: Rect2i) -> void:
    rect = covering
    _held = texture
    # Here as well as in [method _process], so the first picture a dialog is
    # seeded with is already display-ready. A dialog that opens and is shot in
    # the same frame never reaches a process call.
    _sync_material()
    if texture == null or not texture.rid.is_valid():
        _picture.texture = null
        _bound = RID()
        _fit_chequer()
        return
    if texture.rid != _bound:
        var bound := Texture2DRD.new()
        bound.texture_rd_rid = texture.rid
        _picture.texture = bound
        _bound = texture.rid
        textures_bound += 1
    shows += 1
    _fit_chequer()


## Lays the chequer under the rectangle the picture is drawn in, and hides it
## when nothing is.
func _fit_chequer() -> void:
    if chequer == null or _picture == null:
        return
    var drawn := Rect2()
    if _held != null and _bound.is_valid():
        drawn = fitted(_picture.size, Vector2(_held.size))
    chequer.visible = drawn.has_area()
    chequer.position = drawn.position
    chequer.size = drawn.size


## Where a texture of *texture_size* lands in a control of *inside*, which is
## `STRETCH_KEEP_ASPECT_CENTERED` over `EXPAND_IGNORE_SIZE`: scaled to the
## largest size that fits, either way, and centred. Empty when either is.
static func fitted(inside: Vector2, texture_size: Vector2) -> Rect2:
    if inside.x <= 0.0 or inside.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
        return Rect2()
    var drawn := texture_size * minf(inside.x / texture_size.x, inside.y / texture_size.y)
    return Rect2((inside - drawn) / 2.0, drawn)


## Has the picture answer a press from now on: the pointer over it is a cross,
## its hover says what a click does, and [method picture_input] hears the
## picture's own input. Called by the dialog of a filter that asked, once.
func take_clicks() -> void:
    if takes_clicks:
        return
    takes_clicks = true
    _picture.mouse_filter = Control.MOUSE_FILTER_STOP
    _picture.mouse_default_cursor_shape = Control.CURSOR_CROSS
    _picture.tooltip_text = tr("Click a pixel of the picture to run the filter again from it.")
    _picture.gui_input.connect(picture_input)


## A press of the left button on the picture, reported as [signal clicked] with
## the document pixel under it. A press in the bands the kept aspect leaves
## beside the picture, or while nothing is drawn, reports nothing, because no
## pixel is there to start from. A pen's press arrives as this same event.
func picture_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if not takes_clicks or press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
        return
    var under: Variant = pixel_under(press.position)
    if under == null:
        return
    clicks += 1
    clicked_pixel = under
    if _picture.is_inside_tree():
        _picture.accept_event()
    clicked.emit(clicked_pixel)


## The document pixel drawn at *point*, in the picture's own units, or null
## where none is.
func pixel_under(point: Vector2) -> Variant:
    if _held == null or not _bound.is_valid():
        return null
    return pixel_at(point, _picture.size, Vector2(_held.size), rect)


## The document pixel at *point* of a picture *inside* across that draws a
## texture of *shown* texels covering *covering*, or null off the drawn part.
##
## Through [method fitted], the one place that says where the texture lands,
## and by the share of the drawn picture rather than by texels, because a point
## pass's picture is a reduced copy whose texel is several document pixels.
static func pixel_at(point: Vector2, inside: Vector2, shown: Vector2, covering: Rect2i) -> Variant:
    var drawn := fitted(inside, shown)
    if not drawn.has_point(point) or not covering.has_area():
        return null
    var share := (point - drawn.position) / drawn.size
    var pixel := covering.position + Vector2i((share * Vector2(covering.size)).floor())
    return pixel.clamp(covering.position, covering.end - Vector2i.ONE)


## Where the centre of document pixel *pixel* is drawn in a picture *inside*
## across, the way back from [method pixel_at], or null when it is not drawn.
static func point_at(pixel: Vector2i, inside: Vector2, shown: Vector2, covering: Rect2i) -> Variant:
    var drawn := fitted(inside, shown)
    if not drawn.has_area() or not covering.has_point(pixel):
        return null
    var share := (Vector2(pixel - covering.position) + Vector2(0.5, 0.5)) / Vector2(covering.size)
    return drawn.position + share * drawn.size


## `{"click": [x, y]}` presses the left button over document pixel x, y of the
## picture and lets it go, the door's `filter` step handing the words over
## by the picture row's key.
##
## Pushed into the dialog's own window at the point the picture draws that
## pixel, so the press finds the picture by the engine's own hit test and
## reaches [method picture_input] the way a hand's press does, rather than
## being handed to it. The line says what the picture reported, which is the
## pixel asked for when the mapping both ways agrees.
func capture_option_edit(spec: Dictionary) -> String:
    var wanted := spec.get("click", []) as Array
    if wanted == null or wanted.size() < 2:
        return 'the preview takes {"click": [x, y]}, a document pixel'
    var pixel := Vector2i(int(wanted[0]), int(wanted[1]))
    var shown := Vector2(_held.size) if _held != null and _bound.is_valid() else Vector2.ZERO
    var local: Variant = point_at(pixel, _picture.size, shown, rect)
    if local == null or not _picture.is_inside_tree():
        return "the preview draws no pixel %s, it covers %s" % [pixel, rect]
    var before := clicks
    var at: Vector2 = _picture.get_global_transform_with_canvas() * (local as Vector2)
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.position = at
        event.global_position = at
        _picture.get_viewport().push_input(event, true)
    if clicks == before:
        return "pressed over pixel %s at %s and the picture heard nothing" % [pixel, at]
    return "clicked pixel %s, the preview reports %s after %d clicks" % [pixel, clicked_pixel, clicks]


## Shows *ctx*'s point pass run over a reduced copy of the layer, over the run's
## rectangle.
##
## A point pass draws nothing until something runs it, and the compositor runs
## it on the canvas and nowhere else, so this is the run the thumbnail needs of
## its own. On the GPU from the layer's chunks to the texture shown, with
## nothing read back (hard rule 1, no CPU-GPU ping-pong), and at [constant REDUCED_SIDE] texels rather
## than the layer's own size, so a slider frame costs a few hundred thousand
## texels whatever the document measures.
func show_point_pass(ctx: SaFilterContext) -> void:
    if _reducer == null:
        _reducer = Reducer.new()
    var made := _reducer.picture(ctx)
    if made != null:
        point_runs += 1
    show_texture(made, ctx.rect if ctx != null else Rect2i())


## Shows the layer *ctx* was made for, reduced as a point pass's picture is,
## over the rectangle a run without a margin covers. The picture a dialog opens
## on before its first run.
func show_layer(ctx: SaFilterContext) -> void:
    if _reducer == null:
        _reducer = Reducer.new()
    show_texture(_reducer.layer(ctx), ctx.rect_for(0) if ctx != null else Rect2i())


## Shows *gathered*, a neighbourhood pass's picture over *ctx*'s rectangle,
## blended with the layer under the selection's mask the way a shown texture is.
## Gathered at full size by the caller, because a neighbourhood pass's radius is
## in document pixels and a reduced copy would read too far.
func show_gathered(ctx: SaFilterContext, gathered: SaTexture) -> void:
    var covering := ctx.rect if ctx != null else Rect2i()
    show_texture(blended_over(ctx, gathered, covering), covering)


## Shows *ctx*'s pass that reads the whole layer, a kaleidoscope, over the
## whole of where it writes, reduced to [constant REDUCED_SIDE] texels.
##
## Run one chunk at a time over that chunk alone, a texel would read only what
## its fold finds inside its own chunk, and over the painted bounds it would
## miss where the fold writes the canvas, a piece of the photograph where the
## layer is a whole kaleidoscope. So the picture covers what [method
## Reducer.whole_covering] answers, and each chunk reads the layer gathered
## whole, as the compositor's chain and Apply read it.
func show_whole_pass(ctx: SaFilterContext) -> void:
    if _reducer == null:
        _reducer = Reducer.new()
    var covering := Reducer.whole_covering(ctx)
    var made := _reducer.whole_picture(ctx, covering)
    if made != null:
        whole_runs += 1
    show_texture(made, covering)


## Paints the picture with the canvas's material, or with nothing when there is
## no canvas to borrow from, which is every test that builds a dialog on its own.
##
## The material object is shared rather than duplicated. That is what the
## minimap does while its proof is off, and it is what makes the two views
## impossible to get out of step: there is one set of uniforms and both read it.
## Nothing here writes to the material, so sharing costs nothing either way.
func _sync_material() -> void:
    var wanted := _canvas_material()
    if _picture != null and _picture.material != wanted:
        _picture.material = wanted


## The canvas the filter is running on, the front document's, which is the
## door `SaFilterDialogWindow` takes its document through, so the material and
## the pixels cannot come from two different documents.
func _canvas_material() -> ShaderMaterial:
    return display_material_of(SaCanvasView.front_canvas() if is_inside_tree() else null)


## The display material of *canvas*, or null for no canvas or one with no
## material yet, which is a test host and the editor both: neither has a front
## document, and a preview there stays the bare picture it always was.
##
## Static and by argument rather than reading the tree itself, so a suite can
## ask the question without a scene, which is the only half of the claim a
## windowless test can hold. The other half is the scenario.
static func display_material_of(canvas: SaCanvas) -> ShaderMaterial:
    return canvas.material as ShaderMaterial if canvas != null else null


## What the preview is showing, for the state dump.
##
## No RID. A texture's id is a handle the device hands out, a different number in
## every process, so two runs of one scenario never agreed on it and a comparison
## through the door failed on that key alone. What a scenario has to say is that
## the texture changed between two dumps, and `textures_bound` says so in a
## number every run agrees on. `shows` beside it counts every show, a second show
## of the texture already bound included.
func describe() -> Dictionary:
    var shown_size := Vector2i.ZERO
    if _held != null and _held.rid.is_valid():
        shown_size = _held.size
    return {
        "shows": shows,
        "holds_texture": _bound.is_valid(),
        "textures_bound": textures_bound,
        "point_runs": point_runs,
        "whole_runs": whole_runs,
        "texture_size": [shown_size.x, shown_size.y],
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "height": size_of_picture(),
        "display_shader": shown_display_shader(),
        "screen_rect": _screen_rect_of_picture(),
        "chequer": chequer.visible,
        "chequer_rect": [chequer.position.x, chequer.position.y, chequer.size.x, chequer.size.y],
        "chequer_shader": (chequer.material as ShaderMaterial).shader.resource_path.get_file(),
        "takes_clicks": takes_clicks,
        "clicks": clicks,
        "clicked": [clicked_pixel.x, clicked_pixel.y],
    }


## The shader the picture is painted through, or an empty name when it is
## painted through none. What says the display transform reached the preview,
## which a shot can show but cannot name.
func shown_display_shader() -> String:
    var painted_with := _picture.material as ShaderMaterial if _picture != null else null
    var shader := painted_with.shader if painted_with != null else null
    return shader.resource_path.get_file() if shader != null else ""


## The height the picture is actually drawn at, so a shot that looks empty can
## be told from a preview that was never given room.
func size_of_picture() -> float:
    return _picture.size.y if _picture != null else 0.0


## Where the picture lands in the shot, in root viewport pixels, so a script can
## read the preview's colour out of a PNG instead of a person pointing at it.
##
## The arithmetic is `workspace_page.gd`'s `track_screen_rect`, which is the one
## place in the tree that already answers "where is this control in the picture"
## for a control inside a dialog: an embedded window is placed in the root
## viewport and takes the root's final transform, a real OS window takes its own
## position and content scale.
func _screen_rect_of_picture() -> Dictionary:
    var window := get_window() if is_inside_tree() else null
    if window == null or _picture == null:
        return {}
    var box := _picture.get_global_rect()
    if not window.is_embedded():
        var factor := window.content_scale_factor
        box = Rect2(Vector2(window.position) + box.position * factor, box.size * factor)
    else:
        var tree := get_tree()
        if tree != null and tree.root != null:
            var transform := tree.root.get_final_transform()
            box = Rect2(transform * (Vector2(window.position) + box.position), transform.get_scale() * box.size)
    return {"x": box.position.x, "y": box.position.y, "w": box.size.x, "h": box.size.y}


## *ctx*'s last result, blended with what the layer already holds over the
## selection's mask, through the same kernel `SaFilterApply.apply` writes with,
## so a lasso, an ellipse or a feather reads the same way here as it
## will once Apply runs. The raw result, unmodified, when no selection is
## active.
##
## `ctx.document` and `ctx.layer` are read rather than written, which any
## file may do with a private member. A blend built apart from the run that
## made it would risk a document, a layer or a selection that came from three
## places disagreeing, the same reasoning `SaFilterApply.apply` gives for
## reading its own pair off the context.
static func blended(ctx: SaFilterContext) -> SaTexture:
    if ctx == null or ctx.shown == null:
        return null
    return blended_over(ctx, ctx.shown, ctx.shown_rect)


## *picture*, which covers *covering* of *ctx*'s layer, blended with what the
## layer holds there over the selection's mask. [method blended] for a picture
## the run did not hand to `show`, which is a neighbourhood pass's gathered
## picture in the dialog: showing it through the context would give Apply a
## texture to write where the pass is what it has to walk.
static func blended_over(ctx: SaFilterContext, picture: SaTexture, covering: Rect2i) -> SaTexture:
    if ctx == null or picture == null:
        return null
    var document: SaDocument = ctx.document
    var layer: SaLayer = ctx.layer
    var selection: SaSelection = document.selection if document != null else null
    if selection == null or not selection.active or layer == null:
        return picture
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null:
        return picture
    # At the picture's density, the layer's own, so on a layer at twice the
    # document's resolution the blend reads each chunk's 512 texels and the
    # selection enlarged to them.
    var side := SaFilterDensity.side_of(layer)
    var original := SaTexture.new(picture.size, picture.format)
    original.clear(Color(0.0, 0.0, 0.0, 0.0))
    for grid_pos: Vector2i in layer.chunks.keys():
        var chunk: SaChunk = layer.chunks[grid_pos]
        var source: SaTexture = chunk.field(SaFieldSpec.ALBEDO) if chunk != null else null
        if source == null or source.size.x != side:
            continue
        SaFilterDensity.copy_share(rd, source, grid_pos, covering, original)
    var mask := SaTexture.new(picture.size, SaSelection.FORMAT)
    mask.clear(Color(0.0, 0.0, 0.0, 0.0))
    var masks := SaFilterDensity.Masks.new()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(covering):
        var source := masks.at(selection.texture_for(grid_pos), side)
        if source == null:
            continue
        SaFilterDensity.copy_share(rd, source, grid_pos, covering, mask)
    var compute := SaCompute.new("apply_masked")
    compute.use_storage_format(original.format)
    compute.set_texture(0, original.rid)
    compute.set_texture(1, picture.rid)
    compute.set_texture(2, mask.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, float(picture.size.x), float(picture.size.y)]))
    compute.dispatch_kernel("apply_masked", SaCompute.groups_for(picture.size.x), SaCompute.groups_for(picture.size.y), 1)
    return original


## A point pass run over a reduced copy of the layer, which is the picture
## [method show_point_pass] shows.
##
## Three steps, each a compute dispatch on the one queue, so every step reads
## what the step before it wrote, which a transfer such as a texture clear
## would not be ordered against. The
## layer's chunks are sampled into a copy of the run's rectangle at most
## [constant REDUCED_SIDE] texels on a side, the selection's likewise when one
## is active, and the recorded kernel then rewrites the copy in place with the
## reduced selection as its mask. That is [SaPointPass]'s own contract with the
## copy standing in for a chunk: the kernel reads binding 0 and stops at its
## edge, and it mixes by the mask itself, so a lasso or a feather shows in the
## picture the way Apply will write it.
##
## Reduced before the pass rather than after it, which is what makes it cheap,
## and exact for a point filter's meaning: every output texel reads only its
## own input texel, so the picture is the filter applied to a smaller layer.
##
## A pass that reads the whole layer is the second picture this makes, for
## [method show_whole_pass], and is reduced after the pass, one chunk at a time,
## for the reason [method whole_picture] gives.
class Reducer:
    extends RefCounted

    const SHADER := "filter_thumbnail"

    ## The kernels that fill the copies, one for the layer's format and one for
    ## the selection's, because switching one instance between the two reloads
    ## its pipelines on every run.
    var _colour: SaCompute = null
    var _coverage: SaCompute = null

    ## The size of the copy of *covering*: its own while its longer side fits
    ## [constant REDUCED_SIDE], and shrunk at its own aspect to fit it
    ## otherwise. Never enlarged, since that costs texels and shows nothing more.
    static func size_for(covering: Vector2i) -> Vector2i:
        if covering.x <= 0 or covering.y <= 0:
            return Vector2i.ZERO
        var longest := maxi(covering.x, covering.y)
        if longest <= REDUCED_SIDE:
            return covering
        var scale := float(REDUCED_SIDE) / float(longest)
        return Vector2i(maxi(1, roundi(covering.x * scale)), maxi(1, roundi(covering.y * scale)))

    ## *ctx*'s point pass over the reduced copy, or null when there is no pass,
    ## no layer or nothing to cover. A neighbourhood pass answers null as well:
    ## its radius is in document pixels, and a copy at a third of the size
    ## would read three times as far.
    func picture(ctx: SaFilterContext) -> SaTexture:
        var recorded: SaPointPass = ctx.point if ctx != null else null
        if recorded == null or recorded is SaNeighbourhoodPass:
            return null
        var document: SaDocument = ctx.document
        var painted: SaLayer = ctx.layer
        var covering := ctx.rect
        var wanted := size_for(covering.size)
        if document == null or painted == null or wanted == Vector2i.ZERO or GlobalShaderCompiler.get_rd() == null:
            return null
        var span := Vector2(covering.size) / Vector2(wanted)
        var stand_in := document.selection.everything()

        var copy := SaTexture.new(wanted, _format_of(painted))
        if _colour == null:
            _colour = SaCompute.new(SHADER)
        _fill(_colour, copy, "reduce_color", _albedo_within(painted, covering), stand_in, span, covering)

        var mask := stand_in
        if document.selection.active:
            mask = SaTexture.new(wanted, SaSelection.FORMAT)
            if _coverage == null:
                _coverage = SaCompute.new(SHADER)
            _fill(_coverage, mask, "reduce_mask", _coverage_within(document.selection, covering), stand_in, span, covering)

        # The context's own instance of the kernel, which Apply and every rerun
        # already share, so the thumbnail loads no pipeline of its own.
        var compute := ctx.kernel(recorded.shader)
        compute.use_storage_format(copy.format)
        compute.set_texture(0, copy.rid)
        compute.set_texture(SaSelection.BINDING, mask.rid)
        recorded.bind(compute)
        # In the context's pieces, since the copy is up to 400 texels on a side
        # and the bound is a chunk's worth.
        SaFilterContext.run_point_in_submits(compute, recorded, Rect2i(Vector2i.ZERO, wanted), Vector2i.ZERO)
        return copy

    ## The layer of *ctx* over the rectangle a run without a margin covers, as
    ## a copy reduced to [method size_for] of it, or null with no layer or
    ## nothing to cover. What the dialog shows before its first run.
    ##
    ## Reduced rather than [method SaFilterContext.layer_pixels], a copy of the
    ## layer at its own size, which on a layer painted over a large canvas is a
    ## texture of hundreds of megabytes, allocated, cleared and filled every
    ## time a dialog opens, for a picture 200 high that the open's own run
    ## replaces at once.
    func layer(ctx: SaFilterContext) -> SaTexture:
        var document: SaDocument = ctx.document if ctx != null else null
        var source: SaLayer = ctx.layer if ctx != null else null
        if document == null or source == null or GlobalShaderCompiler.get_rd() == null:
            return null
        var covering := ctx.rect_for(0)
        var wanted := size_for(covering.size)
        if wanted == Vector2i.ZERO:
            return null
        var copy := SaTexture.new(wanted, _format_of(source))
        if _colour == null:
            _colour = SaCompute.new(SHADER)
        var span := Vector2(covering.size) / Vector2(wanted)
        _fill(_colour, copy, "reduce_color", _albedo_within(source, covering), document.selection.everything(), span, covering)
        return copy

    ## Where *ctx*'s pass that reads the whole layer writes, in document
    ## pixels: the chunks [method SaNeighbourhoodPass.lands_on] answers, which
    ## is the whole canvas for a kaleidoscope, cut to the selection's bounds
    ## when one is active, since Apply writes nothing outside them, and to the
    ## canvas. Empty for any other run.
    static func whole_covering(ctx: SaFilterContext) -> Rect2i:
        var recorded := ctx.point as SaNeighbourhoodPass if ctx != null else null
        var document: SaDocument = ctx.document if ctx != null else null
        var painted: SaLayer = ctx.layer if ctx != null else null
        if recorded == null or not recorded.whole() or document == null or painted == null:
            return Rect2i()
        var cell := Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        var covering := Rect2i()
        for grid_pos: Vector2i in recorded.lands_on(painted.chunks.keys(), document.canvas_size):
            var at := Rect2i(grid_pos * cell, cell)
            covering = at if covering.size == Vector2i.ZERO else covering.merge(at)
        if document.selection.active:
            covering = covering.intersection(document.selection.bounds)
        return covering.intersection(Rect2i(Vector2i.ZERO, document.canvas_size))

    ## *ctx*'s pass that reads the whole layer over *covering*, reduced to
    ## [method size_for] of it, or null when there is no such pass, nothing to
    ## cover or no paint to read.
    ##
    ## Not reduced before the pass, as [method picture] is, because the pass's
    ## numbers are document pixels, a centre or an offset, and a copy at a third
    ## of the size would fold round a point three times too far out. So the
    ## layer is gathered whole at its own size, the one texture the compositor's
    ## chain and Apply gather for the same pass, the pass runs over one chunk at
    ## a time into a scratch of a chunk's size, and each answer is reduced into
    ## the picture over the texels it owns before the next chunk is run. Nothing
    ## past the gather is the size of the layer, and nothing is read back (hard
    ## rules 1 and 2).
    ##
    ## The kernel mixes by the selection itself, as Apply's does, so a chunk the
    ## selection leaves out is run against the empty mask and keeps the layer's
    ## own texels, which is what Apply leaves there. A layer at twice the
    ## document's resolution answers null, since Apply refuses the pass there.
    func whole_picture(ctx: SaFilterContext, covering: Rect2i) -> SaTexture:
        var recorded := ctx.point as SaNeighbourhoodPass if ctx != null else null
        if recorded == null or not recorded.whole():
            return null
        var document: SaDocument = ctx.document
        var painted: SaLayer = ctx.layer
        var wanted := size_for(covering.size)
        if document == null or painted == null or wanted == Vector2i.ZERO or GlobalShaderCompiler.get_rd() == null:
            return null
        var side := SaFilterDensity.side_of(painted)
        if side != SaChunk.SIZE:
            return null
        var format := _format_of(painted)
        var runner := SaNeighbourhoodPass.Runner.new()
        var node := runner.gather(painted.chunks.keys(), painted.get_field, format)
        if node.texture == null:
            return null
        var span := Vector2(covering.size) / Vector2(wanted)
        var selection := document.selection
        var reduced := SaTexture.new(wanted, format)
        if _colour == null:
            _colour = SaCompute.new(SHADER)
        # Cleared through the fill with no chunk, so the clear is a dispatch
        # ordered before the reductions that follow it.
        _fill(_colour, reduced, "reduce_color", {}, selection.everything(), span, covering)
        var filter := RenderingDevice.SAMPLER_FILTER_NEAREST
        if span.x > 1.0 or span.y > 1.0:
            filter = RenderingDevice.SAMPLER_FILTER_LINEAR
        # The context's own instance of the kernel, as the point pass uses.
        var compute := ctx.kernel(recorded.shader)
        var answer := SaTexture.new(Vector2i(side, side), format)
        var masks := SaFilterDensity.Masks.new()
        for grid_pos: Vector2i in recorded.lands_on(painted.chunks.keys(), document.canvas_size):
            var corner := Vector2(grid_pos * SaLayer.CHUNK_SIZE - covering.position)
            var reach := _reach(corner, span, wanted)
            if reach.size.x <= 0 or reach.size.y <= 0:
                continue
            var mask := masks.at(selection.texture_for(grid_pos), side)
            if mask == null:
                mask = selection.nothing()
            runner.run_whole(recorded, compute, answer, node, grid_pos, Rect2i(Vector2i.ZERO, answer.size), mask)
            _colour.use_storage_format(reduced.format)
            _colour.set_texture(0, reduced.rid)
            _colour.set_sampled_texture(1, answer.rid, filter)
            _colour.set_params(_params(reach, span, corner))
            _colour.dispatch_kernel("reduce_color", SaCompute.groups_for(reach.size.x), SaCompute.groups_for(reach.size.y), 1)
        return reduced

    ## Clears *target*, then samples every texture of *sources*, grid position
    ## to texture, into it through *kernel*. The clear is a dispatch and not a
    ## `texture_clear`, which is a transfer and is not ordered against the
    ## compute that follows it. *stand_in* is bound as the sampler when no
    ## chunk is, because the clear declares the binding without reading it.
    static func _fill(
        compute: SaCompute,
        target: SaTexture,
        kernel: String,
        sources: Dictionary,
        stand_in: SaTexture,
        span: Vector2,
        covering: Rect2i
    ) -> void:
        var whole := Rect2i(Vector2i.ZERO, target.size)
        compute.use_storage_format(target.format)
        compute.set_texture(0, target.rid)
        compute.set_sampled_texture(1, stand_in.rid)
        for piece: Rect2i in SaFilterContext.submits(whole):
            compute.set_params(_params(piece, span, Vector2.ZERO))
            compute.dispatch_kernel("reduce_clear", SaCompute.groups_for(piece.size.x), SaCompute.groups_for(piece.size.y), 1)
        if sources.is_empty():
            return
        # Nearest while a texel spans a pixel or less, so a layer small enough
        # to need no reduction is copied exactly rather than blurred by the
        # taps between its pixels.
        var filter := RenderingDevice.SAMPLER_FILTER_NEAREST
        if span.x > 1.0 or span.y > 1.0:
            filter = RenderingDevice.SAMPLER_FILTER_LINEAR
        compute.list_begin(compute.index_of_kernel(kernel))
        for grid_pos: Vector2i in sources:
            var corner := Vector2(grid_pos * SaLayer.CHUNK_SIZE - covering.position)
            var reach := _reach(corner, span, target.size)
            if reach.size.x <= 0 or reach.size.y <= 0:
                continue
            compute.set_sampled_texture(1, (sources[grid_pos] as SaTexture).rid, filter)
            compute.set_params(_params(reach, span, corner))
            compute.list_dispatch(SaCompute.groups_for(reach.size.x), SaCompute.groups_for(reach.size.y), 1)
        compute.list_end()

    ## The target texels a chunk whose corner sits at *corner*, in document
    ## pixels from the covered rectangle's, can own, so its dispatch covers
    ## those and not the whole target (hard rule 2, dirty-rect dispatch only).
    static func _reach(corner: Vector2, span: Vector2, size: Vector2i) -> Rect2i:
        var extent := Vector2(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        var from := Vector2i((corner / span).floor())
        var to := Vector2i(((corner + extent) / span).ceil())
        from = Vector2i(clampi(from.x, 0, size.x), clampi(from.y, 0, size.y))
        to = Vector2i(clampi(to.x, 0, size.x), clampi(to.y, 0, size.y))
        return Rect2i(from, to - from)

    static func _params(region: Rect2i, span: Vector2, corner: Vector2) -> Dictionary:
        return {
            "origin": Vector2(region.position),
            "extent": Vector2(region.size),
            "texel_span": span,
            "chunk_origin": corner,
            "chunk_span": Vector2(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE),
            "spare": Vector2.ZERO,
        }

    ## The layer's colour field in every chunk *covering* reaches. A chunk's
    ## texture may hold fewer pixels than its place on the grid, and the kernel
    ## samples it by where it sits rather than texel by texel, so a chunk at
    ## any resolution reads the same.
    static func _albedo_within(painted: SaLayer, covering: Rect2i) -> Dictionary:
        var found: Dictionary = {}
        for grid_pos: Vector2i in SaChunkWalk.positions_in(covering):
            var chunk: SaChunk = painted.chunks.get(grid_pos, null)
            var albedo := chunk.albedo() if chunk != null else null
            if albedo != null and albedo.rid.is_valid():
                found[grid_pos] = albedo
        return found

    ## The selection's coverage in every chunk *covering* reaches. A position
    ## it holds no chunk at is outside it, which the clear already says.
    static func _coverage_within(selection: SaSelection, covering: Rect2i) -> Dictionary:
        var found: Dictionary = {}
        for grid_pos: Vector2i in SaChunkWalk.positions_in(covering):
            var coverage := selection.texture_for(grid_pos)
            if coverage != null and coverage.rid.is_valid():
                found[grid_pos] = coverage
        return found

    static func _format_of(painted: SaLayer) -> int:
        var spec := SaFieldSpec.find(painted.schema, SaFieldSpec.ALBEDO)
        return spec.format if spec != null else RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
