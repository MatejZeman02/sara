## The status line: the document's name and the tool in hand, the zoom as two
## figures, the document's size and its colour space, and why a stroke changed
## nothing when one did, in a bar along the bottom edge of the main window.
##
## The Info docker has the size and the space but no zoom, and a docker is
## something a painter closes. Krita, Photoshop and Clip Studio all keep these
## words on the bottom edge, so a painter coming from any of them looks there
## first.
##
## The bar joins `SaCanvasView.COVER_GROUP`, the way the top bar does, so Fit
## and Center place the document in what the two leave between them rather
## than with its bottom rows under the words.
##
## The words sit in the middle of the line. The default layout stands a docker
## at each bottom corner, which is what `SaNotice` found as well, and the middle
## is the one part of the edge no docker of it covers.
##
## What it follows is the view's `transform_changed`, the document's own news
## (a colour space, a resize, a file opened), and the canvas's rectangle. The
## last is there because the fit a new document gets is written onto the
## canvas's scale by `SaCanvas._center_canvas`, which never goes through the
## view, so with `transform_changed` alone File > New would leave the zoom of
## the document before it on the line. A burst of these costs one reading at the
## end of the frame. That is also when File > New has both its space and its
## size: the space is announced first, before the document has its new size.
##
## **The zoom is two figures**, one about the pixels and one about the zoom
## level. Zoom is the picture's size on screen, 100% being the whole
## picture fitted between the bars and the dockers, `SaView.zoom_per_cent`.
## Screen is device pixels a texel, the zoom over `SaView.actual_pixel_zoom`,
## named Screen rather than Pixels, which does not say what it measures.
## Zoom is measured against the free rectangle, so the line follows what moves
## that as well: a docker shown, hidden, resized or dragged, a cover resized and
## the window resized, with the picture staying where it is.
##
## **The document and the tool come first**, because a painter refused a
## Liquify preset with the Bucket in hand by accident has otherwise nothing on
## the screen that says so. The document reads as its tab does, the
## unsaved star included, and the tool as its toolbox button's tooltip names
## it, without the chord. The tool is read off the surface's own machine at
## every reading, so a quick tool held on a key shows while it is held, and the
## scratchpad's machine, which announces on the same bus, never names its tool
## here. A name wider than the room the other words leave is cut with an
## ellipsis and shows whole in its tooltip, the document's first.
##
## **It can be hidden**, from View > Show Status Line or a chord bound to the
## command of that name, because it takes space on the canvas to show what the
## Info docker shows too. A hidden line is not visible in the tree,
## which is what `SaCanvasView.get_visible_rect` asks of a cover, so the next Fit
## or Center puts the document over the rows it held.
##
## The answer is a profile's element visibility rather than a property of
## `SaSettings`, the store a docker's parts already keep theirs in, so it
## survives a restart and follows a switch of profile with no new setting,
## rather than the way of the top bar's own two sections, which nothing
## remembers and which come back on every launch.
class_name SaStatusLine
extends PanelContainer

## The bar's height, in logical units. It grows with its text when a larger
## font size needs more, and never shrinks below this.
const HEIGHT: int = 24

## The words' size as a fraction of the interface font, through the meta the
## theme pass reads. At the full 20 a line of 24 has no room above and below
## its text, and these are words a painter glances at rather than reads.
const FONT_SCALE: float = 0.7

## Where the profile keeps whether the line is shown, as a category and an
## element of `SaSettings.get_element_visible`. Shown unless a profile says not.
const SETTING_CATEGORY := "StatusLine"
const SETTING_ELEMENT := "Shown"

## The command View > Show Status Line runs, and the one a chord binds.
const COMMAND := &"view_status_line"

## How long the line a save ended with stays on, in seconds.
const SAVED_SECONDS := 4.0

## The words, each made through `SaMake` so a scenario reads them by name.
var document_label: Label
var tool_label: Label
var zoom_label: Label
var pixels_label: Label
var size_label: Label
var space_label: Label
## Why the last stroke changed nothing, said once by `SaStrokeNote` and hidden
## while there is nothing to say. On this line because it is
## where a painter already looks for the state the pen does not show.
var note_label: Label
var _note_separator: Control
## How far a save running in the background has gone, and that it ended, with
## its separator. `SaSadSave` says it through `EventBus.save_progressed`.
var save_label: Label
var _save_separator: Control
## That a script holds the lock on the mouse and the pen, with its separator,
## so a painter whose mouse does nothing is told why. `SaPointerLock` says it
## through `EventBus.pointer_lock_changed`.
var lock_label: Label
var _lock_separator: Control
## Hides the line a save ended with after [constant SAVED_SECONDS].
var _save_timer: Timer

