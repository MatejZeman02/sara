## The Brush Editor's scratchpad: a small document of its own on the right of
## the editor, painted by the tool the editor is editing with the settings the
## editor is showing, and thrown away by a button.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why the pad is not `ui/widgets/sa_scratchpad.gd`.** That class exists, taken out
## of the Info docker and kept for exactly this host, and two things about it are
## wrong here rather than wrong in general.
##
## 1. Its `SaCanvas` is a direct child of a box. `SaCanvas._center_canvas` scales
##    and places the picture against `get_viewport().get_visible_rect()`, which
##    inside a dialog is the whole dialog: the pad would be drawn over the page
##    list and the dashboard at whatever scale filled the window. A canvas of its
##    own needs a viewport of its own, so the pad here is a `SubViewport` and the
##    centring arithmetic comes out right without a line of it being rewritten.
## 2. It drives a `ToolMachine`, and a machine announces `EventBus.tool_changed`
##    to the whole application when it registers its first tool. A pad inside a
##    dialog must not tell the toolbox and the tool options bar that the painter
##    switched tools. There is one tool here, the one the editor is editing, so
##    there is nothing for a machine to decide.
##
## **The same stroke path the canvas uses.** The tool instance is the editor's
## own tool script, `handle_input` takes the same events the app pushes at the
## main canvas, and the dabs land in sparse chunks of the pad's own document.
## Nothing is read back, nothing is scaled, and the settings resource is the
## editor's live one rather than a copy, so a slider moved on a page is in the
## next dab without anything having to notice.
##
## **One instance per surface is the rule the tool base class states**, so the
## painter here is a second instance of the same script and never the one the
## main canvas is holding. Sharing the instance would share its stroke state,
## and a pad stroke would land half on the painting.
##
## **The column is the split's second child and never expands**.
## `HSplitContainer` puts a child that does not expand at its minimum width and
## moves the divider by `split_offset` from there, so with a minimum of nought
## the column's width is exactly `-split_offset`, which is the one number
## `SaSplitSnap` keeps and snaps and this class stores in the profile. The pad
## is a `MarginContainer` rather than sitting inside one, because the inset has
## to go to nought when the pad is shut, and a margin is its owner's to write.
@tool
class_name SaEditorScratchpad
extends MarginContainer

## The pad's document, in pixels. Square, and exactly one chunk at the default
## depth, so a doodle costs one allocation and hard rule 3 has nothing to say.
const EDGE: int = 256

## How wide the pad's column is when the profile has no width for it, and the
## floor under a drag, in logical units.
##
## **Half the page column's height, and never more than 0.28 of the editor's
## width**, rather than a share of the width alone, which in a small window
## takes the room the page needs to show its own curve. Following the height
## makes the pad a tall column, its width at most half its height, and the page
## keeps the rest. The editor opens at 1100
## by 700, whose page column is about 540 tall, so the pad is about 270 there,
## very nearly its 256 document. The width's share stays as a ceiling, because a
## window dragged tall and narrow would otherwise hand the pad the page's room.
##
## The floor is where the web's resizers snap: a column dragged under it snaps
## shut rather than showing a sliver, and a shut column dragged back past it
## snaps to the width it had.
const HEIGHT_SHARE: float = 0.5
const WIDTH_SHARE: float = 0.28
const MIN_WIDTH: int = 150

## The gap around the pad's chrome, the same eight every other box in this
## window insets by.
const MARGIN: int = 8

## The four sides the inset is written on.
const SIDES: Array[String] = ["margin_left", "margin_right", "margin_top", "margin_bottom"]


## A view that answers wherever the pad is told the pointer is, and the real
## pointer the rest of the time.
##
## The tool reads its position off the view rather than off the event, which is
## what lets a scenario paint at all: a press injected into a dialog never
## reaches an embedded control, so the door hands the point over here instead.
## `SaPresetThumbs.ThumbView` is the same idea with no hand behind it.
##
## The scripted point is written by the two methods below rather than assigned
## from outside, because a member is its own class's to write.
class PadView:
    extends SaCanvasView

    var _scripted: Variant = null

    ## Built here rather than assigned into from the pad, because the canvas is
    ## this class's member and a member is its own class's to write.
    static func for_pad(pad_canvas: SaCanvas) -> PadView:
        var made := PadView.new()
        made.canvas = pad_canvas
        return made

    func script_to(at: Vector2) -> void:
        _scripted = at

    func stop_scripting() -> void:
        _scripted = null

    func get_document_mouse_position() -> Vector2:
        return _scripted as Vector2 if _scripted != null else super()


