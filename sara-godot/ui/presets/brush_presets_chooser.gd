## The preset chooser: a grid of rendered strokes with a name under each, used by
## the Brush Presets docker and by the brush editor's presets fold.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One control and two hosts, which is the whole reason it is a file of its own
## rather than more lines in `ui/presets/tool_options_presets.gd`. It knows about a
## `SaPresetStore` and about `SaPresetThumbs`, and about nothing else: the tool
## whose script draws the thumbnails is handed over, the settings resource a
## preset is applied to comes through a `Callable`, and the host decides what a
## click means by connecting `preset_chosen`.
##
## **The loaded preset's cell is drawn marked**. Which preset the brush is on is the one
## thing a grid of pictures has to say and this one said nothing, so the name lived only
## in the bar's dropdown and the editor's dashboard, both of them somewhere else on the
## screen from the cells being picked in. The name is handed over like everything else
## here, as `loaded_source`, and both hosts already rebuild the grid on
## `EventBus.preset_loaded`, so the mark follows a load from the bar, a chord or the other
## host without a signal of its own.
##
## **The cell shows a stroke or a tip, and the painter chooses which**. The S
## says what the brush does along a stroke, which is what a preset is for, and
## the dab says what its tip looks like, which is what the painter is picking
## between when six presets differ only in their mask. Both are cached, under two
## names, so flipping the choice is two file reads rather than two renders.
##
## **A thumbnail is never rendered while the grid is being built.** A cell whose
## PNG is on disk takes it at once, which is a file read. A cell whose PNG is
## stale gets a placeholder and joins a queue, and `_process` renders a share of
## one a frame, so a library of two hundred presets opens in a frame and fills
## in over the next ones rather than stalling the popup that opened it. The cell
## takes its picture without the chooser being reopened, which is the clause this
## is graded on. The cells and their pictures are `SaBrushPresetCells`'.
class_name SaBrushPresetsChooser
extends VBoxContainer

## A cell was clicked. The host applies it, because what applying means is the
## host's business: the bar loads onto the tool it is showing.
signal preset_chosen(preset_name: String)

## The icon size slider's ends, in logical pixels. The ceiling is the width
## `SaPresetThumbs` renders a stroke at, 128, so the largest cell shows the
## picture at its own size and no larger: at the old 80 a stroke was always drawn
## at about half of what was rendered, and three sweeps read the strokes as too
## small to tell apart.
const MIN_ICON: int = 30
const MAX_ICON: int = 128

## The widest a cell's name column grows to fit one word, as a multiple of the
## largest icon. Past it a painter's own word of forty letters would set every
## column in the grid, so a word that long runs past its cell instead.
const NAME_WORD_CAP: float = 2.0

## The room either side of the widest word, in logical pixels, so two neighbours'
## names never touch across the grid's separation.
const NAME_PAD: int = 4

## How many lines of the name a cell shows before the rest is an ellipsis. Two,
## because every shipped name is one or two words and the column is as wide as
## the widest of them.
const NAME_LINES: int = 2

## The meta a cell carries its preset's stored name under, which Map to MIDI
## reads off the cell a click lands in.
const PRESET_META := &"sa_preset_name"

## What the Strokes and Tip choice writes for each row. The row's own word
## rather than its place in the list, so nothing here counts positions, and the
## two are exactly the words a scenario's `thumb` names.
const THUMB_STROKES: String = "strokes"
const THUMB_TIP: String = "tip"

## How thick the marked cell's rim is drawn, in logical pixels. Two rather than
## one because one is the rim a hovered button already draws, and a mark that
## can be mistaken for a hover marks nothing.
const MARK_BORDER: int = 2

## The Button states the mark is drawn in. All five, because a mark that a hover
## or a press paints over is gone exactly while the painter is looking at it.
const MARK_STATES: Array[String] = ["normal", "hover", "pressed", "focus", "disabled"]

## The colours a marked button's own words take in the accent, for a picker whose
## name is the button's text rather than a label under it: a Recent Presets row
## and a cell of the Pop-up Palette's ring. Every state but disabled, because a
## marked preset is the loaded one and a disabled cell holds none.
const MARK_FONT_COLORS: Array[String] = [
    "font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"
]

## The two acts the tag dropdown carries below its tags, as ids no tag can be.
## They are offered only while a tag is on, because renaming All is not a
## thing and `SaChoiceButton` has no disabled row to offer instead.
const TAG_RENAME_ID: String = "__sa_rename_tag"
const TAG_DELETE_ID: String = "__sa_delete_tag"

## The All row's id. Not the empty string, because an empty id is the list's own
## word for no row chosen, and while a tag is on no row is.
const TAG_ALL_ID: String = "__sa_all_tags"

var store: SaPresetStore = null

## The tool whose script draws a thumbnail, and where the settings to draw it
## from come from. Both handed over: this file has no registry and no tool.
var tool_script: Script = null
var settings_source: Callable = Callable()

## The script that draws a preset of each engine, by the engine's id, for a
## shelf that holds more than one: the Brush's holds the stamp's and the noise
## engine's. A preset of an engine not here is drawn by
## [member tool_script]. Handed over with it.
var engine_scripts: Dictionary = {}

## What the host says the brush's preset currently is, answering a name or the
## empty string. A `Callable` and not a member the host writes, for the reason
## `settings_source` is one: the chooser asks at the moment it draws, so a host
## that has just replaced its session is never a frame behind its own grid.
var loaded_source: Callable = Callable()

