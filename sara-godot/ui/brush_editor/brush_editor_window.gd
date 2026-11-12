## The brush editor window: a dashboard, the page list, the open page, the pad
## and one row of buttons.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Built from the active tool's `SaOptionSpec` list and knowing nothing about
## brushes, which is hard rule 6 read from the other side: a third-party tool
## that declares curve options gets an editor without a line being written here.
## The word "brush" is in the file name and in the command's label, and nowhere
## in what the window does.
##
## **What this file is.** The chrome and nothing else: a dashboard, a page
## list, a box for the open page, the pad, and the floor the whole of it needs.
## It holds two objects and asks them, and neither knows it exists.
## `SaBrushEditorPages` owns which pages there are and which one is showing,
## and says when a row wrote. `SaBrushEditorPresetBar` owns the preset: its
## name, Save, Save As, Rename, Reset, the dirty indicator and the session
## behind them, and says when it wrote. The pages are handed what they work on
## rather than calling back into this window, and the floor stays here because
## a class of its own would hold nothing but a reference back.
##
## **The live preview strip is a flat rectangle** of the theme's window colour.
## A stroke is rendered into it. It is here rather than left out because the
## dashboard's arithmetic is laid out around it and a strip added later would
## move everything beside it.
##
## **Not exclusive.** `SaSettingsWindow` had to give that up for the
## reason that applies twice as hard here: an exclusive window blocks the parent
## for as long as it is visible, and an editor whose whole point is watching the
## canvas while a curve moves cannot block the canvas.
@tool
class_name SaBrushEditorWindow
extends SaDialogWindow

## The command F5 runs, whose InputMap action is where a rebind is written.
const EDIT_BRUSH_COMMAND := &"edit_brush"

const PageListScript = preload("res://ui/brush_editor/page_list.gd")
const PreviewStripScript = preload("res://ui/brush_editor/preview/live_preview.gd")
const ScratchpadScript = preload("res://ui/brush_editor/preview/editor_scratchpad.gd")

## Logical units. The minimum is the floor under the measured one, which
## [method fit_to_content] lifts (d34), and the opening size is fitted to the
## host by `fit_opening_size`, so a smaller screen gets what it has room for.
##
## 1100 by 700, because at 900 by 560 the Brush Tip page's falloff curve is
## cut off at the bottom of the page scroll and a painter meets the curve by
## scrolling for it.
const DEFAULT_LOGICAL_SIZE := Vector2i(1100, 700)
const MIN_LOGICAL_SIZE := Vector2i(640, 420)
const DASHBOARD_HEIGHT: int = 84
const PAGE_LIST_WIDTH: int = 200
const THUMBNAIL_SIZE: int = 56
const PREVIEW_SIZE := Vector2i(320, 60)
const PAGE_MARGIN: int = 10

## How far the row of buttons is held off the window's rim, in logical units:
## eight from the sides and the bottom, the page's own inset, and half that from
## the page above it, so the inset reads as a border round the window rather
## than as a gap in the middle of it.
const BUTTONS_INSET: int = 8
const BUTTONS_INSET_TOP: int = 4

## A preset was written from this window's preset bar, so whoever else lists
## presets can follow. The tool options bar's dropdown is the one that has to: the editor
## writes straight to the store and the bar would otherwise still be showing its
## old name, and a reopened editor would come back on no preset at all.
##
## A signal rather than a call, because this window must not know the bar exists.
signal preset_written(stored_name: String)

## What [member canvas_min] holds when nobody said, which is the same number the
## bar and the Tool Options docker fall back to when there is no document behind
## them. A test binding a bare tool gets a plausible page rather than one
## reading zero pixels everywhere.
const NO_DOCUMENT: float = 1000.0

## A cell in the Brush Presets fold was clicked. Announced for the same reason
## and to the same listener: applying a preset means writing the settings
## resource the whole application is holding, and only the bar knows how, so the
## door connects this to `ToolOptionsBar.load_preset` beside the signal above.
signal preset_chosen(stored_name: String)

var page_list: SaBrushEditorPageList
var page_scroll: ScrollContainer
var page_box: VBoxContainer
var thumbnail: Panel
var thumbnail_image: TextureRect
var preview: Panel
var preview_image: SaBrushPreviewStrip

## The pad on the right, its own document and its own instance of the tool being
## edited. Built here and asked, the way the pages are.
var scratchpad: SaEditorScratchpad = null