var column: VBoxContainer
var view_box: SubViewportContainer
var viewport: SubViewport
var canvas: SaCanvas
var clear_button: Button
var title: Label

## The snap on the split whose grabber the painter drags. The split is a
## constructor argument because the window builds it first and the pad is its
## second child, and a pad built alone, which is every headless test of this
## file, has a snap with no split under it. The width the column snaps back to
## and whether it is shut are the snap's, read from outside as `snap.open_width`
## and `snap.shut`.
var snap: SaSplitSnap = null

## The share, the width a profile with no key gets, and the editor width and
## page height it was taken from.
##
## The two sizes are kept for the dump. A pad that followed the editor and a pad
## that had nothing to follow lay out identically wide, and only the numbers the
## share was taken from tell which of the two a shot shows.
var _share: int = 0
var _editor_width: int = 0
var _page_height: int = 0

## The pad's own surface and the tool instance painting on it. Null until
## [method bind_tool] is given a tool and the canvas has a rendering device
## behind it, which is what a detached window in a headless test has not.
var surface: SaSurface = null
var painter: ToolState = null
var view: PadView = null

## What the pad has been asked to do, for a dump. A picture of a doodle cannot
## say how many strokes drew it, and the whole claim of "no new step on the
## painting" is a count somewhere else staying still.
var strokes: int = 0
var clears: int = 0

## The settings the pad paints with, held rather than copied so a page moved a
## moment ago is in the next dab. The editor's own resource, kept for the dump
## rather than read here: the tool holds the same object.
var _settings: Resource = null


func _init(pad_split: HSplitContainer = null) -> void:
    name = "EditorScratchpad"
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    # Fill and not expand, which is what makes the column's width `-split_offset`
    # rather than a share of the room the page leaves.
    size_flags_horizontal = Control.SIZE_FILL
    snap = SaSplitSnap.new(pad_split, false, MIN_WIDTH, MIN_WIDTH)
    snap.moved.connect(_on_snap_moved)
    _inset(MARGIN)

    column = SaMake.column(self, "ScratchpadColumn", SaTheme.GAP_TIGHT)
    title = SaMake.label(column, "ScratchpadTitle", tr("Scratchpad"))
    # Clipped, so the title's text is not a floor under the drag: a label asks
    # for its text's width and a split refuses to go under a child's minimum.
    title.clip_text = true

    view_box = SubViewportContainer.new()
    view_box.name = "ScratchpadViewport"
    view_box.stretch = true
    view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(view_box)

    viewport = SubViewport.new()
    viewport.name = "ScratchpadSubViewport"
    # Always, because nothing else asks this viewport to redraw: the pad is
    # painted by events rather than by the window's own frame, and an update
    # mode of "when visible" leaves a stroke on a texture nobody draws.
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.transparent_bg = true
    # The pad is a Control tree of its own, so the container's forwarded mouse
    # events have somewhere to land.
    viewport.handle_input_locally = true
    # A size before the container has one, because `SaCanvas._ready` fits itself
    # to the viewport it is in and a container that has not been laid out yet is
    # two pixels square, and the pad's canvas would come out at a zoom of 2/256,
    # a dot on the screen.
    viewport.size = Vector2i(EDGE, EDGE)
    view_box.add_child(viewport)

    canvas = SaCanvas.new()
    canvas.name = "ScratchpadCanvas"
    canvas.canvas_size = Vector2i(EDGE, EDGE)
    viewport.add_child(canvas)

    clear_button = SaMake.button(column, "ScratchpadClear", tr("Clear", "clear the scratchpad"))
    clear_button.clip_text = true
    # Dimmed while the pad holds no stroke, because clearing a blank pad does
    # nothing. A stroke and a clear keep it in step through [method _show_blank].
    _show_blank(true)