var search_field: LineEdit
var tag_option: SaChoiceButton

## Making and unmaking tags, built when the store arrives because it writes
## through one. Public because a test drives the gesture and a capture reads it.
var tags: SaBrushPresetTags = null

## The star on every cell and the Starred filter. Public for the
## reason `tags` is.
var stars: SaBrushPresetStars = null

## Which tags are shown only and which hidden, and the line the grid shows when
## they leave nothing. Public for the reason `tags` is.
var tag_filter: SaBrushPresetTagFilter = null
## The bundle menu on the top row, which loads and unloads a bundle.
var bundle_menu: SaBrushPresetBundles = null
var thumb_option: SaChoiceButton
var size_slider: FactorSlider
var grid: GridContainer

## The line where the cells would be while the store holds no preset at all, so
## a painter who deleted every one is told the door that is left. It hands
## a press on to this control, so a right-click on it opens the menu.
var empty_line: Label

## The grid's cells, built and waiting, and their pictures. Public because a
## test drives the tile's hover and reads it.
var cells: SaBrushPresetCells = null

## Whether the grid builds its cells a share a frame rather than all in the
## call that lays it out. Set by the boot's presets scan on the Brush Presets
## docker's chooser, the one with frames to share them over, so a suite's
## chooser and the brush editor's build at once.
var in_shares: bool = false

## Whether the preset in hand keeps a cell in the grid when the search, a tag
## or the Starred filter hides it, the Brush Presets panel's rule, because the
## painter chose it and a filter should not take it out of their hand. A
## constructor argument, true for the panel alone, so the brush editor's fold
## and a suite's chooser filter strictly.
var keeps_loaded: bool = false

## The names the grid lists, in its order.
var _names: Array[String] = []

## The name of the cell the grid holds only because it is the preset in hand,
## the filters hiding it, empty when there is none. Written by `refresh` alone.
var _added: String = ""

## The name the grid is marking, empty when the brush is on no preset or when
## the filters have hidden the one it is on and the grid does not keep it. Written by `refresh` alone, and a
## cell is built marked rather than marked afterwards, because every path that
## changes it rebuilds the grid anyway.
var _marked: String = ""

## How wide every cell's name is declared, `name_width` taken once per build
## rather than once per cell, since it reads every name. Written by `refresh` and
## by the theme pass that changes the font.
var _name_column: float = 0.0

## The row the search field and the two dropdowns sit on, held because the tag
## name field joins it when the store arrives.
var _top: HBoxContainer = null

## The tags the row is offering, in the order it offers them, and the one the
## Rename and Delete acts are on: the tag last pressed while it is still on. Which
## tags filter is the profile's, `SaBrushPresetTagFilter`, and empty means none.
var _tag_rows: Array[String] = []
var _selected_tag: String = ""

## The tag the bar last handed `follow_tag`, kept so a hand-over of the same one
## is told apart from a move. The bar hands its own tag over on every refresh,
## which a switch of tool is, and its tag is none unless a scenario set one, so
## taking it every time put the painter's own choice back on All.
var _followed_tag: String = ""

## What the cells in the grid were built from: the store, the names in their
## order, the marked one, the tip choice and the icon size. Written by `refresh`
## alone, and read by `refresh_if_changed`, which rebuilds only when the grid
## would come out different.
var _built_from: Array = []


## *keep_loaded* is [member keeps_loaded]. A host that scrolls the chooser hands
## its column as *pinned_in*, and the rows above the grid stand there, above the
## scroll, in a `SaBrushPresetPinnedHeader`.
func _init(keep_loaded: bool = false, pinned_in: Container = null) -> void:
    keeps_loaded = keep_loaded
    name = "BrushPresetsChooser"
    add_theme_constant_override("separation", SaUI.px(6))

    # Two rows: at 280 units one row drew both dropdowns as bare arrows.
    var holder: Control = self
    if pinned_in != null:
        holder = SaBrushPresetPinnedHeader.new(pinned_in, 6)
    var header := SaMake.column(holder, "ChooserHeaderRows", 6)
    var search_row := SaMake.row(header, "ChooserSearchRow", 6)
    search_field = SaMake.line_edit(search_row, "ChooserSearch", "", tr("Search presets"))
    search_field.clear_button_enabled = true
    SaSearchField.mark(search_field)
    search_field.tooltip_text = tr("Filter presets by name.")
    search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    search_field.text_changed.connect(func(_text: String) -> void: refresh())

    # The kit's slider, so the header's size reads like every other slider in
    # Sara and the harness lists it among the controls it walks.
    size_slider = SaMake.slider(search_row, "ChooserIconSize", MIN_ICON, MAX_ICON, 1.0, float(SaSettings.preset_icon_size))
    # Again at each change of language, since the docker is built before a
    # language module's catalogue arrives.
    SaOnLanguage.watch(size_slider, func() -> void: size_slider.prefix = tr("Size") + ": ")
    size_slider.decimal_places = 0
    size_slider.tooltip_text = tr("How large each preset is drawn.")
    # `preferred_width` too: the slider rewrites its minimum from it at every refit, 170
    # by default, which undid the 90 and left the field 118 wide, "Search pre".
    size_slider.preferred_width = SaUI.px(90)
    size_slider.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    size_slider.value_changed.connect(_on_icon_size_changed)
    _top = SaMake.row(header, "ChooserTop", 6)
    tag_option = SaMake.choice(_top, "ChooserTag")
    tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tag_option.tooltip_text = tr("Click a tag to show only its presets, again to hide them, a third time to let them be.")
    tag_option.choice_picked.connect(_on_tag_selected)

    var thumbs := [{"id": THUMB_STROKES, "label": tr("Strokes")}, {"id": THUMB_TIP, "label": tr("Tip")}]
    thumb_option = SaMake.choice(_top, "ChooserThumb", thumbs)
    thumb_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    thumb_option.tooltip_text = tr("Show each preset as a sample stroke or as its tip.")
    thumb_option.select_value(THUMB_TIP if SaSettings.preset_thumb_tip else THUMB_STROKES)
    thumb_option.choice_picked.connect(_on_thumb_selected)

    # Beside the tag dropdown, since the two filters combine.
    stars = SaBrushPresetStars.new()
    _top.add_child(stars.filter)
    _top.move_child(stars.filter, thumb_option.get_index())
    stars.changed.connect(refresh)

    tag_filter = SaBrushPresetTagFilter.new()
    tag_filter.changed.connect(refresh)
    bundle_menu = SaBrushPresetBundles.new(_top)
    bundle_menu.changed.connect(refresh)

    grid = SaMake.grid(self, "ChooserGrid", 1, 6)
    resized.connect(_recount_columns)
    cells = SaBrushPresetCells.new(grid, stars, preset_chosen.emit, _on_menu_asked)

    var empty_text := tr("No presets. Right-click here and choose New Preset... to start one from an engine's defaults.")
    empty_line = SaMake.label(self, "ChooserEmpty", empty_text)
    empty_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    empty_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    empty_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    empty_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
    empty_line.mouse_filter = Control.MOUSE_FILTER_PASS
    empty_line.visible = false
    SaTheme.bind_font(empty_line, "text_muted")
    add_child(tag_filter.empty_box)