## The chooser inside the page list's Brush Presets fold. The same control the
## Brush Presets docker hosts, pointed at the store this window was bound with,
## so a preset picked here and a preset picked there are one path.
var presets_chooser: SaBrushPresetsChooser = null

## The width the chooser's grid was last counted for, and whether the presets
## grabber is in hand, so a drag recounts once when it ends.
var _presets_width_seen: int = -1
var _presets_dragging: bool = false

## The document's smaller dimension, for the rows that draw a canvas fraction as
## pixels. Handed over by `bind_tool` like everything else here, because this
## window has no document and reaches for nothing.
##
## Taken once, at the bind. A painter who resizes the canvas with the editor
## open sees the old pixels until the next bind, which is what a tool change or
## a reopen does. The bar's own rows are resynced by the resize and this one is
## not, and that is the price of the window not knowing what a document is.
var canvas_min: float = SaBrushEditorWindow.NO_DOCUMENT

## What the window is editing. Handed over by `open`, never reached for.
var tool_state: ToolState = null

var settings: Resource = null

## Which pages this tool declares and which one is on the right. Built here and
## asked, never written into from outside.
var pages: SaBrushEditorPages = null

## The preset, the writes over it and the dirty indicator. Built here and asked.
var preset_bar: SaBrushEditorPresetBar = null

## The column holding the dashboard, the three columns and the row of buttons,
## whose minimum is most of the window's floor (d34).
var _column: Control = null

## The split holding the presets, the page list, the page and the pad, the one
## child of the column that takes the height left over. The page column's height
## is the window's less everything else in the column, which is what the pad's
## width follows.
var _body: Control = null

## What the strip was last drawn from, so the ticker asks for a render when a
## setting moved and not once a quarter second for ever.
var _preview_seen: String = ""