func _ready() -> void:
    clear_button.pressed.connect(clear)
    canvas.gui_input.connect(_on_canvas_gui_input)
    # After `SaCanvas._ready`, which connects its own handler first, so the fit
    # below is the last word on where the picture sits. The canvas's own handler
    # moves the picture by half the change in the viewport's size, which is the
    # right answer for a painting the hand has panned and the wrong one for a
    # pad that is always whole and always centred.
    viewport.size_changed.connect(_fit_pad)
    _fit_pad.call_deferred()


## Fills whatever room the column has with the pad, scaled by the longer side
## and centred, so a tall thin column is paint from top to bottom rather than a
## small square in the middle of dead space.
##
## The document stays 256 square, so the fill costs the sides: a column twice as
## high as it is wide shows the middle half of the pad's width, the same strip
## either side, rather than letterboxing by the shorter side, which in a tall
## column draws a small square with a band of nothing above and below it.
##
## `scale` and `position` are `Control`'s own, which the view already reads as
## the zoom and the pan, so this is the same two numbers every other canvas in
## Sara is placed by and not a second idea of where a picture goes.
func _fit_pad() -> void:
    if canvas == null or viewport == null:
        return
    var box := Vector2(viewport.size)
    if box.x <= 0.0 or box.y <= 0.0:
        return
    var factor := maxf(box.x, box.y) / float(EDGE)
    canvas.scale = Vector2(factor, factor)
    canvas.position = (box - Vector2(EDGE, EDGE) * factor) * 0.5


## Points the pad at *tool_script* and *brush_settings*, building its surface and
## its own instance of the tool the first time there is a canvas to build on.
##
## Called from the window's `bind_tool`, which is called again every time the
## editor is opened, so this has to be idempotent: the surface is built once and
## only the tool and the settings are re-pointed.
func bind_tool(tool_script: Script, brush_settings: Resource) -> void:
    _settings = brush_settings
    _ensure_surface()
    if surface == null or tool_script == null:
        return
    if painter == null or painter.get_script() != tool_script:
        var instance: Variant = tool_script.new()
        painter = instance as ToolState
        if painter == null:
            push_warning("SaEditorScratchpad: %s does not extend ToolState" % tool_script.resource_path)
            return
        painter.surface = surface
    # Onto the instance rather than copied into it, which is the difference
    # between a pad that follows the editor and a pad that shows what the editor
    # said when it opened. Assigned once per instance, at its birth, which is
    # the same moment `ToolMachine._rebuild_tools` hands a tool its shared
    # settings: swapping a resource under a tool that has already run is
    # `eraser-paints` and is not what this is.
    if brush_settings != null and "settings" in painter:
        painter.settings = brush_settings


## Builds the surface, once, as soon as the canvas has an easel behind it. A
## window built detached, which is every headless test of this editor, never
## gets that far and never needs to.
func _ensure_surface() -> void:
    if surface != null or canvas == null or not canvas.is_inside_tree():
        return
    var easel := canvas.ensure_easel()
    if easel == null or easel.document == null:
        return
    view = PadView.for_pad(canvas)
    surface = SaSurface.create(&"brush_editor_pad", easel, view)
    # The pad offers one tool and never a tool list, so this says what it is
    # rather than what it filters: a second surface, not the painting.
    surface.is_embedded = true


## Throws the pad's painting away. Not undoable, and not the painting's history:
## the pad is its own document, so there is no step to add anywhere.
func clear() -> void:
    _show_blank(true)
    if canvas == null or canvas.document == null:
        return
    canvas.document.clear_layer()
    if canvas.document.stroke_layer != null:
        canvas.document.stroke_layer.chunks.clear()
    canvas.document.invalidate_all_allocated_chunks()
    canvas.request_composite()
    clears += 1


## Whether the pad holds nothing to clear, said on the Clear button. A flag
## rather than a count of the layer's chunks, because a clear fills the layer
## with nothing and keeps every chunk it had.
func _show_blank(blank: bool) -> void:
    clear_button.disabled = blank