## What the chooser draws from. Every one of the four is handed over rather than
## reached for.
##
## *loaded* is optional so a test that only wants the grid builds a chooser with
## three arguments, and an unbound one marks nothing. So are
## *painters*, [member engine_scripts], which a host of one engine never hands.
func bind_store(
    preset_store: SaPresetStore,
    painter_script: Script,
    source: Callable,
    loaded: Callable = Callable(),
    painters: Dictionary = {}
) -> void:
    store = preset_store
    tool_script = painter_script
    engine_scripts = painters
    settings_source = source
    loaded_source = loaded
    _bind_tags()
    refresh()


## Builds the tag gesture over the store that just arrived, and puts its two
## controls where they belong: the name field on the top row left of the tag
## dropdown, and the cell menu under this control.
##
## Here rather than in `_init` because the gesture writes through a store and a
## store is what `bind_store` brings. A second bind replaces it rather than
## adding a second field, which is what a host that swaps its store would
## otherwise get.
func _bind_tags() -> void:
    if tags != null:
        if tags.field != null:
            # Out of the row before the new field joins it, or the new one meets
            # the old name still taken and the engine gives it `@LineEdit@` and
            # a number, which no walker finds by name.
            if tags.field.get_parent() != null:
                tags.field.get_parent().remove_child(tags.field)
            tags.field.queue_free()
        if tags.menu != null:
            tags.menu.queue_free()
    # Hosted on this control's own owner rather than on a cell, so the delete
    # question outlives the grid rebuild its answer causes.
    tags = SaBrushPresetTags.new(store, self)
    tags.changed.connect(_on_tags_changed)
    _top.add_child(tags.field)
    _top.move_child(tags.field, tag_option.get_index())
    add_child(tags.menu)


## The icon size the grid is drawing at, in logical pixels.
func icon_size() -> int:
    return int(clampf(SaSettings.preset_icon_size, MIN_ICON, MAX_ICON))


## Whether the cells are drawing the tip rather than the stroke. Read off the
## profile at the moment it is asked, the way `icon_size` is, so the two hosts
## never hold two answers.
func showing_tip() -> bool:
    return SaSettings.preset_thumb_tip


## Lays the grid out again from the store, the tag row and the search field. A
## cell still right is kept and every other one is built, at once or
## `in_shares`, as `SaBrushPresetCells.lay_out` says.
func refresh() -> void:
    if store == null:
        return
    _sync_tag_row()
    bundle_menu.rebuild(store)
    stars.begin_build(store)
    tag_filter.begin_build()
    # The row follows the profile rather than the other way round, so the other
    # host's chooser is on the choice this one was left on.
    if thumb_option != null:
        thumb_option.select_value(THUMB_TIP if showing_tip() else THUMB_STROKES)
    _names = _listed_names()
    var loaded := _loaded_name()
    _added = loaded if keeps_loaded and _names.has(loaded) and not _passes(loaded, _wanted_text(), _tags_on()) else ""
    empty_line.visible = store.list_names().is_empty()
    var filtered_none := _names.size() == (0 if _added.is_empty() else 1)
    tag_filter.show_empty(filtered_none and not empty_line.visible, _tags_on())

    _marked = loaded if _names.has(loaded) else ""
    _name_column = name_width()
    var name_floor := Vector2(_name_column, _name_height())
    var tip := showing_tip()
    cells.lay_out(_names, store, tool_script, engine_scripts, icon_size(), tip, _marked, name_floor, not in_shares)
    grid.columns = _columns_that_fit()
    _built_from = _wanted_build(_names.duplicate())


