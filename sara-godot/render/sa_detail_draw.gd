## The canvas's draw of its easel's detail view.
##
## Each display chunk is a `TextureRect` over its grid position's rectangle in
## document pixels, a child of the canvas drawn after its own texture and
## before the overlays, so the zoom, the pan and the rotation carry it with the
## picture. Every one takes the canvas's material (`use_parent_material`), so
## the roll-off, the profiles and the view modes apply to the detail as they do
## to the rest. Its sampler is the canvas's rule at half the canvas's pixels
## per texel: linear below 200%, where a detail texel is smaller than a device
## pixel, and nearest from 200%.
##
## A chunk past the document's edge is cut to the edge through an atlas
## region, the way the output ends there. Hidden while the half size view
## stands in for the canvas and while a relief is up, because the relief is
## sampled at the canvas's UV and a child's UV spans its own chunk.
class_name SaDetailDraw
extends RefCounted

## The parent of every display chunk's rectangle, which the canvas places
## among its own children.
var holder: Control = null
## Grid position to `[TextureRect, SaTexture]`, the texture held so its RID
## outlives the `Texture2DRD` bound to it.
var _drawn: Dictionary = {}
## Textures let go of this frame, dropped at the next sync, for the reason
## `SaEasel` keeps a displaced output for a frame.
var _displaced: Array[SaTexture] = []
var _revision: int = -1


## Builds the holder, drawn with its parent's material.
func _init() -> void:
    holder = Control.new()
    holder.name = "DetailView"
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.use_parent_material = true


## Follows *view* for a canvas of *canvas_size* at *pixels_per_texel*, shown
## when *shown*. Answers whether anything it draws changed.
func sync(view: SaDetailView, canvas_size: Vector2i, pixels_per_texel: float, shown: bool) -> bool:
    _displaced.clear()
    var changed := false
    if view != null and view.revision != _revision:
        _revision = view.revision
        changed = true
        for grid_pos: Vector2i in _drawn.keys():
            var pair: Array = _drawn[grid_pos]
            if view.chunks.get(grid_pos, null) != pair[1]:
                _drop(grid_pos)
        for grid_pos: Vector2i in view.chunks:
            if not _drawn.has(grid_pos):
                _add(grid_pos, view.chunks[grid_pos], canvas_size)
    var filter := SaCanvas.filter_for(pixels_per_texel / SaDetailView.DENSITY)
    for pair: Array in _drawn.values():
        var rect: TextureRect = pair[0]
        if rect.texture_filter != filter:
            rect.texture_filter = filter
            changed = true
    var visible := shown and not _drawn.is_empty()
    if is_instance_valid(holder) and holder.visible != visible:
        holder.visible = visible
        changed = true
    return changed


## How many display chunks are drawn and whether they show, for a state dump.
func report() -> Dictionary:
    var at: Array = []
    for grid_pos: Vector2i in _drawn:
        at.append([grid_pos.x, grid_pos.y])
    at.sort()
    return {"chunks": _drawn.size(), "at": at, "shown": is_instance_valid(holder) and holder.visible}


## Lets go of every rectangle and the textures under them.
func release() -> void:
    for grid_pos: Vector2i in _drawn.keys():
        _drop(grid_pos)
    _displaced.clear()
    _revision = -1


func _add(grid_pos: Vector2i, chunk: SaTexture, canvas_size: Vector2i) -> void:
    if not is_instance_valid(holder):
        return
    var corner := grid_pos * SaLayer.CHUNK_SIZE
    var extent := (canvas_size - corner).min(Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
    if extent.x <= 0 or extent.y <= 0:
        return
    var bound := Texture2DRD.new()
    bound.texture_rd_rid = chunk.rid
    var cut := AtlasTexture.new()
    cut.atlas = bound
    cut.region = Rect2(Vector2.ZERO, Vector2(extent) * SaDetailView.DENSITY)
    var rect := TextureRect.new()
    rect.name = "Detail_%d_%d" % [grid_pos.x, grid_pos.y]
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rect.use_parent_material = true
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_SCALE
    rect.position = Vector2(corner)
    rect.size = Vector2(extent)
    rect.texture = cut
    holder.add_child(rect)
    _drawn[grid_pos] = [rect, chunk]


func _drop(grid_pos: Vector2i) -> void:
    var pair: Array = _drawn[grid_pos]
    _drawn.erase(grid_pos)
    var held: Variant = pair[0]
    if is_instance_valid(held):
        var rect: TextureRect = held
        rect.texture = null
        rect.get_parent().remove_child(rect)
        rect.free()
    _displaced.append(pair[1])
