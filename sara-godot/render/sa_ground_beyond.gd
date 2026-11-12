## What the canvas draws behind its page: the checkerboard inside the page and
## the ground beyond it.
##
## **The page ends while the canvas is bounded.** The bottom ground, a Paper, a
## Canvas or a Background, is the composited picture inside the page, and the
## view shows the backdrop around it, so the page's edge is where the painting
## ends. A ground drawn past the edge of a bounded page made a plain document
## look endless and hid the edge a painter frames a picture by.
##
## **A ground with an Edge ends the sheet past a bounded page.** A Deckle, a
## Torn, a Cut or a Wrapped edge lies wholly outside the page
## (`ground_edge.gdshaderinc`), so [member beyond] is shown on a bounded page
## while its ground asks for an edge, and the shader leaves it transparent past
## the edge's reach, where the backdrop shows as it does round a page with no
## edge.
##
## **The edge goes while the infinite canvas is on.** The page then grows by
## whole chunks under the paint (`SaInfiniteCanvas`), and its rectangle is
## kept for export and every reader but never shown: [member beyond] draws the
## same generator with the same parameters past it, its edge excepted, so the
## ground runs on across the old rectangle and a stroke can start anywhere the
## painter sees paper.
##
## [member beyond] is a child behind the checkerboard, so large in document
## pixels that it reaches the viewport's edges at any zoom. A child rather than
## a sibling in view space, so it turns and scales with the document and the
## ground's pattern stays continuous across the edge. A wrap's tiles show the
## ground repeated with the picture and need nothing from here.
class_name SaGroundBeyond
extends RefCounted

## Half the side of [member beyond] in document pixels, larger than any zoom
## shows.
const REACH: float = 1.0e6

## The transparency pattern drawn inside the page.
const CHECKER: Shader = preload("res://shaders/canvas/checkerboard.gdshader")

## The node's name under the canvas, which a suite finds it by.
const NODE_NAME := "BackgroundBeyond"

## The ground's parameter and the view shader's uniform for its edge, nought
## for none.
const EDGE := "edge"

## The ground past the page, shown while the infinite canvas is on or the
## ground has an edge to draw there.
var beyond: ColorRect = null

## The transparency checkerboard over the page's own rectangle.
var checkerboard: ColorRect = null

## What [member beyond] was last synced from, so a frame costs a compare.
var _state: Array = []


## Builds both and places them under *canvas*, the checkerboard over a page of
## *page_size* and [member beyond] first among the canvas's children so the
## checkerboard draws over it inside the page. Nothing here keeps the canvas.
static func place_under(canvas: Control, page_size: Vector2i) -> SaGroundBeyond:
    var behind := SaGroundBeyond.new()
    behind.checkerboard = ColorRect.new()
    var board := behind.checkerboard
    board.set_anchors_preset(Control.PRESET_FULL_RECT)
    board.show_behind_parent = true
    board.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var checker_material := ShaderMaterial.new()
    checker_material.shader = CHECKER
    checker_material.set_shader_parameter("canvas_size", Vector2(page_size))
    board.material = checker_material
    canvas.add_child(board)

    behind.beyond = ColorRect.new()
    var rect := behind.beyond
    rect.name = NODE_NAME
    rect.show_behind_parent = true
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rect.position = Vector2(-REACH, -REACH)
    rect.size = Vector2(2.0 * REACH, 2.0 * REACH)
    rect.visible = false
    canvas.add_child(rect)
    canvas.move_child(rect, 0)
    return behind


## Points [member beyond] at *document*'s bottom-most ground and shows it while
## the infinite canvas is on or the ground has an edge, hidden otherwise. With
## the infinite canvas on the edge is told nought, because the page's rectangle
## is never shown then. The material is kept up to date either way, so turning
## the switch on shows the ground at the zoom of the moment. True when anything
## changed, which a zoom or the switch is.
func sync(document: SaDocument, pixels_per_texel: float) -> bool:
    if document == null:
        return false
    var state := SaGeneratedLayer.view_state(document, pixels_per_texel)
    var reaches := _reaches_past(document)
    state.append(reaches)
    if state == _state:
        return false
    _state = state
    SaGeneratedLayer.apply_view(beyond, document, pixels_per_texel)
    var shaded := beyond.material as ShaderMaterial
    if reaches and shaded != null:
        shaded.set_shader_parameter(EDGE, 0.0)
    beyond.visible = beyond.visible and (reaches or _edged(document))
    return true


## Tells both the page's new size after a resize or a grow.
func resize(page_size: Vector2i) -> void:
    for rect: ColorRect in [checkerboard, beyond]:
        var shaded := rect.material as ShaderMaterial
        if shaded != null:
            shaded.set_shader_parameter("canvas_size", Vector2(page_size))


## What a dump reads: whether the ground reaches past the page, and whether it
## is drawn there now, which a half size view standing in may hide.
func report(document: SaDocument) -> Dictionary:
    return {"reaches_past_page": _reaches_past(document), "visible": beyond.visible}


## Whether *document*'s ground runs past its page, which is while its infinite
## canvas is on.
static func _reaches_past(document: SaDocument) -> bool:
    return document != null and document.infinite_canvas != null and document.infinite_canvas.on


## Whether *document*'s ground ends its sheet in an edge drawn past the page.
static func _edged(document: SaDocument) -> bool:
    var source := SaGeneratedLayer.view_source(document)
    return source != null and SaTyped.real(source.generator_params.get(EDGE, 0.0), 0.0) > 0.5