## Rebuilds the grid only when it would come out different from the one it
## holds, and answers whether it did.
##
## A tool switch is the reason. Both hosts hear `tool_changed`, a switch
## changes neither the store, the tag, the search nor the loaded preset, and a
## rebuild of every cell in each host would land in the transform's commit
## frame, which ends in the hand back to the tool before it.
##
## The store's contents are not in the comparison, because a preset saved over
## one of the same name lists the same names with a new picture. A host that
## hears the store change calls `refresh` or `bind_store`, which always rebuild.
func refresh_if_changed() -> bool:
    if store == null:
        return false
    # A tag the acts are on that the library no longer carries is one `refresh`
    # lets go of, so the row the dropdown holds is a row of a tag that is gone.
    var tag_gone := not _selected_tag.is_empty() and not _carries_tag(_selected_tag)
    if not tag_gone and _wanted_build(_listed_names()) == _built_from:
        return false
    refresh()
    return true


## Follows a switch to the tool whose script is *painter_script*, rebuilding
## the grid only if it would come out different. Answers false, and follows
## nothing, when the chooser is bound to a store other than *preset_store* or to
## none, since what binds a store is `bind_store` with the host's sources.
## *painters* are the new tool's [member engine_scripts].
func follow_tool(preset_store: SaPresetStore, painter_script: Script, painters: Dictionary = {}) -> bool:
    if store == null or store != preset_store:
        return false
    tool_script = painter_script
    engine_scripts = painters
    refresh_if_changed()
    return true


## Filters by *tag* the way the bar's own row does, and rebuilds only if that
## changes the grid. The bar's `refresh` calls this on every tool switch.
##
## **Only a tag that moved is taken.** The bar's tag is the one its own list was
## last filtered by, and the painter filters through this row, so the bar's stays
## on none while the painter's moves. A hand-over of the tag the last one handed
## is the bar saying nothing, and taking it would set the painter's tag back to All at
## every switch of tool, among them the one a preset of the other engine makes
## when it is pressed.
##
## Checked against the store rather than against the rows the dropdown was last
## built with, since the bar's tag may be one a save has only just added. A tag
## the store does not carry leaves the filter alone and says nothing, because the
## bar clears its own filter when its tag is gone and a warning is for a scenario
## naming a tag by hand, which is `capture_tag`.
func follow_tag(tag: String) -> bool:
    if store == null:
        return false
    if tag != _followed_tag and (tag.is_empty() or _carries_tag(tag)):
        _selected_tag = tag
        _followed_tag = tag
        tag_filter.only(tag)
    return refresh_if_changed()


## Whether the library carries *tag*, asked before a filter is put on it or kept
## on it.
func _carries_tag(tag: String) -> bool:
    return store.all_tags().has(tag)


## The tags, bundles and engines on that the library carries, word to show or hide.
func _tags_on() -> Dictionary:
    var words := store.all_tags()
    for auto: PackedStringArray in SaBrushPresetTagFilter.auto_words(store):
        words.append_array(auto)
    return SaBrushPresetTagFilter.states(words)


## The names the store, the tag filter, the Starred filter and the search field
## let through, in the order the grid shows them, and the preset in hand in its
## place in that order when [member keeps_loaded] and they hide it.
##
## **In its place rather than first.** A cell put first would jump to the top
## and back as the painter picks, and the grid's order is the store's, so the
## added cell stands where the same preset stands with no filter on.
func _listed_names() -> Array[String]:
    var listed: Array[String] = []
    var wanted := _wanted_text()
    var on := _tags_on()
    var kept := _loaded_name() if keeps_loaded else ""
    for stored_name: String in store.list_names():
        if stored_name == kept or _passes(stored_name, wanted, on):
            listed.append(stored_name)
    return listed


## The search field's text as a name is matched against, empty with no field.
func _wanted_text() -> String:
    return search_field.text.strip_edges().to_lower() if search_field != null else ""


## Whether the tags *on*, the search *wanted* and the Starred filter let
## *stored_name* through.
func _passes(stored_name: String, wanted: String, on: Dictionary) -> bool:
    var title := store.origin_for(stored_name)[0]
    var words := SaBrushPresetTagFilter.words_of(store.tags_for(stored_name), title, store.engine_for(stored_name))
    if not SaBrushPresetTagFilter.passes(on, words):
        return false
    if not wanted.is_empty() and not stored_name.to_lower().contains(wanted):
        return false
    return stars.passes(stored_name) and SaBrushPresetBundles.loaded(store, stored_name)


## A preset loaded anywhere: its cell marked and, where the filters hide it and
## [member keeps_loaded], added, and then scrolled into view once the grid has
## laid the cell out.
##
## **A load that moves only the mark moves only the mark**. The whole
## `refresh` entered every kept cell into the grid again and asked the disk for
## every picture's age, 48 to 53 ms of the frame a preset was picked in, where
## two cells are all a load changes.
func follow_load() -> void:
    if not _move_mark():
        refresh()
    if _marked.is_empty() or not is_inside_tree():
        return
    var wanted := _marked
    await get_tree().process_frame
    if is_inside_tree() and wanted == _marked:
        cells.bring_into_view(wanted)