## `func() -> SaSurface`, asked at every reading. The main canvas builds its
## surface only when the tools are bound, after the modules load and long after
## this bar, so the bar is handed the question rather than the answer.
var _surface_of: Callable

## The view and the canvas this is connected to, kept so the connections are
## made once and dropped when a different surface answers.
var _view: SaView = null
var _canvas: Control = null

## The covers and the dockers this line hears resize, so each is connected
## once. A freed one stays listed, and its connections went with it.
var _rooms: Array[Node] = []

## The row the words stand in, whose room the two names share.
var _words: HBoxContainer

## The document whose star and name the line hears, kept so it is connected
## once and let go when another document is in front.
var _heard_document: SaDocument = null

## A reading is already waiting for the end of the frame.
var _queued: bool = false

## The line's height the last time it laid out, in logical units, and
## [constant HEIGHT] before any line has. Static, because the layout store asks
## it of no node: there is one line in the main window. Written here only.
static var _height: int = HEIGHT


func _init(surface_of: Callable) -> void:
    name = "StatusLine"
    _surface_of = surface_of
    add_to_group(SaCanvasView.COVER_GROUP)
    set_meta(SaUI.FONT_SCALE_META, FONT_SCALE)
    anchor_left = 0.0
    anchor_right = 1.0
    anchor_top = 1.0
    anchor_bottom = 1.0
    offset_top = -float(SaUI.px(HEIGHT))
    offset_bottom = 0.0
    grow_vertical = Control.GROW_DIRECTION_BEGIN
    custom_minimum_size = Vector2(0.0, float(SaUI.px(HEIGHT)))

    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_primary", "border_color": "border_primary"})
    style.border_width_top = 1
    style.content_margin_left = float(SaUI.px(SaTheme.GAP))
    style.content_margin_right = float(SaUI.px(SaTheme.GAP))
    add_theme_stylebox_override("panel", style)

    var words := SaMake.row(self, "Words", SaTheme.PAD)
    words.alignment = BoxContainer.ALIGNMENT_CENTER
    words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _words = words
    document_label = _name_word(words, "StatusDocument")
    SaMake.separator(words, "DocumentToolSeparator", true)
    tool_label = _name_word(words, "StatusTool")
    SaMake.separator(words, "ToolZoomSeparator", true)
    zoom_label = _word(
        words,
        "StatusZoom",
        (
            "The picture's size on screen. At 100% the whole picture fits between the bars and the dockers, so the "
            + "figure moves when a docker column opens or closes while the picture stays where it is."
        )
    )
    SaMake.separator(words, "ZoomPixelsSeparator", true)
    pixels_label = _word(
        words,
        "StatusPixels",
        "Pixels of the screen per pixel of the painting. At 100% one pixel of the painting is one pixel of the screen."
    )
    SaMake.separator(words, "ZoomSizeSeparator", true)
    size_label = _word(words, "StatusSize", "The painting's width and height in pixels.")
    SaMake.separator(words, "SizeSpaceSeparator", true)
    space_label = _word(
        words, "StatusSpace", "The colour space the painting's numbers are in, and whether they are kept as 16 or 32 bit floats."
    )
    _note_separator = SaMake.separator(words, "SpaceNoteSeparator", true)
    note_label = _word(words, "StatusNote", "Why the last stroke changed nothing.")
    show_note("")
    _save_separator = SaMake.separator(words, "NoteSaveSeparator", true)
    save_label = _word(words, "StatusSave", "A save running in the background, and when it ended.")
    _save_timer = Timer.new()
    _save_timer.one_shot = true
    _save_timer.timeout.connect(show_save.bind(""))
    add_child(_save_timer)
    _lock_separator = SaMake.separator(words, "SaveLockSeparator", true)
    var lock_why := "An agent is working through the door, so Sara does not listen to the mouse or the pen until it lets go."
    lock_label = _word(words, "StatusLock", lock_why)
    show_lock(SaCursorPolicy.system_pointer_locked, "")
    show_save("")