func _init() -> void:
    _init_dialog("SaBrushEditorWindow", tr("Brush Editor"), DEFAULT_LOGICAL_SIZE, MIN_LOGICAL_SIZE)
    maximise_button.visible = true
    # Same reason `SaSettingsWindow` does it: a Window is visible the moment it
    # joins the tree, and this one is built on the first request.
    visible = false
    exclusive = false
    preset_bar = SaBrushEditorPresetBar.new()
    preset_bar.preset_written.connect(_on_preset_written)
    preset_bar.settings_reset.connect(_on_settings_reset)
    preset_bar.ticked.connect(_on_ticked)
    add_child(preset_bar)

    var column := SaMake.column(content, "Column", 0)
    column.set_anchors_preset(Control.PRESET_FULL_RECT)

    column.add_child(_build_dashboard())

    # The presets column against everything else, so the editor's left edge is a
    # grabber the way its right edge is. The list builds the column and owns its
    # snap, and the window only puts it first.
    var presets_split := HSplitContainer.new()
    presets_split.name = "PresetsSplit"
    presets_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    presets_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(presets_split)

    page_list = PageListScript.new(presets_split)
    page_list.page_selected.connect(show_page)
    page_list.presets_folded.connect(_on_presets_folded)
    presets_split.add_child(page_list.presets_column)
    # The grid counts its columns against the width it has, and the column has
    # none until the split has sorted it, so the first open drew one column of
    # four. Recounted when the box settles at a width and once per drag rather
    # than per motion, because a refresh rebuilds every cell.
    page_list.presets_box.resized.connect(_refresh_presets_for_width)
    presets_split.drag_started.connect(func() -> void: _presets_dragging = true)
    presets_split.drag_ended.connect(
        func() -> void:
            _presets_dragging = false
            _refresh_presets_for_width()
    )

    var split := HSplitContainer.new()
    split.name = "Split"
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    presets_split.add_child(split)

    var left := PanelContainer.new()
    left.name = "PageListPanel"
    var left_style := StyleBoxFlat.new()
    SaTheme.bind(left_style, {"bg_color": "bg_sidebar"})
    for side: String in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
        left_style.set(side, float(SaUI.px(8)))
    left.add_theme_stylebox_override("panel", left_style)
    left.custom_minimum_size = Vector2(float(SaUI.px(PAGE_LIST_WIDTH)), 0.0)
    split.add_child(left)
    left.add_child(page_list)

    # The chooser goes in the fold the list built, rather than the list building
    # one: what a cell means is the host's business, which is the whole reason
    # `SaBrushPresetsChooser` is a control with two hosts and now three.
    presets_chooser = SaBrushPresetsChooser.new()
    presets_chooser.name = "EditorPresetsChooser"
    presets_chooser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Shrunk to what it needs rather than stretched, because the box is a scroll
    # of a fixed height: a library of three sits at the top of it and a library
    # of three hundred scrolls, and neither moves the page rows under it.
    presets_chooser.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    presets_chooser.preset_chosen.connect(preset_chosen.emit)
    presets_chooser.preset_chosen.connect(func(_stored: String) -> void: SaUsageTally.preset_picked(SaUsageTally.BRUSH_EDITOR))
    page_list.presets_box.add_child(presets_chooser)

    # The right half of the window is itself split, the open page against the
    # scratchpad, rather than a third child of the split above: an
    # `HSplitContainer` divides two children and lays a third out with no grabber
    # of its own, so the pad would be a column the painter could not resize.
    var pad_split := HSplitContainer.new()
    pad_split.name = "PadSplit"
    pad_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pad_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.add_child(pad_split)

    page_scroll = SaMake.scroll(pad_split, "PageScroll")
    page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var margin := SaMake.margin(page_scroll, "PageMargin", PAGE_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page_box = SaMake.column(margin, "Page", 6)
    page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pages = SaBrushEditorPages.new(page_box)
    pages.option_written.connect(_on_option_written)
    pages.curve_toggled.connect(_on_curve_toggled)

    pad_split.add_child(_build_scratchpad(pad_split))

    _build_buttons(column)
    _column = column
    _body = presets_split
    _column.minimum_size_changed.connect(_fit_later)
    # Opening the fold moves no minimum, for the reason `floor_minimum` gives,
    # so it is listened to on its own.
    page_list.presets_folded.connect(_fit_later.unbind(1))


## The strip across the top: what the preset is, what it looks like, and the two
## ways of writing it back.
func _build_dashboard() -> Control:
    var bar := SaMake.row(null, "Dashboard", SaTheme.GAP)
    bar.custom_minimum_size = Vector2(0.0, float(SaUI.px(DASHBOARD_HEIGHT)))

    thumbnail = _flat_panel("Thumbnail", Vector2i(THUMBNAIL_SIZE, THUMBNAIL_SIZE))
    thumbnail_image = TextureRect.new()
    thumbnail_image.name = "ThumbnailImage"
    thumbnail_image.set_anchors_preset(Control.PRESET_FULL_RECT)
    thumbnail_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    thumbnail_image.stretch_mode = TextureRect.STRETCH_SCALE
    thumbnail.add_child(thumbnail_image)
    bar.add_child(thumbnail)

    preview = _flat_panel("LivePreview", PREVIEW_SIZE)
    # A stroke is rendered into this, over the flat rectangle, so the panel's
    # border still frames it while nothing has been drawn yet.
    preview_image = PreviewStripScript.new()
    preview.add_child(preview_image)
    bar.add_child(preview)

    preset_bar.build_name_controls(bar)
    number_field_answers = false
    return bar


## The row of buttons at the foot of the window, which every dialog builds with
## `pinned_buttons`, filled by the preset bar.
##
## **Inside a margin, which is the whole of an earlier note**. "These buttons
## (Reset, Close) are covering the rim of the dialog window": the row is the last
## child of a column anchored to the window's full rect, so it would be drawn
## hard against the frame and over its rounded corner. Every other dialog insets
## its whole column, and this one insets the row alone, because the page list's
## sidebar is meant to run to the window's left edge. The row is pinned by the
## split above it, the one child of the column that expands.
func _build_buttons(column: VBoxContainer) -> void:
    var margin := MarginContainer.new()
    margin.name = "ButtonsMargin"
    for side: String in ["margin_left", "margin_right", "margin_bottom"]:
        margin.add_theme_constant_override(side, SaUI.px(BUTTONS_INSET))
    margin.add_theme_constant_override("margin_top", SaUI.px(BUTTONS_INSET_TOP))
    column.add_child(margin)
    var foot := SaMake.column(margin, "ButtonsColumn", 0)
    preset_bar.build_buttons(pinned_buttons(foot), hide)
    default_button = preset_bar.save_button


## The pad on the right, carrying the same eight-unit inset the page uses, so
## the two columns of the split line up. The pad is given the split it sits in,
## because its grabber is what the pad's width and snap answer.
func _build_scratchpad(pad_split: HSplitContainer) -> Control:
    scratchpad = ScratchpadScript.new(pad_split)
    scratchpad.size_to_editor(DEFAULT_LOGICAL_SIZE.x)
    return scratchpad


## How tall the page column is in a window *height* logical units tall: the
## window less its title strip and everything in the column but the split the
## page sits in. Measured off the minimums rather than off a laid-out size,
## because the window asks on `size_changed`, before the column has been laid out
## at the new size.
func page_height(height: int) -> int:
    if _column == null or _body == null:
        return 0
    var chrome := _column.get_combined_minimum_size().y - _body.get_combined_minimum_size().y
    return maxi(0, int(round(float(height) - title_strip_height() - chrome)))


## A rectangle of the theme's window colour at a fixed logical size.
func _flat_panel(panel_name: String, logical: Vector2i) -> Panel:
    var panel := Panel.new()
    panel.name = panel_name
    panel.custom_minimum_size = Vector2(float(SaUI.px(logical.x)), float(SaUI.px(logical.y)))
    panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": "bg_window", "border_color": "border_primary"})
    style.set_border_width_all(1)
    panel.add_theme_stylebox_override("panel", style)
    return panel


## Shows *state*'s options, from *specs*, with *store* behind Save and Reset.
##
## Everything the window edits arrives here. It reaches for nothing, which is
## what lets a test bind a bare `ToolState` and a scratch store without a canvas
## or a machine anywhere near it.
func bind_tool(
    state: ToolState,
    specs: Array,
    store: SaPresetStore,
    loaded_preset: String = "",
    document_min: float = SaBrushEditorWindow.NO_DOCUMENT
) -> void:
    tool_state = state
    canvas_min = document_min
    settings = state.get("settings") as Resource if state != null else null
    preset_bar.bind(settings, store, loaded_preset)
    page_list.build(pages.bind_specs(specs, state, settings, canvas_min))
    if preview_image != null:
        preview_image.bind_source(state.get_script() as Script if state != null else null, settings)
    refresh_thumbnail()
    request_preview()
    bind_presets()
    # After the pages are built, because the fold is a child of the list and the
    # profile is what says whether it is open and how wide.
    page_list.restore_presets()
    if scratchpad != null:
        scratchpad.bind_tool(state.get_script() as Script if state != null else null, settings)
        scratchpad.size_to_editor(logical_size.x, page_height(logical_size.y))
        scratchpad.restore_width()
    if pages.count() > 0:
        show_page(maxi(0, pages.index_of(SaSettings.brush_editor_page)))


## Points the pages' rows at the blend registry and the document the bar's own
## controls follow, so the editor's blend row lists what the bar's does.
##
## Two halves of one binding: the registry fills the list and the document names
## the colour space in plain Normal's label. Handed by the door, which reads
## both off the bar, because the bar is where this window's tool, specs and
## preset store already come from.
func follow_blend_modes(blend_registry: SaBlendModeRegistry, document: SaDocument = null) -> void:
    pages.follow_blend_modes(blend_registry, document)


## Points the fold's chooser at the store, the tool and the settings this window
## was bound with, and rebuilds its grid.
##
## The settings arrive as a `Callable` rather than as the resource, which is the
## chooser's own contract: it renders a thumbnail from whatever the source
## answers at the moment it draws, so a preset saved a second ago is drawn from
## what is in front of the painter now.
func bind_presets() -> void:
    if presets_chooser == null:
        return
    var painter_script := tool_state.get_script() as Script if tool_state != null else null
    var bar := preset_bar
    presets_chooser.bind_store(
        bar.session.preset_store,
        painter_script,
        func() -> Resource: return settings,
        func() -> String: return bar.session.preset_name
    )


## The fold moved, so the profile follows. Written here rather than in the list,
## because a list of rows has no business knowing what a profile is.
func _on_presets_folded(open: bool) -> void:
    SaSettings.brush_editor_presets_open = open


## Rebuilds the grid for the width the box has now, when that is a width it has
## not been counted for and nobody is dragging.
func _refresh_presets_for_width() -> void:
    if presets_chooser == null or _presets_dragging or not page_list.presets_box.visible:
        return
    var width := int(page_list.presets_box.size.x)
    if width <= 0 or width == _presets_width_seen:
        return
    _presets_width_seen = width
    presets_chooser.refresh.call_deferred()


## A preset was applied, from this window's fold or from anywhere else: the
## session is a comparison against a stored file and the file it compares
## against has just changed, so it is replaced whole, the way [method bind_tool]
## replaces it.
##
## Through `EventBus` rather than as an answer from the door, because the bar,
## the Brush Presets docker and a chord all load presets and the editor has to
## follow every one of them. It is the only signal this window listens to, and
## it listens because being wrong about which preset is loaded misleads the painter.
## A preset was stored by some surface, the top bar's Save As among them, and
## the editor takes its name when what was stored is the brush it is editing.
## The session decides, because it owns the comparison.
func _on_preset_store_changed(stored_name: String, saved: bool) -> void:
    if not saved or settings == null:
        return
    if preset_bar.adopt(settings, stored_name):
        refresh_thumbnail()


func _on_preset_loaded(stored_name: String) -> void:
    if settings == null:
        return
    # A preset of another engine was applied to a tool this window is not bound
    # to, and taking it would mark the noise brush's settings with a stamp
    # preset's name. The door rebinds the window when the bar's tool changes,
    # and this is what keeps a load that beats the rebind from being read as
    # this tool's.
    var store := preset_bar.session.preset_store
    if store != null and not store.refusal(stored_name, settings).is_empty():
        return
    preset_bar.bind(settings, preset_bar.session.preset_store, stored_name)
    refresh_thumbnail()
    request_preview()
    if presets_chooser != null:
        presets_chooser.refresh()
    # The rows on the open page are built from the settings, and every one of
    # them is now showing the value the preset replaced.
    if page_list.selected >= 0:
        show_page(page_list.selected)
    sync_ticks()


## Builds the page at *index* on the right and marks its row in the list. The
## page list's signal, the capture step and a scenario all reach it here.
func show_page(index: int) -> void:
    if index < 0 or index >= pages.count():
        return
    page_list.select(index)
    pages.show_page(index)


## Writes *on* onto what the page at *index* switches, the way its switch does.
func set_page_enabled(index: int, on: bool) -> void:
    pages.set_page_enabled(index, on)


## A row on the open page was written: redraw what the setting moved and ask the
## page again, because a written row can be the one another row's condition
## reads, the way a tip generator row chooses which of its page's sections show.
##
## A module's widget writing is the page's own business first: the pages answer
## whether it changed a list the page offers, and the page is built again when
## it did.
func _on_option_written(key: StringName, _value: Variant) -> void:
    if pages.widget_wrote(key):
        show_page(page_list.selected)
    preset_bar.sync_dirty()
    request_preview()
    pages.apply_conditions()


## A page's switch, at the top of the page or above one graph of several,
## switched what it switches, so the indicator, the strip, the dot in the list
## and the switch itself follow. The switch follows because a write through
## [method set_page_enabled] from the capture step moves no switch on its own.
## The tool's options moved too, and a bar row can come and go by a switch, as
## Paint and Smudge does by Smudge Pickup's, so the bar and the docker are told.
func _on_curve_toggled(_key: StringName, _on: bool) -> void:
    preset_bar.sync_dirty()
    request_preview()
    sync_ticks()
    EventBus.tool_options_moved.emit()


## The bar wrote a preset, so the thumbnail is the new file's and whoever else
## lists presets is told.
func _on_preset_written(stored: String) -> void:
    refresh_thumbnail()
    preset_written.emit(stored)


## Reset put the settings back, so the strip and the open page show them.
func _on_settings_reset() -> void:
    request_preview()
    if page_list.selected >= 0:
        show_page(page_list.selected)


## Puts every page's switch onto its dot in the list, and the open page's onto
## the switch at its top, for a page whose switch is a row as well as for one
## whose switch is a curve option.
##
## The ticks were read once, in [method bind_tool], and a preset loaded while
## the editor was open left every one of them where it was: the Texture page
## said off while the strip drew the grain. Called from the preset signal and
## from the ticker, because a `brush` step and a `CURVE_OPTION` row on the bar
## write `enabled` with no signal at all, and a dozen reads four times a second
## is what the dirty label already costs.
func sync_ticks() -> void:
    for i in pages.count():
        var on: Variant = pages.tick_at(i)
        if on != null:
            page_list.show_on(i, bool(on))
    pages.sync_switch()


## The two signals the window listens to from outside, and the resize.
func _ready() -> void:
    super()
    # The pad is sized by the editor's width and this window is resizable, so
    # the share is taken again every time the window's own size changes.
    size_changed.connect(_on_window_size_changed)
    window_input.connect(close_on_its_chord)
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    if not EventBus.preset_store_changed.is_connected(_on_preset_store_changed):
        EventBus.preset_store_changed.connect(_on_preset_store_changed)


## Hides the editor on a fresh press of Edit Brush's chord and says whether it
## did, so F5 is a toggle with the editor focused as well.
## The router declines the chord in a dialog, since it is no window chord, and
## `window_input` runs before the window's tree, so a focused text field never
## holds it. A `hide`, as Close is, so the window keeps what it holds.
func close_on_its_chord(event: InputEvent) -> bool:
    if not visible or not SaShortcutKeys.pressed(event, [String(EDIT_BRUSH_COMMAND)], false, true):
        return false
    hide()
    set_input_as_handled()
    return true


## The window was resized, by a hand on its corner or by a scenario, so the pad
## takes its share of the new size.
##
## The width is measured off `size` rather than read off `logical_size`, because
## a dialog's logical size is what its constructor passed and does not follow a
## resize: `sa_dialog_window.gd` says so where it refuses to re-derive geometry
## on a font change. `SaUI.window_scale` is the same divisor the toolbox docker
## reports its own logical size through, and it is 1 for an embedded subwindow,
## whose `size` is logical already.
##
## The share only reaches the column when the profile has no width of its own,
## which is `size_to_editor`'s own rule: a painter who dragged the grabber keeps
## what they dragged however the window moves.
func _on_window_size_changed() -> void:
    if scratchpad == null:
        return
    var factor := SaUI.window_scale(self)
    var height := int(round(float(size.y) / factor))
    scratchpad.size_to_editor(int(round(float(size.x) / factor)), page_height(height))


# --- The floor ----------------------------------------------------------------


## Lifts the window's floor to what its content measures, and the window with
## it (d34).
##
## The claim was a shot of the editor at 660 by 460, above the 640 its
## constructor named as a floor, reading "Unsaved brush", "Rename" and two
## letters of "Save", about 45 pixels of the pad and a lone "R" of the footer.
## The column is anchored to the window's full rectangle and a container never
## shrinks under its children's minimum, so a column that needed more than the
## window offered ran past the right edge and took everything laid out last with
## it. Measured rather than guessed, as the Colour Space dialog is: a font, a
## translation, a long preset name and the presets fold opening all move the
## minimum, and all of them reach `minimum_size_changed`. It was `SaEditorFloor`
## beside this, a class whose only state was this window and its column, until
## the window took it back.
func fit_to_content() -> void:
    var wanted := floor_minimum()
    if wanted == logical_min_size:
        return
    logical_min_size = wanted
    min_size = SaUI.window_size_for(self, logical_min_size)
    size = Vector2i(maxi(size.x, min_size.x), maxi(size.y, min_size.y))


## Deferred because the signal fires mid-layout, and a window resized from
## inside a layout pass is a warning.
func _fit_later() -> void:
    fit_to_content.call_deferred()


## The editor's floor in logical units, never under the constructor's own.
##
## The column's minimum answers for the dashboard, the page list, the page and
## the row of buttons. It does not answer for the two columns a split sizes, the
## presets fold on the left and the pad on the right: a split keeps a column's
## offset only while the page keeps its minimum, and gives the column what is
## left, which is its own minimum of a margin and nothing. The first after shot
## of the fold opened at 768 was exactly that, a pad crushed to one letter of
## its title.
##
## So each open column goes in on top at a width of its own. The pad's is its
## floor, the width under which a drag shuts it, where its title fits: the
## width it opens at is a share of the window's, and a floor that grew with the
## window would grow the window without end. The fold's is the width it opens
## at, which the painter set and the window does not move. Measured at its
## floor instead, the fold opened at its 300 and took the difference out of
## the pad, which the second after shot showed at 108 with its title cut.
func floor_minimum() -> Vector2i:
    var wanted := content_floor()
    return Vector2i(maxi(wanted.x, MIN_LOGICAL_SIZE.x), maxi(wanted.y, MIN_LOGICAL_SIZE.y))


## What the content alone needs, before the constructor's floor is laid under
## it. With the buttons out of the dashboard it can be the narrower of the two,
## and a column that opens or shuts then moves this and not the window's floor.
func content_floor() -> Vector2i:
    var column_min := _column.get_combined_minimum_size()
    var width := column_min.x
    if page_list.presets_open and page_list.snap != null:
        var snap := page_list.snap
        width += _beyond_own_minimum(page_list.presets_column, snap, maxi(snap.floor_width, snap.open_width))
    if scratchpad != null:
        width += _beyond_own_minimum(scratchpad, scratchpad.snap, scratchpad.snap.floor_width)
    var bar := maxf(drag_handle.size.y, drag_handle.get_combined_minimum_size().y)
    return Vector2i(int(ceil(width)), int(ceil(column_min.y + bar)))


## How much wider than its own minimum a split's column has to be to stand at
## *width*, and nothing for a shut one.
func _beyond_own_minimum(column: Control, snap: SaSplitSnap, width: int) -> float:
    if column == null or snap == null or snap.shut:
        return 0.0
    return maxf(0.0, float(width) - column.get_combined_minimum_size().x)


## What the floor is and what it was measured from, for the dump.
func floor_report() -> Dictionary:
    var column_min := _column.get_combined_minimum_size()
    var wanted := floor_minimum()
    return {
        "minimum": {"x": wanted.x, "y": wanted.y},
        "logical_min_size": {"x": logical_min_size.x, "y": logical_min_size.y},
        "min_size": {"x": min_size.x, "y": min_size.y},
        "column_min": {"x": int(ceil(column_min.x)), "y": int(ceil(column_min.y))},
        "fits": size.x >= wanted.x and size.y >= wanted.y,
    }


# --- The ticker ---------------------------------------------------------------


## The preset bar's ticker read the settings again. The ticks and the strip
## follow a setting moved on the bar for the same reason the label does, and
## through the same reading: there is no signal that says an option changed, so
## a comparison four times a second is what any of them can have. The strip's
## own compressor decides whether that costs a render.
func _on_ticked(moved: bool) -> void:
    sync_ticks()
    if moved or _preview_seen != _settings_fingerprint():
        _preview_seen = _settings_fingerprint()
        request_preview()


## A cheap stand-in for "the settings as they are now", so the ticker can tell a
## change from a quiet second without walking every property. The four numbers a
## thumbnail's shape depends on most, and a change nothing here names simply
## waits for whichever control moved it to ask.
func _settings_fingerprint() -> String:
    if settings == null:
        return ""
    var parts := PackedStringArray()
    for key: String in ["radius", "opacity", "spacing", "exposure"]:
        if key in settings:
            parts.append("%.6f" % float(settings.get(key)))
    return ",".join(parts)


## Opens the editor on the page holding *option*, which is what a `CURVE_OPTION`
## row's button asks for.
##
## The page is found by the resource rather than by the title, because two pages
## can be given one title by a careless tool and only one of them holds this
## object.
func show_curve_option(option: Resource, page_title: String) -> void:
    popup_centered()
    for i in pages.count():
        if pages.curve_option_at(i) == option or pages.title_at(i) == page_title:
            show_page(i)
            return


## Draws the preset's own thumbnail beside the strip, off the cache when the
## `.tres` has not moved since the PNG was written.
func refresh_thumbnail() -> void:
    var session := preset_bar.session
    if thumbnail_image == null or session.preset_store == null or settings == null or tool_state == null:
        return
    if not session.has_preset():
        thumbnail_image.texture = null
        return
    var path := SaPresetThumbs.ensure(session.preset_store.dir, session.preset_name, tool_state.get_script() as Script, settings)
    if path.is_empty():
        return
    var image := Image.load_from_file(path)
    if image != null:
        thumbnail_image.texture = ImageTexture.create_from_image(image)


## Asks the strip and every module widget on the open page to draw again. The
## window's whole share of the rule, which lives on `SaPreviewCompressor`: the
## stamp brush's tip preview asks it too, because a dab drawn per tick of the
## Hardness slider lags behind the hand.
func request_preview() -> void:
    if preview_image != null:
        preview_image.request()
    pages.settings_moved()


## Drives the pad: `{"paint": {...}}` and `{"clear": true}`.
##
## The window's public door rather than a getter, for the reason the header
## gives about `show_page` and `save`: a capture step reaches it by name, and a
## door that moved is a door the step has to be taught about.
func scratch(spec: Dictionary) -> void:
    if scratchpad != null:
        scratchpad.scratch_step(spec)


# --- What a dump reads --------------------------------------------------------


## Where each graph on the open page ends against what the page scroll shows, in
## the window's own units, from the scroll's top: the falloff curve on the Brush
## Tip page, a curve option's graph on its own. `inside` says whether the page
## opened with the graph in sight, which a window too short for its page gets
## wrong and a shot of a cut-off curve shows only to a careful reader.
func graphs_in_sight() -> Array:
    var out: Array = []
    if page_scroll == null:
        return out
    var view := page_scroll.get_global_rect()
    for graph: Control in pages.graphs():
        var rect := graph.get_global_rect()
        (
            out
            . append(
                {
                    "name": String(graph.name),
                    "top": int(round(rect.position.y - view.position.y)),
                    "bottom": int(round(rect.end.y - view.position.y)),
                    "shown": int(round(view.size.y)),
                    "inside": rect.size.y > 0.0 and view.encloses(rect),
                }
            )
        )
    return out


## The words of the row of buttons, left to right: the way out first and the
## default last, the order every dialog's row keeps.
func button_row() -> PackedStringArray:
    var words := PackedStringArray()
    var row := preset_bar.save_button.get_parent() if preset_bar.save_button != null else null
    if row == null:
        return words
    for child: Node in row.get_children():
        var button := child as Button
        if button != null and button.visible:
            words.append(button.text)
    return words


## What the window is showing, for a state dump: the geometry the spec names, the
## preset, the dirty state and every row of the list.
func editor_report() -> Dictionary:
    # Synced first, so the dump and the label can never disagree. The first run of
    # this scenario caught them doing exactly that: `dirty` true beside
    # `dirty_text` "Saved", after a slider moved on the bar and nothing told the
    # window.
    preset_bar.sync_dirty()
    sync_ticks()
    # The open page's switch at its top, or null for a page with none.
    var switch_on: Variant = null
    if pages.page_switch != null:
        switch_on = pages.page_switch.button_pressed
    return {
        "open": visible,
        "logical_size": {"x": logical_size.x, "y": logical_size.y},
        # `size` is logical for an embedded subwindow and physical for a real OS
        # one, which is why the scale is beside it: at 1.5 the window still reads
        # 900 by 560 embedded, and only `content_scale` says the pass ran.
        "size": {"x": size.x, "y": size.y},
        "floor": floor_report(),
        "content_scale": content_scale_factor,
        "embedded": is_embedded(),
        "preset": preset_bar.session.preset_name,
        "engine": preset_bar.engine_label.text if preset_bar.engine_label != null else "",
        "dirty": preset_bar.is_dirty(),
        "dirty_text": preset_bar.dirty_label.text if preset_bar.dirty_label != null else "",
        "description": preset_bar.description_edit.text if preset_bar.description_edit != null else "",
        "page": page_list.title_at(page_list.selected),
        "pages": page_list.row_report(),
        "page_switch": switch_on,
        "graphs": graphs_in_sight(),
        "buttons": button_row(),
        "rows": pages.row_report(),
        # What the module widgets on the open page say about themselves, the
        # stamp brush's tip preview among them, keyed by option. Empty for a
        # page carrying none, which is what says a widget is its page's and not
        # the window's.
        "widgets": pages.widget_report(),
        "curve_page": pages.curve_control != null,
        # The document the size rows were drawn against, because "Size: 5 px" and
        # "Size: 0 px" are the same shape in a screenshot and a scenario has to
        # be able to say which one it got.
        "canvas_min": canvas_min,
        # Whether the fold is open, whether the chooser is in it and what it is
        # showing, because a shut fold is a picture of nothing and the claim is
        # about what a painter finds when they open it.
        "presets": page_list.presets_report(),
        "presets_chooser": presets_chooser.chooser_report() if presets_chooser != null else {},
        # The pad is its own document, so what it holds is a claim about a
        # surface that is not the painting: `strokes` going up beside a History
        # count that does not is the whole of what the pad claims.
        "scratch": scratchpad.pad_report() if scratchpad != null else {},
        # The preview's four numbers, and what each counts, because two of them
        # are easy to read as the same thing. `preview_renders` and
        # `preview_coalesced` are this strip's: the compressor's claim is that a
        # drag costs one render rather than one per event, and a picture of a
        # stroke cannot say how many times it was drawn. `strokes_rendered` is
        # the run's total through `SaPresetThumbs`, the strip's renders
        # included, and `thumb_cache_hits` counts the asks that read a PNG
        # instead. A second open reading the cache is a claim about the store
        # rather than about the strip, which is why those two are static and
        # these two are not.
        "preview_renders": preview_image.renders if preview_image != null else 0,
        "preview_coalesced": preview_image.compressor.coalesced if preview_image != null else 0,
        "strokes_rendered": SaPresetThumbs.renders,
        "thumb_cache_hits": SaPresetThumbs.cache_hits,
        "thumbnail": thumbnail_image != null and thumbnail_image.texture != null,
        "preview": preview_image != null and preview_image.texture != null,
    }