## Moves the mark to the loaded preset and answers whether that was all the
## grid needed, which it was when the grid built from now differs from the one
## held in the loaded preset alone. Answers false, touching nothing, otherwise.
func _move_mark() -> bool:
    if store == null or _built_from.is_empty():
        return false
    if not _selected_tag.is_empty() and not _carries_tag(_selected_tag):
        return false
    var names := _listed_names()
    var wanted := _wanted_build(names)
    var marked: String = wanted[2]
    wanted[2] = _built_from[2]
    if names != _names or wanted != _built_from:
        return false
    var loaded := _loaded_name()
    _added = loaded if keeps_loaded and _names.has(loaded) and not _passes(loaded, _wanted_text(), _tags_on()) else ""
    _marked = marked
    cells.mark(marked)
    _built_from[2] = marked
    return true


## Everything a grid of *names* would be built from, in the form `_built_from`
## is kept in, so one comparison settles whether the cells are still right.
func _wanted_build(names: Array[String]) -> Array:
    var loaded := _loaded_name()
    return [store, names, loaded if names.has(loaded) else "", showing_tip(), icon_size()]


## The preset the host says the brush is on, empty when it says nothing or when
## there is no host to ask.
func _loaded_name() -> String:
    return str(loaded_source.call()) if loaded_source.is_valid() else ""


## How many cells fit across the width the host gave, from the width a cell
## actually is rather than from a guess at it.
##
## **The count is what keeps the grid from widening its own host**. The grid's
## minimum width is `columns * pitch`, so a count taken from a pitch smaller
## than the real one asks the host for room the count was never made against,
## the host grows, and the next refresh counts again against the width it just
## caused. That is the ratchet: the same icon size counts more columns at each
## refresh, and a drag of the size slider, which sends fifty refreshes, would
## end with the grid as wide as the screen lets it.
##
## So the pitch is measured off the cells, which exist by the time this is
## called, and the width is `get_parent_area_size()`, the room the parent
## container has for this control, rather than `size`, the width this control
## has grown to. With both, `columns * pitch` is never more than the width it
## was counted against and there is nothing to ratchet.
##
## Capped at the number of cells as well, because a grid of six things has no
## use for eleven columns however wide the host is.
func _columns_that_fit() -> int:
    if _names.is_empty():
        return 1
    var separation := float(grid.get_theme_constant("h_separation"))
    var pitch := maxf(float(SaUI.px(icon_size())), cells.widest()) + separation
    var room := _host_width() + separation
    return clampi(int(room / pitch) if pitch > 0.0 else 1, 1, _names.size())


## Counts again when the host's width moves, without rebuilding a cell. The
## count `refresh` took was made against the width the host had then, and a
## docker's first show is the one time that is not the width the painter sees:
## the grid was built at boot inside a hidden window, whose containers sort
## nothing, so the docker opened with two columns spread over room for five and
## its buttons pushed under the scroll, until any action rebuilt the grid. A
## resize by hand is the same question asked later. Guarded, because writing the
## count the grid holds queues a sort for nothing.
func _recount_columns() -> void:
    if store == null or _names.is_empty():
        return
    var wanted := _columns_that_fit()
    if wanted != grid.columns:
        grid.columns = wanted


## The name floor follows the font. A docker readied at boot has no theme yet,
## so the cells built then declared two lines of the engine's own font, and a
## one-line name sat its engine line higher than its neighbours' until a rebuild
## measured the theme's. The theme pass that changes the font size in
## Preferences is the same moment, and so is a palette switch, which is when
## the stars take their colours again.
##
## Entering and leaving the tree is when the stars start and stop hearing the
## profile, so a chooser a suite built and never freed does not rebuild its grid
## on every profile load of every suite after it.
func _notification(what: int) -> void:
    if stars != null and (what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EXIT_TREE):
        stars.listen(what == NOTIFICATION_ENTER_TREE)
        tag_filter.listen(what == NOTIFICATION_ENTER_TREE)
    # The picture under way holds an easel, which is not a reference.
    if what == NOTIFICATION_PREDELETE and cells != null:
        cells.drop()
    if what != NOTIFICATION_THEME_CHANGED or cells == null:
        return
    if stars != null:
        stars.repaint()
    _name_column = name_width()
    cells.name_floor = Vector2(_name_column, _name_height())
    cells.refresh()


## The width the host gave, which is not the width this control has grown to.
##
## **The host that declares a width is asked for that**, because a declared
## width is the one number in this chain the grid cannot move. The bar's popup
## gives the chooser a column of `CHOOSER_WIDTH`, and the popup itself is a
## `Window` sized to its content, so the column's own `size` is whatever the
## grid last talked it into and its `custom_minimum_size` is what the host
## meant. A host that declares nothing, which is the docker's margin inside its
## scroll, is asked for its area instead, and that is safe because
## `_columns_that_fit` never returns a count whose grid is wider than the width
## it was counted against.
func _host_width() -> float:
    var host := get_parent_control()
    if host != null and host.custom_minimum_size.x > 0.0:
        return host.custom_minimum_size.x
    return get_parent_area_size().x