## The width this column takes when the profile has none for it, from the
## editor's own logical width and the height of the page column beside the pad.
##
## The pad is sized by the editor and the editor is resizable, so the share is
## recomputed rather than fixed: a painter who never touched the grabber and
## drags the dialog taller gets a wider pad. A painter who did drag it keeps
## what they dragged, which [method restore_width] applies.
##
## *page_height* nought is a page nobody has measured, which is a pad built
## alone in a test, and the width's share answers by itself then.
##
## **Called on every resize of the editor and not only on an open**. Until then
## the only two callers were the pad's construction and `bind_tool`, both of
## which pass the dialog's `logical_size`, which is what the constructor set and
## never follows a drag. The window's `size_changed` calls this so the share
## follows whatever the painter does to the window.
func size_to_editor(editor_logical_width: int, page_height: int = 0) -> void:
    if editor_logical_width <= 0:
        return
    _editor_width = editor_logical_width
    _page_height = maxi(0, page_height)
    var share := int(round(float(editor_logical_width) * WIDTH_SHARE))
    if _page_height > 0:
        share = mini(share, int(round(float(_page_height) * HEIGHT_SHARE)))
    _share = maxi(MIN_WIDTH, share)
    if SaSettings.brush_editor_pad_width <= 0:
        snap.restore(_share, snap.shut)
    _lay_out()


## Reads the profile's width and shut state and lays the column out to them.
## Called on every open of the editor, which is what "reopens with the offset
## kept" means when the window stays in the tree between opens.
func restore_width() -> void:
    var stored: int = SaSettings.brush_editor_pad_width
    snap.restore(stored if stored > 0 else _share, SaSettings.brush_editor_pad_shut)
    _lay_out()


## `{"drag": 0}`, the grabber dragged to the column's width in logical units,
## through the same handler a hand's drag reaches. Nought is the right edge.
func drag_to(width: int) -> void:
    snap.drag_to(width)


## The snap moved, by a hand on the grabber or a scenario's drag: the profile
## follows the column, and the inset and the chrome follow the state. Shut is
## offset nought and no inset, so the page has the whole width and nothing of
## the pad is left to see.
func _on_snap_moved(open_width: int, shut: bool) -> void:
    SaSettings.brush_editor_pad_width = open_width
    SaSettings.brush_editor_pad_shut = shut
    _lay_out()


## Puts the inset and the chrome where the snap's state says.
func _lay_out() -> void:
    _inset(0 if snap.shut else MARGIN)
    if column != null:
        column.visible = not snap.shut


func _inset(logical: int) -> void:
    for side in SIDES:
        add_theme_constant_override(side, SaUI.px(logical))


func _on_canvas_gui_input(event: InputEvent) -> void:
    if painter == null:
        return
    # Whatever the hand does goes at the real pointer, so a scripted point left
    # over from a `paint` step cannot answer for it.
    if view != null:
        view.stop_scripting()
    painter.handle_input(event)
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
        _show_blank(false)


# --- What the door drives -----------------------------------------------------


## `{"paint": {"from": [x, y], "to": [x, y], "pressure": 0.9, "steps": 24}}` and
## `{"clear": true}`, in document pixels of the pad. `{"drag": 0}` is the
## grabber dragged to a column width in logical units, and
## `{"editor_size": [w, h]}` the editor's own window resized, in the same units.
##
## A helper rather than a click, for the reason `brush_editor_capture.gd` gives
## for every other step it holds: the editor is its own `Window` and an injected
## press never reaches a control inside one. What this proves is the path from
## the tool's `handle_input` onwards, which is everything except the pixel the
## pointer landed on.
func scratch_step(spec: Dictionary) -> void:
    if spec.has("editor_size"):
        resize_editor(spec["editor_size"] as Array)
    if spec.has("drag"):
        drag_to(int(spec["drag"]))
    if spec.has("paint"):
        paint(spec["paint"] as Dictionary)
    if spec.has("clear"):
        clear()


