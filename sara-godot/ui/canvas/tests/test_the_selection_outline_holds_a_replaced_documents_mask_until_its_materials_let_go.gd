## The selection outline keeps the mask of a document that was replaced alive
## until every material it drew through has let go of it.
##
## A door `document` step that reset a 512 by 512 document with a selection
## left sixteen errors in the log, "Texture (binding: 2, index 0) is not a valid
## texture" at `uniform_set_create`, each under the Layers docker's freeing of a
## row. The row was only where the engine noticed. Each chunk of the outline
## draws through a material that names the textures of the chunks around it,
## the reset freed those textures, and the engine rebuilt the materials over
## them at the next texture freed anywhere, which was a row's picture.
##
## The error itself is the engine's and a suite cannot catch it, so what is
## asserted is the order: the mask's textures outlive the reset while the
## outline still names them, and go once the outline has let go.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const CANVAS := Vector2i(1024, 1024)

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "SelectionOutlineLetGoHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = CANVAS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    viewport.add_child(canvas)
    var overlay := SaSelectionOverlay.attach_to(canvas)
    overlay.hold_the_ants()
    return canvas


func _frames(count: int) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    for _i in count:
        await tree.process_frame


func _overlay(canvas: SaCanvas) -> SaSelectionOverlay:
    for child: Node in canvas.get_children():
        if child is SaSelectionOverlay:
            return child
    return null


## The masks of a selection across four chunks, by their RIDs.
func _mask_rids(selection: SaSelection) -> Array[RID]:
    var rids: Array[RID] = []
    for grid_pos: Vector2i in selection.chunks:
        var texture: SaTexture = (selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        if texture != null:
            rids.append(texture.rid)
    return rids


func test_a_reset_leaves_the_mask_alive_until_the_outline_lets_go() -> void:
    var canvas := _canvas()
    var overlay := _overlay(canvas)
    assert_not_null(overlay, "The canvas carries its selection outline")
    var selection := canvas.document.selection
    var side := 0
    selection.select_rect(Rect2i(0, 0, 1, 1))
    for grid_pos: Vector2i in selection.chunks:
        side = (selection.chunks[grid_pos] as SaChunk).pixel_size()
    @warning_ignore("integer_division")
    selection.select_rect(Rect2i(side / 2, side / 2, side, side))
    await _frames(3)
    var rids := _mask_rids(selection)
    assert_eq(rids.size(), 4, "A box over a corner of four chunks holds four masks")
    assert_eq(overlay._drawn.size(), 4, "and the outline draws all four")
    # The suite holds the old selection no longer, so only the outline can.
    selection = null

    var marks: Array = overlay._drawn.values()
    var rd := RenderingServer.get_rendering_device()
    canvas.document.reset_to_default(CANVAS, SaColorSpace.srgb())
    var alive := rids.filter(func(rid: RID) -> bool: return rd.texture_is_valid(rid))
    assert_eq(alive.size(), 4, "The reset leaves every mask the outline's materials name alive")

    # The outline's own frame, run here rather than awaited, so the chunks it
    # lets go of are still waiting for the frame's end and can be read. The
    # error came between this and the frame's end, when anything freed a
    # texture while a chunk's material still named a mask already gone.
    overlay._process(0.0)
    assert_eq(overlay._drawn.size(), 0, "The new document has no selection, so the outline draws no chunk")
    var left := rids.filter(func(rid: RID) -> bool: return rd.texture_is_valid(rid))
    assert_eq(left.size(), 0, "and once it has let go, every mask of the old one is freed")
    for mark: Node in marks:
        assert_true(mark.is_queued_for_deletion(), "Each chunk goes at the frame's end")
        var own := (mark as CanvasItem).material as ShaderMaterial
        for compass: StringName in SaSelectionOverlay.ChunkDraw.NEIGHBOURS:
            assert_null(own.get_shader_parameter(compass), "and its material names no %s mask meanwhile" % compass)


## A chunk the selection stops holding goes the same way, its material
## emptied before its texture is let go.
func test_a_chunk_that_leaves_the_selection_lets_go_of_its_neighbours_first() -> void:
    var canvas := _canvas()
    var overlay := _overlay(canvas)
    var selection := canvas.document.selection
    var side := 0
    selection.select_rect(Rect2i(0, 0, 1, 1))
    for grid_pos: Vector2i in selection.chunks:
        side = (selection.chunks[grid_pos] as SaChunk).pixel_size()
    @warning_ignore("integer_division")
    selection.select_rect(Rect2i(side / 2, 0, side, side / 2))
    await _frames(3)
    assert_eq(overlay._drawn.size(), 2, "A box across one seam draws two chunks")
    var marks: Array = overlay._drawn.values()

    @warning_ignore("integer_division")
    selection.select_rect(Rect2i(0, 0, side / 4, side / 4))
    # The outline's own frame, run here so the chunk it lets go of is still
    # waiting for the frame's end and its material can be read.
    overlay._process(0.0)
    assert_eq(overlay._drawn.size(), 1, "A box inside one chunk draws one")
    var gone := marks.filter(func(mark: Node) -> bool: return not overlay._drawn.values().has(mark))
    assert_eq(gone.size(), 1, "and lets the other go")
    for mark: Node in gone:
        assert_true(mark.is_queued_for_deletion(), "The chunk let go of goes at the frame's end")
        var own := (mark as CanvasItem).material as ShaderMaterial
        for compass: StringName in SaSelectionOverlay.ChunkDraw.NEIGHBOURS:
            assert_null(own.get_shader_parameter(compass), "A chunk let go of names no %s texture" % compass)