func _sync_tag_row() -> void:
    if tag_option == null:
        return
    _tag_rows.assign(store.all_tags())
    var on := _tags_on()
    if not on.has(_selected_tag):
        _selected_tag = ""
    # The open list names the tags alone, since the list is plainly of tags, and
    # the closed button says what it filters by, which is the line below. A tag
    # that is on carries its state's mark, `SaBrushPresetTagFilter.ICONS`.
    var rows: Array = [{"id": TAG_ALL_ID, "label": tr("All")}]
    for tag: String in _tag_rows:
        rows.append(
            {
                "id": tag,
                "label": SaBrushPresetTagFilter.label_of(tag),
                "icon": String(SaBrushPresetTagFilter.ICONS.get(on.get(tag, ""), ""))
            }
        )
    # The auto tags after the stored ones, the bundles and then the engines,
    # each under a heading of its own, by its title and toggled as a tag is.
    var auto := SaBrushPresetTagFilter.auto_words(store)
    for at: int in auto.size():
        if not auto[at].is_empty():
            rows.append({"section": tr("Bundles") if at == 0 else tr("Engines")})
        for word: String in auto[at]:
            var mark := String(SaBrushPresetTagFilter.ICONS.get(on.get(word, ""), ""))
            rows.append({"id": word, "label": SaBrushPresetTagFilter.label_of(word), "icon": mark})
    # The two acts, under the tags they act on and only while one is on. A
    # painter who has never filtered by a tag is offered neither, which is the
    # same rule the row itself is drawn under.
    if not _selected_tag.is_empty():
        rows.append({"id": TAG_RENAME_ID, "label": tr("Rename tag...")})
        rows.append({"id": TAG_DELETE_ID, "label": tr("Delete tag...")})
    tag_option.set_choices(rows)
    # All is the chosen row while no tag is on, so a press on it says nothing. While
    # one is, no row is chosen, because the marks are the state and a press on a
    # tag already pressed has to be heard to move it on.
    var words := tag_filter.button_words(on)
    if on.is_empty():
        tag_option.select_value(TAG_ALL_ID)
        # "Tag: All" is one message rather than "All" dropped into the tag's line,
        # so a language can agree the word with "Tag". A tag is the painter's word.
        tag_option.text = words
    else:
        tag_option.clear_choice(words)
    # Sara's own "Tag: All" breaks onto a second line where a language longer
    # than English cannot fit it beside the thumbnail choice, and stays the one
    # line it was in English. A tag the painter named is cut with an ellipsis as
    # before, since a long one would stack line on line.
    tag_option.wrap_its_words(on.is_empty())
    # Not drawn at all while nothing is tagged, which is `ToolOptionsPresets`'
    # rule and the reason a painter who never tags a preset never meets a filter
    # that can only say All.
    tag_option.visible = not _tag_rows.is_empty() or not auto[0].is_empty() or not auto[1].is_empty()