func _ready() -> void:
    SaUI.apply_ui_theme(self)
    EventBus.ui_scale_changed.connect(_on_text_resized)
    EventBus.ui_font_scale_changed.connect(_on_text_resized)
    EventBus.boot_finished.connect(follow)
    EventBus.document_loaded.connect(follow)
    EventBus.active_document_changed.connect(_on_front_changed)
    EventBus.tool_changed.connect(_on_tool_changed)
    EventBus.document_color_space_changed.connect(_on_document_space_changed)
    EventBus.document_resized.connect(_on_document_news)
    EventBus.stroke_explained.connect(show_note)
    EventBus.save_progressed.connect(show_save)
    EventBus.pointer_lock_changed.connect(show_lock)
    EventBus.docker_layout_changed.connect(queue_refresh)
    # The window's size moves the free rectangle the Zoom figure is read
    # against. A suite that calls this by hand has no viewport to hear.
    if get_viewport() != null:
        get_viewport().size_changed.connect(queue_refresh)
    SaSettings.profile_changed.connect(_follow_setting)
    _follow_setting()
    follow()


## Finds the surface's view and canvas, connects to them the first time they are
## seen, and reads the three words again at the end of the frame. What boot and
## every opened document call. The document `document_loaded` carries is not
## read, the surface is what is asked.
func follow(_document: SaDocument = null) -> void:
    var surface := _surface()
    var view: SaView = surface.view if surface != null else null
    if view != _view:
        if _view != null and _view.transform_changed.is_connected(queue_refresh):
            _view.transform_changed.disconnect(queue_refresh)
        _view = view
        if _view != null:
            _view.transform_changed.connect(queue_refresh)
    var canvas_view := view as SaCanvasView
    var canvas: Control = canvas_view.canvas if canvas_view != null else null
    if not is_instance_valid(_canvas) or canvas != _canvas:
        if is_instance_valid(_canvas) and _canvas.item_rect_changed.is_connected(queue_refresh):
            _canvas.item_rect_changed.disconnect(queue_refresh)
        _canvas = canvas
        if _canvas != null:
            _canvas.item_rect_changed.connect(queue_refresh)
    _hear_rooms()
    queue_refresh()


## Connects to every cover and docker that moves the free rectangle and is not
## connected yet. On every `follow`, because boot ends after the dockers are
## built and a module's docker can arrive with a later document.
func _hear_rooms() -> void:
    if not is_inside_tree():
        return
    for node in get_tree().get_nodes_in_group(SaCanvasView.COVER_GROUP):
        var cover := node as Control
        if cover != null and cover != self and not _rooms.has(cover):
            _rooms.append(cover)
            cover.resized.connect(queue_refresh)
            cover.visibility_changed.connect(queue_refresh)
    for node in get_tree().get_nodes_in_group(SaCanvasView.SIDE_COVER_GROUP):
        var side := node as Window
        if side != null and not _rooms.has(side):
            _rooms.append(side)
            side.size_changed.connect(queue_refresh)
            side.visibility_changed.connect(queue_refresh)


## Asks for a reading at the end of the frame, once however often it is asked.
func queue_refresh() -> void:
    if _queued:
        return
    _queued = true
    refresh.call_deferred()


## Writes the three words from the surface as it is now. Public so a suite can
## take the reading a change queued without awaiting a frame.
func refresh() -> void:
    _queued = false
    var surface := _surface()
    var document: SaDocument = SaSurface.document_of(surface)
    var view: SaView = surface.view if surface != null else null
    _hear_document(document)
    _show_name(document_label, document_text(document))
    _show_name(tool_label, tool_text(surface.tool_machine if surface != null else null))
    zoom_label.text = zoom_text(view, surface.get_canvas_size() if surface != null else Vector2i.ZERO)
    pixels_label.text = pixels_text(view)
    size_label.text = size_text(document)
    space_label.text = space_text(document.color_space if document != null else null)
    fit_names()


## Shares the room the other words leave between the two names. The tool's name
## is given its whole width first and the document's takes what is left, so a
## long file name is the one cut. What a resize of the line calls as well.
func fit_names() -> void:
    var room := size.x - get_theme_stylebox("panel").get_minimum_size().x
    var separation := _words.get_theme_constant("separation")
    var shown := 0
    for child: Node in _words.get_children():
        var word := child as Control
        if word == null or not word.visible:
            continue
        shown += 1
        if word != document_label and word != tool_label:
            room -= word.get_combined_minimum_size().x
    room -= float(separation * maxi(shown - 1, 0))
    var widths := share_room(room, _text_width(document_label), _text_width(tool_label), _text_width(document_label, "…"))
    document_label.custom_minimum_size.x = widths.x
    tool_label.custom_minimum_size.x = widths.y