## Resizes the window the pad is in to *logical* units, the way a hand on the
## dialog's corner does, so a scenario can make the editor tall and shoot the
## column. The dialog's own `logical_size` is what its constructor set and
## does not follow a drag, so it is not written here either. Centred again
## afterwards, because a corner drag grows a window down and off the screen
## and the shot has to hold the whole column.
func resize_editor(logical: Array) -> void:
    var window := get_window()
    if window == null or logical.size() < 2:
        return
    var wanted := Vector2i(int(logical[0]), int(logical[1]))
    if wanted.x <= 0 or wanted.y <= 0:
        return
    window.size = SaUI.window_size_for(window, wanted)
    var room := window.get_parent().get_viewport().get_visible_rect().size if window.get_parent() != null else Vector2()
    if room.x > 0.0 and room.y > 0.0:
        window.position = Vector2i((room - Vector2(window.size)) * 0.5)


## Walks one straight stroke across the pad, press, motions, release, the same
## three kinds of event the app pushes at a tool.
##
## The view is moved before each event rather than after it, because the tool
## reads the position off the view and the pressure off the event, and the app's
## own input path arrives in that order.
func paint(spec: Dictionary) -> void:
    _ensure_surface()
    if painter == null or view == null:
        push_warning("SaEditorScratchpad: nothing bound, so there is nothing to paint with")
        return
    var from := _point(spec.get("from", []), Vector2(float(EDGE) * 0.2, float(EDGE) * 0.5))
    var to := _point(spec.get("to", []), Vector2(float(EDGE) * 0.8, float(EDGE) * 0.5))
    var pressure := float(spec.get("pressure", 0.9))
    var steps: int = maxi(int(spec.get("steps", 24)), 1)

    view.script_to(from)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    press.global_position = from
    painter.handle_input(press)

    for i in range(1, steps + 1):
        var at := from.lerp(to, float(i) / float(steps))
        view.script_to(at)
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.global_position = at
        # Not decoration: the brush treats a pointer as a tablet until eleven
        # zero-pressure motions say otherwise, and a tablet stroke at zero
        # pressure paints a full-size dab at no alpha. The `stroke` step carries
        # the same paragraph for the same reason.
        motion.pressure = pressure
        painter.handle_input(motion)

    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = to
    release.global_position = to
    painter.handle_input(release)
    view.stop_scripting()
    strokes += 1
    _show_blank(false)

    if canvas.document != null:
        canvas.document.commit_stroke()
    canvas.request_composite()


func _point(raw: Variant, fallback: Vector2) -> Vector2:
    var coords := raw as Array
    if coords == null or coords.size() < 2:
        return fallback
    return Vector2(float(coords[0]), float(coords[1]))


## What the pad tells the editor's own report about itself.
##
## The document's size and the chunks it has allocated, because a pad that
## painted is a pad with a chunk, and the two counters, because the claim
## to check is that the painting's history did not move while these
## did.
func pad_report() -> Dictionary:
    var document := canvas.document if canvas != null else null
    return {
        "bound": painter != null,
        "settings": _settings != null,
        "strokes": strokes,
        "clears": clears,
        # Whether Clear is offered, which a shot shows as a shade of grey and
        # this says as a word.
        "clear_disabled": clear_button.disabled if clear_button != null else true,
        "size": {"x": EDGE, "y": EDGE},
        # The column as laid out, the width it snaps back to, and whether it is
        # shut, because a shot of a pad that is gone is a shot of the page and
        # only the numbers say the pad is a drag away.
        "width": int(size.x),
        "height": int(size.y),
        "open_width": snap.open_width,
        "shut": snap.shut,
        # The share and the editor width and page height it came from, because
        # a column at the width a painter dragged and a column at the share look
        # the same and only these numbers say which is which.
        "share": _share,
        "editor_width": _editor_width,
        "page_height": _page_height,
        "split_offset": snap.split.split_offset if snap.split != null else 0,
        "box": {"x": viewport.size.x, "y": viewport.size.y} if viewport != null else {},
        "zoom": canvas.scale.x if canvas != null else 0.0,
        "chunks": document.active_layer.chunks.size() if document != null and document.active_layer != null else 0,
        "visible": is_visible_in_tree(),
    }