## How wide every cell's name column is: the picture, or the widest word of any
## name the grid lists at the name's own font, whichever is wider.
##
## One width for every cell rather than one per name, so the columns line up and
## `_columns_that_fit` takes its pitch from a number the whole grid shares. Taken
## from the names and never from the host, which is what keeps the column
## ratchet shut: a wider host changes nothing this measures. Capped at `NAME_WORD_CAP`
## of the largest icon, so one painter's very long word does not set the grid.
func name_width() -> float:
    var picture := float(SaUI.px(icon_size()))
    var font := get_theme_font("font", "Label")
    if font == null:
        return picture
    var font_size := get_theme_font_size("font_size", "Label")
    var widest := 0.0
    for stored_name: String in _names:
        for word: String in stored_name.split(" ", false):
            widest = maxf(widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    var wanted := ceilf(widest) + float(SaUI.px(NAME_PAD * 2))
    return clampf(wanted, picture, maxf(picture, float(SaUI.px(MAX_ICON)) * NAME_WORD_CAP))


## The height `NAME_LINES` lines of a name's font take, which is the floor a
## cell declares for its name.
##
## A declared height rather than the label's own minimum, because a wrapping
## `Label` that is also allowed to trim reports a minimum height of one pixel:
## the wrap is what keeps the name out of the cell's width, and this is what
## keeps it on the screen.
##
## Asked of this control for the `Label` type rather than of the label, because
## a theme change notifies this control with the cells' own caches still stale:
## the label answered the old size from inside the notification and the new one
## a line after it. The name carries no override of its own, so the two
## questions have one answer once the caches agree.
func _name_height() -> float:
    var font := get_theme_font("font", "Label")
    if font == null:
        return float(SaUI.px(SaUI.get_font_size() * NAME_LINES))
    return font.get_height(get_theme_font_size("font_size", "Label")) * float(NAME_LINES)


## Draws *button* as the preset in use: a rim in the accent on every state, and
## the name in the accent rather than the body colour, the name being *label*
## when the picker sets it under the picture and the button's own words when it
## has no label.
##
## **Every picker calls this one**, the grid, Recent Presets and the Pop-up
## Palette's ring. Each drew a preset its own way, and Recent Presets and the
## ring did not say which preset was in use at all, so a painter who learnt the
## mark in the grid looked for it in the other two and found nothing. Static,
## because what a mark looks like belongs to no grid.
##
## **A mark is for the life of its button.** Its colours are bound to the palette
## so it follows a theme switch, and a binding has no undoing, so a picker whose
## mark moves builds the button that loses it again: the grid and Recent Presets
## rebuild every row anyway, and the ring builds the one cell.
##
## **The content margin is what makes the rim visible at all.** A cell's picture
## is drawn with `expand_icon`, which stretches it over everything the box's
## margins leave, so with no margin the thumbnail would paint straight over a
## two pixel rim, and a marked cell would differ from its neighbours only in the
## label's colour. The margin is
## the button's own box's, never narrower than the rim, so the picture starts
## inside the rim and is the size an unmarked neighbour's is, rather than the
## rim's width alone, which would draw the marked tile's picture larger than the
## rest and put a row's words against its rim.
##
## **Nothing the mark adds is wider than the box it replaces**.
## `_columns_that_fit` takes the widest cell as the grid's pitch, so a marked
## cell wider than the rest would move every other cell whenever the mark landed
## on it. It does not: the margins are the box's own, the button's
## `custom_minimum_size` is the icon size, and a `Button` with `expand_icon` asks
## for nothing towards it.
static func draw_mark(button: Button, label: Label = null) -> void:
    var rim := float(SaUI.px(MARK_BORDER))
    for state: String in MARK_STATES:
        var own := button.get_theme_stylebox(state)
        var style := StyleBoxFlat.new()
        SaTheme.bind(style, {"bg_color": "bg_slider", "border_color": "accent_primary"})
        style.set_border_width_all(SaUI.px(MARK_BORDER))
        for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
            style.set_content_margin(side, maxf(rim, own.get_margin(side) if own != null else 0.0))
        button.add_theme_stylebox_override(state, style)
    if label != null:
        SaTheme.bind_font(label, "accent_primary")
        return
    for colour: String in MARK_FONT_COLORS:
        SaTheme.bind_font(button, "accent_primary", colour)


## Puts the picture at *path* on *button*, the cached thumbnail of a preset, and
## answers whether there was one to put. Static and public for the reason
## `draw_mark` is: Recent Presets shows the same picture the grid does, and a
## thumbnail drawn two ways is two thumbnails.
static func show_picture(button: Button, path: String) -> bool:
    if path.is_empty() or not FileAccess.file_exists(path):
        return false
    var image := Image.load_from_file(path)
    if image == null:
        return false
    button.icon = ImageTexture.create_from_image(image)
    # A thumbnail is a picture rather than a glyph, so it is the one icon that
    # must not take the theme's icon colour: that colour is the palette's text,
    # which is right for a monochrome glyph and would flatten a rendered stroke
    # to a black bar under a light palette.
    for state: String in SaThemeDefaults.ICON_STATES:
        button.add_theme_color_override(state, Color.WHITE)
    return true


## One share of the frame for the cells still to build, or once none waits for
## the pictures still to come, so a grid of fifty-two presets to build and
## draw keeps the window at the display's rate.
func _process(_delta: float) -> void:
    cells.build(SaBrushPresetCells.SLICE_USEC)


## The choice writes the profile, and the profile is what the grid reads, so a
## painter who wants tips gets them on the other host and after a restart.
func _on_thumb_selected(row: Variant) -> void:
    SaSettings.preset_thumb_tip = String(row) == THUMB_TIP
    refresh()


## A row of the tag dropdown: All turns every tag off, a tag moves one state on,
## and the two acts under them act on the tag last pressed.
##
## The acts are read before the filter is written, because both of them are
## about the tag that is on and writing the row's own id first would leave the
## filter on a word no preset carries.
func _on_tag_selected(tag: Variant) -> void:
    var row := String(tag)
    if row == TAG_RENAME_ID:
        _begin_tag_rename()
        return
    if row == TAG_DELETE_ID:
        _ask_tag_delete()
        return
    if row == TAG_ALL_ID:
        _selected_tag = ""
        tag_filter.clear()
    else:
        # An auto tag cycles as a tag does and is never the tag the acts are on,
        # since a bundle or an engine is not renamed or deleted from here.
        var now_on := not tag_filter.cycle(row).is_empty()
        if not SaBrushPresetTagFilter.is_auto(row):
            _selected_tag = row if now_on else ""
    refresh()


## Opens the name field on the tag being filtered by, seeded with it.
func _begin_tag_rename() -> void:
    if tags == null or _selected_tag.is_empty():
        # The dropdown is put back on the filter, because a row that did nothing
        # must not leave the button reading Rename tag.
        _sync_tag_row()
        return
    tags.begin_rename(_selected_tag)
    _sync_tag_row()


func _ask_tag_delete() -> void:
    if tags != null and not _selected_tag.is_empty():
        tags.ask_delete(_selected_tag)
    _sync_tag_row()


## The library's tags moved. The grid, the filter row and the dropdown all come
## off the store, so a rebuild is the whole of the answer.
##
## *follow* is the tag the gesture says the painter is still looking at, which a
## rename fills and everything else leaves empty. It is taken only when the
## library really carries it, so a rename that wrote nothing cannot leave the
## filter pointing at a word that is not there (the loud failure rule of `capture_tags`, one layer up).
func _on_tags_changed(follow: String) -> void:
    if store == null:
        return
    if not follow.is_empty() and _carries_tag(follow):
        tag_filter.renamed(_selected_tag, follow)
        _selected_tag = follow
    refresh()


## A right press on a cell opens the tag menu for its preset at the pointer,
## which is where a painter's hand is at the moment they decide a brush belongs
## somewhere. *at* is the press measured by `SaPopupRect.at_press`.
func _on_menu_asked(stored_name: String, button: Button, at: Vector2i) -> void:
    if tags != null:
        tags.open_menu_for(stored_name, button, at)


## A right press on the chooser that no tile took, the grid around and under the
## cells and the empty line, opens the menu with New preset... alone, so a library
## emptied of every preset still has one. At the pointer, as every right-click
## menu opens.
func _gui_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press != null and press.pressed and press.button_index == MOUSE_BUTTON_RIGHT and tags != null:
        tags.open_menu_for("", grid, SaPopupRect.at_press(press, self))
        accept_event()


## The slider writes the profile, and the profile is what the grid reads, so the
## size survives a restart without this control remembering anything.
func _on_icon_size_changed(value: float) -> void:
    SaSettings.preset_icon_size = int(value)
    refresh()


# --- What a dump and a scenario read -------------------------------------------


## Every name the grid is showing, in the order it shows them.
func visible_names() -> Array[String]:
    return _names.duplicate()


## The chooser's own report: what is on screen, what it is filtered by, and how
## many cells are still waiting for a stroke.
##
## `pending` is the number that says the grid opened without rendering: a chooser
## that drew every thumbnail before it appeared would report zero on the first
## frame and a stall in the picture. `building` is the same for the cells of a
## grid built in shares.
##
## `marked` is the cell drawn as the loaded preset, and it is here because a rim is the
## one thing in this report a screenshot argues about. A dump that names the cell settles
## which one it is, and empty settles that the brush is on no preset or that a filter has
## hidden the one it is on. `added` names the marked cell when it is in the grid only
## because it is in hand, [member keeps_loaded], and is empty otherwise.
##
## `cell` is the width and height of a cell's picture, so a dump settles the
## square the tip is drawn in rather than a screenshot arguing about it.
func chooser_report() -> Dictionary:
    var report := {
        "names": visible_names(),
        "count": _names.size(),
        "marked": _marked,
        "added": _added,
        "tag": _selected_tag,
        "tag_filter": _tags_on() if store != null else {},
        "bundles": SaBrushPresetTagFilter.auto_words(store)[0] if store != null else PackedStringArray(),
        "engines": SaBrushPresetTagFilter.auto_words(store)[1] if store != null else PackedStringArray(),
        "stored_tags": store.all_tags() if store != null else PackedStringArray(),
        "tags_empty_line": tag_filter.empty_line.text if tag_filter.empty_box.visible else "",
        "tags": tags.tags_of(_names) if tags != null else {},
        "search": search_field.text if search_field != null else "",
        "icon_size": icon_size(),
        "columns": grid.columns if grid != null else 0,
        "thumb": "tip" if showing_tip() else "strokes",
        "stars": stars.report(store),
        "bundle_menu": SaBrushPresetBundles.report_of(store),
        "empty_line": empty_line.text if empty_line.visible else "",
    }
    report.merge(cells.report())
    return report


## Shows only the tag *tag*, every other one off, or turns all off when it is empty.
##
## A tag no preset carries is a loud failure and not a quiet All, or
## `{"preset": {"tag": "Paint"}}` would photograph the whole library, the
## shipped tag being `paint` in lower case. `sara_shot.py` reads a line
## carrying both `SaCapture:` and `failed` as a problem, which is why the
## warning is worded the way it is, and it names the tags there are so the next
## scenario does not have to guess. A control name that resolves to nothing is
## a failure in the same way, rather than a click at the origin.
##
## The filter is left where it was rather than cleared, because a step that
## failed has no business changing what the picture shows. Case is left alone on
## purpose too: folding it would make the step accept a tag the painter's own
## popup does not offer, which is the same bug one layer down. An auto tag is
## named by its title or an engine's id, `Sara Basic` or `noise`.
func capture_tag(tag: String) -> void:
    var auto := SaBrushPresetTagFilter.auto_named(store, tag) if not _tag_rows.has(tag) else ""
    if not auto.is_empty():
        tag_filter.only(auto)
        refresh()
        return
    if not tag.is_empty() and not _tag_rows.has(tag):
        # Clearing is a thing a painter does, so an empty tag never comes here.
        push_warning(
            (
                "SaCapture: preset tag failed, nothing is tagged '%s'. The tags are: %s"
                % [tag, ", ".join(_tag_rows) if not _tag_rows.is_empty() else "(none)"]
            )
        )
        return
    _selected_tag = tag
    tag_filter.only(tag)
    refresh()


## Hands a scenario's `tags` block to the gesture that owns it, with the cell
## the menu opens under resolved from the grid.
##
## A forwarder rather than the steps themselves, because the menu, the field and
## the question are `SaBrushPresetTags`' and a door onto a gesture belongs beside
## the gesture. What this file knows and that one does not is which cell is
## which, so that is the whole of what it adds.
func capture_tags(spec: Dictionary) -> Dictionary:
    if tags == null:
        return {}
    # Every cell built, since a menu opens under a picture.
    cells.build(-1)
    # Under the grid when no cell is named, where a right press outside every cell opens it.
    var over := String(spec.get("menu", ""))
    var anchor: Control = grid if over.is_empty() else null
    var cell := grid.get_node_or_null("Cell_%s/Icon" % over.validate_node_name())
    if not over.is_empty() and cell != null:
        anchor = cell as Control
    var report := tags.capture_tags(spec, _selected_tag, anchor)
    report["tag"] = _selected_tag
    return report


## Builds every cell still to come and drains the render queue, for a test or
## a scenario that wants the grid finished rather than filling.
func capture_finish() -> void:
    cells.finish()