## The widths the document's name and the tool's take of *room*, as x and y,
## from the widths their whole names would. The tool keeps its whole name while
## the room leaves the document *floor*, an ellipsis, and the document has the
## rest, never less than the floor.
static func share_room(room: float, document_width: float, tool_width: float, floor_width: float) -> Vector2:
    var tool_share := minf(tool_width, maxf(room - floor_width, floor_width))
    var document_share := minf(document_width, maxf(room - tool_share, floor_width))
    return Vector2(document_share, tool_share)


## The document's name as its tab reads it, with the star of unsaved changes.
## Empty with no document.
static func document_text(document: SaDocument) -> String:
    if document == null:
        return ""
    return SaDocumentLabel.text_for(SaDocumentLabel.file_name_of(document), document.modified, false)


## The name of the tool in *machine*'s hand as its toolbox button's tooltip
## gives it, translated, so a brush engine reads as the Brush it paints as.
## Empty with no machine or no tool.
static func tool_text(machine: Variant) -> String:
    var held := machine as ToolMachine if machine is ToolMachine else null
    if held == null or String(held.active_tool_name).is_empty():
        return ""
    var id := SaToolRegistry.tool_in(held.registry, held.active_tool_name)
    var descriptor := held.get_descriptor(id)
    if descriptor == null or descriptor.display_name.is_empty():
        return String(id)
    return TranslationServer.translate(descriptor.display_name)


## Shows *line* as the note, or hides the note and its separator when it is
## empty.
func show_note(line: String) -> void:
    note_label.text = line
    note_label.visible = not line.is_empty()
    _note_separator.visible = note_label.visible


## Shows *line* as the save's progress, or hides it when it is empty. A line
## that is not a share, the one a save ended with, goes after a few seconds.
func show_save(line: String) -> void:
    save_label.text = line
    save_label.visible = not line.is_empty()
    _save_separator.visible = save_label.visible
    if _save_timer.is_inside_tree():
        _save_timer.stop()
        if not line.is_empty() and not line.ends_with("%"):
            _save_timer.start(SAVED_SECONDS)


## Shows that the mouse and the pen are locked while *locked*, and hides the
## word and its separator once they are not. *by* is who holds the lock, said
## in the tooltip.
func show_lock(locked: bool, by: String) -> void:
    lock_label.text = String(TranslationServer.translate("Mouse locked")) if locked else ""
    lock_label.visible = locked
    _lock_separator.visible = locked
    if by.is_empty():
        lock_label.tooltip_text = TranslationServer.translate(
            "An agent is working through the door, so Sara does not listen to the mouse or the pen until it lets go."
        )
        return
    lock_label.tooltip_text = (
        TranslationServer.translate(
            "%s is working through the door, so Sara does not listen to the mouse or the pen until it lets go."
        )
        % by
    )


## The Zoom figure for a document of *document_size*, the picture's size on
## screen against the whole picture fitted into the free rectangle, so Fit to
## View reads 100% and Ctrl+0 its Size. Empty with no view or no document.
static func zoom_text(view: SaView, document_size: Vector2i) -> String:
    var per_cent := view.zoom_per_cent(document_size) if view != null else 0.0
    if per_cent <= 0.0:
        return ""
    return TranslationServer.translate("Zoom %s%%") % per_cent_text(per_cent)


## The Screen figure, device pixels a texel, so Actual Pixels reads 100% at
## every interface scale.
##
## The Zoom figure is the one relative to the fit, so this one stays honest
## about the pixels.
static func pixels_text(view: SaView) -> String:
    if view == null:
        return ""
    var per_cent := view.get_zoom() / view.actual_pixel_zoom() * 100.0
    return TranslationServer.translate("Screen %s%%") % per_cent_text(per_cent)


## Whole per cents from 10 up and a tenth below, where a whole one would read
## 1% for everything between 0.5 and 1.5.
static func per_cent_text(per_cent: float) -> String:
    return "%d" % roundi(per_cent) if per_cent >= 10.0 else "%.1f" % per_cent


## The size in the words the Export dialog prints it in.
static func size_text(document: SaDocument) -> String:
    if document == null:
        return ""
    var canvas := document.canvas_size
    return TranslationServer.translate_plural("%d x %d px", "%d x %d px", canvas.y) % [canvas.x, canvas.y]


## The space's name and its depth. A space no preset names is called by its
## gamut, and read in Oklab it says so, the shape the presets' own names take.
static func space_text(space: SaColorSpace) -> String:
    if space == null:
        return ""
    var named := TranslationServer.translate(SaColorSpace.display_name(space.id))
    if space.id == SaColorSpace.ID_CUSTOM:
        var gamut := SaColorNames.gamut_name(space.primaries)
        if gamut != SaColorNames.CUSTOM_NAME:
            var in_oklab := space.coordinates == SaColorSpace.Coordinates.OKLAB
            named = TranslationServer.translate("Oklab over %s") % gamut if in_oklab else gamut
    return "%s, %s" % [named, SaInfoSection.depth_text(space)]


## Whether the profile shows the line.
static func shown_in_profile() -> bool:
    return SaSettings.get_element_visible(SETTING_CATEGORY, SETTING_ELEMENT)


## The rows the line takes from the window's foot, in logical units, and none
## while the profile hides it, the floor no docker of a shipped layout reaches
## past. Its own height rather than [constant HEIGHT], since at a font size of
## 1.6 the line is 29 rows and starts at y 995 on a window 1024 tall.
static func rows_taken() -> int:
    return _height if shown_in_profile() else 0


## Registers Show Status Line, a check row and a command a chord can be bound to.
## No chord of its own, because the line is a thing a painter sets once.
static func register_command(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(COMMAND, "Show the status line", _flip)
    command.label = "Show Status Line"
    command.category = &"view"
    command.sentence = "Show the zoom, size and colour space at the bottom of the window."
    command.checked = shown_in_profile
    ctx.register_command(command)


static func _flip() -> bool:
    SaSettings.set_element_visible(SETTING_CATEGORY, SETTING_ELEMENT, not shown_in_profile())
    return true


## Shows or hides the line as the profile says. On `profile_changed`, which the
## command's write emits and which a switch of profile emits as well.
func _follow_setting() -> void:
    visible = shown_in_profile()


func _surface() -> SaSurface:
    if not _surface_of.is_valid():
        return null
    var found: Variant = _surface_of.call()
    return found as SaSurface if found is SaSurface else null


## A name the line cuts with an ellipsis when the room is short, untranslated
## because a file's name is not a message, its tooltip the whole name.
func _name_word(parent: Node, word_name: String) -> Label:
    var word := SaMake.label(parent, word_name)
    word.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    word.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    word.mouse_filter = Control.MOUSE_FILTER_PASS
    return word


## Writes *text* on *word* and its tooltip, and hides the word with its
## separator, the one after it, while there is nothing to say.
func _show_name(word: Label, text: String) -> void:
    word.text = text
    word.tooltip_text = text
    word.visible = not text.is_empty()
    var after := _words.get_child(word.get_index() + 1) as Control
    after.visible = word.visible


## The width *text*, or the word's own text, takes in the word's font.
func _text_width(word: Label, text: String = "") -> float:
    var shown := text if not text.is_empty() else word.text
    if shown.is_empty() or not word.visible:
        return 0.0
    var font := word.get_theme_font("font")
    return font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, word.get_theme_font_size("font_size")).x


## Connects the star and the name of *document*, the one in front, and lets go
## of the one before it.
func _hear_document(document: SaDocument) -> void:
    if document == _heard_document:
        return
    if is_instance_valid(_heard_document):
        if _heard_document.modified_changed.is_connected(_on_document_news):
            _heard_document.modified_changed.disconnect(_on_document_news)
        if _heard_document.path_changed.is_connected(_on_document_news):
            _heard_document.path_changed.disconnect(_on_document_news)
    _heard_document = document
    if _heard_document != null:
        _heard_document.modified_changed.connect(_on_document_news)
        _heard_document.path_changed.connect(_on_document_news)


## Another document in front, whose surface the line asks for itself.
func _on_front_changed(_surface_in_front: SaSurface) -> void:
    follow()


func _on_tool_changed(_tool_name: String) -> void:
    queue_refresh()


func _word(parent: Node, word_name: String, tooltip: String) -> Label:
    var word := SaMake.label(parent, word_name)
    word.tooltip_text = TranslationServer.translate(tooltip)
    # A label ignores the mouse, which would leave its tooltip unreachable.
    word.mouse_filter = Control.MOUSE_FILTER_PASS
    return word


func _on_document_news(_first: Variant = null, _second: Variant = null) -> void:
    queue_refresh()


## Reads again only for the document the line is about, so a document behind
## another tab changing its space leaves the line on the front one's.
func _on_document_space_changed(changed: SaDocument) -> void:
    var surface := _surface()
    if surface == null or changed == surface.get_document():
        queue_refresh()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _height = maxi(HEIGHT, ceili(size.y))
        if _words != null:
            fit_names()


func _on_text_resized(_value: float) -> void:
    SaUI.apply_ui_theme(self)
