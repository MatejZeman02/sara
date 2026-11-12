## The Recent Presets docker: the presets last loaded, most recent first, each a
## button that loads it again.
##
## **Not called History**, because the Info docker's History section and the
## `history` block of every state dump are the undo stack and this docker is
## not. A reviewer seeing a "History" list Fill, Paint and Sketch in a
## screenshot would file a bug against the wrong docker.
##
## The class and the node are `HistoryDocker`, because that string is a key
## rather than a word: `docker_layout.cfg` files it under it, `FILE_NAME`
## below is `preset_history.cfg`, and renaming either would cost a
## migration to move a painter's window back where they left it. What a painter
## reads is the title, the Dockers menu entry and the shortcut's name, and those
## three say Recent Presets.
##
## Without it nothing records which presets were used, so a painter who tried
## four in a row would have no way back to the second.
##
## The list is the docker's own state rather than the preset store's. A preset
## is a file and a history is an order of visits, so the two go stale in
## different ways: deleting a preset leaves its visit behind, and the docker
## drops a name it cannot load any more rather than showing a button that fails.
##
## It records what the *bar* loaded, over `EventBus.preset_loaded`, so a preset
## reached from the bar's dropdown, from this docker, or from a chord somebody
## adds later all land in one place.
##
## **A row is the preset's picture beside its name, and the row in use carries
## the grid's mark**, the grid's own look, so the places a preset is picked from
## draw it one way and a painter reads the brush off this list too: the picture
## is the grid's own cached thumbnail and the mark is
## `SaBrushPresetsChooser.draw_mark`. The docker draws no picture. A row whose
## picture is not on disk yet shows the name alone and takes the picture when the
## grid's queue has drawn it, so one renderer writes each file.
@tool
extends DockerWindow

class_name HistoryDocker

const PresetPickAfter := preload("res://ui/dockers/presets/preset_pick_after.gd")

## What the docker opens at. Narrow and tall, because a row is one name.
const DEFAULT_SIZE := Vector2i(220, 280)

## Beside `docker_layout.cfg` for the reason `SaPresetStore` gives for the
## preset directory: it is the painter's own trail rather than a preference,
## and the profile file has migrations a list of names does not want.
## A file under the data root.
const FILE_NAME: String = "preset_history.cfg"

const SECTION: String = "history"
const KEY: String = "names"

## The cap. Twenty rows is more than a docker this size shows at once,
## which is the point: the scroll holds the tail and the top holds the answer.
const MAX_ENTRIES: int = 20

## A row's height in logical pixels, which with the box's margins leaves the
## picture 32 high, a stroke 64 wide beside the name, half the size the grid
## draws it at its largest. Tall enough that the brush reads, and short enough
## that the docker's default height still shows five rows, where the rows of
## words alone showed eight.
const ROW_HEIGHT: int = 40

## The widest a row's picture is drawn, in logical pixels, which is a stroke's
## two to one at the row's height. A tip is square and narrower.
const PICTURE_WIDTH: int = 64

## How often a row with no picture looks for one, in seconds. A look is two file
## dates, and the grid's queue draws a picture a frame, so four looks a second
## shows a picture about as soon as it lands without asking every frame.
const WAIT_SECONDS: float = 0.25

## Where the list is kept. A test points it somewhere of its own.
var path: String = SaDataRoot.path(FILE_NAME)

## The names, most recent first. Public so a test can read what a load did
## without going through the rows.
var entries: PackedStringArray = PackedStringArray()

var rows: VBoxContainer = null
var empty_label: Label = null

## What a name is checked against on the way in from disk, and where a row's
## picture is looked for. Public so a test can point it at a directory of its own
## rather than at the painter's presets.
var store: SaPresetStore = SaPresetStore.new()

## What answers the name of the preset in use, the empty string for none. Empty
## in the app, where the docker asks the bar the grid asks, and public so a test
## can say what is loaded without a bar, the way `store` is.
var loaded_source: Callable = Callable()

## The rows still showing their name alone, by name. Written by `_rebuild` and
## `take_pictures`.
var _waiting: Dictionary[String, Button] = {}

## The seconds since the waiting rows last looked.
var _waited: float = 0.0

## Whether a walk through the list is under way, Ctrl+R's. While it is, a load
## lights its row and leaves the order alone. Written by `begin_walk` and
## `end_walk`.
var _walking: bool = false

## The row the walk has reached, empty when no walk is under way. Written by
## `record`, `begin_walk` and `end_walk`.
var _lit: String = ""

## What scrolls the rows, kept so a lit row is scrolled into view. Written by
## `_init`.
var _scroll: ScrollContainer = null

## The write of the list and the rows' rebuild a load heard over
## `EventBus.preset_loaded` leaves for the frame after it, 7 to 8 ms of the
## frame a preset was picked in otherwise.
var after_pick: PresetPickAfter = PresetPickAfter.new()


func _init() -> void:
    _init_docker(SaDockerIds.HISTORY, "Recent Presets", DEFAULT_SIZE, Vector2i(150, 140))
    # Where a fresh profile finds it: under the colour picker on the right,
    # beside the bar the presets are loaded from.
    position = Vector2i(2, 700)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Recent Presets")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _scroll = SaMake.scroll(margin, "Scroll")
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    rows = SaMake.column(_scroll, "Rows", 2)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    empty_label = SaMake.label(rows, "EmptyState", tr("No presets loaded yet."))
    empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    empty_label.tooltip_text = tr("Load a preset from the bar and it appears here, newest first.")


func _ready() -> void:
    _setup_docker_ready()
    load_from(path)
    if not EventBus.preset_loaded.is_connected(_on_preset_loaded):
        EventBus.preset_loaded.connect(_on_preset_loaded)
    if not EventBus.preset_store_changed.is_connected(forget_deleted):
        EventBus.preset_store_changed.connect(forget_deleted)
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    if not SaSettings.changed.is_connected(_on_setting_changed):
        SaSettings.changed.connect(_on_setting_changed)
    apply_layout_settings()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.HISTORY)


## The docker in the tree *node* is in, null when it is not built.
static func in_tree(node: Node) -> HistoryDocker:
    if node == null or not node.is_inside_tree():
        return null
    return node.get_tree().root.find_child(String(SaDockerIds.HISTORY), true, false) as HistoryDocker


## Holds the order while Ctrl+R walks the list, as Alt+Tab holds the windows
## still while it is held. Each load the walk makes lights its row rather than
## moving it to the top, and nothing is written until `end_walk`.
func begin_walk() -> void:
    _walking = true
    _lit = ""


## Lets go of the order and puts *reached* at the top, every other row keeping
## its place, the empty string for a walk that loaded nothing.
func end_walk(reached: String) -> void:
    _walking = false
    _lit = ""
    record(reached)


## Puts *preset_name* at the top, without a second copy of it further down, and
## writes the list. What `EventBus.preset_loaded` reaches.
##
## The brush put on no preset records nothing and still redraws the rows, since
## the row that was in use is not any more. During a walk a load lights its row
## and moves nothing, so the list the painter is walking stays where it is.
##
## With *at_once* false the order is the new one at once and the file and the
## rows follow in the frame after, through `after_pick`, except during a walk.
func record(preset_name: String, at_once: bool = true) -> void:
    var saves := not _walking and not preset_name.is_empty()
    if _walking:
        _lit = preset_name
    if saves:
        var wanted := PackedStringArray([preset_name])
        for kept: String in entries:
            if kept != preset_name and wanted.size() < MAX_ENTRIES:
                wanted.append(kept)
        entries = wanted
    # A walk lights its row in the frame of its R, since the walk's own load is
    # not a pick from the grid and the painter is reading the rows as they go.
    if at_once or _walking:
        if saves:
            save_to(path)
        _rebuild()
        return
    if saves:
        after_pick.ask(&"save", func() -> void: save_to(path), get_tree() if is_inside_tree() else null)
    after_pick.ask(&"rows", _rebuild, get_tree() if is_inside_tree() else null)


## A load anywhere, recorded with its file and rows left for the next frame.
func _on_preset_loaded(preset_name: String) -> void:
    record(preset_name, false)


## Takes the row of a preset that was deleted. The list was pruned only when the
## file was read at start, so a preset deleted in this session kept a row whose
## click loaded nothing.
##
## A save keeps every row and redraws them, because it puts the brush on the
## preset it wrote, which moves the mark, and leaves that preset's picture
## behind its file until the grid draws it again.
func forget_deleted(preset_name: String, saved: bool) -> void:
    if saved:
        _rebuild()
        return
    if not entries.has(preset_name):
        return
    var kept := PackedStringArray()
    for entry: String in entries:
        if entry != preset_name:
            kept.append(entry)
    entries = kept
    save_to(path)
    _rebuild()


## Loads the preset a row names, through the bar, so the bar's own dropdown and
## its name field follow. Answers false when the bar is not there to ask.
func load_entry(preset_name: String) -> bool:
    var presets := ToolOptionsPresets.in_tree(self)
    return presets.load_preset(preset_name) if presets != null else false


## A press on a row, which the usage tally counts as a pick here, where a call
## of [method load_entry] counts none.
func _on_row_pressed(preset_name: String) -> void:
    SaUsageTally.preset_picked(SaUsageTally.RECENT_PRESETS)
    load_entry(preset_name)


## The list as it is on disk. A name whose preset has been deleted is dropped
## on the way in rather than shown as a button that cannot work.
func load_from(from_path: String) -> void:
    entries = PackedStringArray()
    var config := ConfigFile.new()
    if config.load(from_path) == OK:
        for stored: String in config.get_value(SECTION, KEY, PackedStringArray()) as PackedStringArray:
            if entries.size() < MAX_ENTRIES and store.has_preset(stored):
                entries.append(stored)
    _rebuild()


func save_to(to_path: String) -> void:
    var config := ConfigFile.new()
    config.set_value(SECTION, KEY, entries)
    config.save(to_path)


## Gives every row still showing its name alone the picture that has landed
## since, and stops looking once none is waiting. Public so a suite can ask
## without waiting out the seconds `_process` counts.
func take_pictures() -> void:
    for entry: String in _waiting.keys():
        if _show_picture(_waiting[entry], entry):
            _waiting.erase(entry)
    set_process(not _waiting.is_empty())


func _process(delta: float) -> void:
    _waited += delta
    if _waited < WAIT_SECONDS:
        return
    _waited = 0.0
    take_pictures()


## One button per entry, newest first, rebuilt whole: the picture, the name, and
## the mark on the preset in use. Twenty rows is nothing to build, and the
## alternative is bookkeeping that goes wrong the first time a name moves, and a
## mark that cannot be taken off a button in place.
func _rebuild() -> void:
    if rows == null:
        return
    for child in rows.get_children():
        if child != empty_label:
            # Removed as well as freed. `queue_free` alone leaves the node a
            # child until the next frame, and a docker built outside the tree
            # never gets one, so the rows piled up instead of being replaced.
            rows.remove_child(child)
            child.queue_free()
    empty_label.visible = entries.is_empty()
    var loaded := _loaded_name()
    _waiting.clear()
    for entry: String in entries:
        var button := SaMake.button(rows, "Row_" + entry, entry, tr("Load the %s preset again") % entry)
        button.clip_text = true
        button.text_overrun_behavior = SaTheme.TEXT_CUT
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.custom_minimum_size = Vector2(0, SaUI.px(ROW_HEIGHT))
        # The picture is fitted to the row's height and kept to its shape, and
        # the theme's icon cap, which would draw it glyph sized, is lifted to the
        # widest a stroke is drawn here.
        button.expand_icon = true
        button.add_theme_constant_override("icon_max_width", SaUI.px(PICTURE_WIDTH))
        button.pressed.connect(_on_row_pressed.bind(entry))
        if entry == loaded:
            SaBrushPresetsChooser.draw_mark(button)
        if entry == _lit:
            _light(button)
        if not _show_picture(button, entry):
            _waiting[entry] = button
    _waited = 0.0
    set_process(not _waiting.is_empty())


## Lights the row a walk has reached the way a pressed button is drawn, and
## scrolls it into view once the rows are laid out, so a walk past the fifth row
## is still seen.
func _light(button: Button) -> void:
    button.toggle_mode = true
    button.button_pressed = true
    _scroll_to.call_deferred(button.get_instance_id())


## Scrolls the button of *button_id* into view when it is still a row. By its id,
## since the next step of a walk can free the rows before the deferred call lands.
func _scroll_to(button_id: int) -> void:
    var button := instance_from_id(button_id) as Button
    if button != null and button.is_inside_tree():
        _scroll.ensure_control_visible(button)


## Puts *entry*'s picture on *button* when the grid has drawn it, the stroke or
## the tip as the grid shows them, and answers whether it did. A picture older
## than its preset is not shown, since it is a brush the preset is not any more.
func _show_picture(button: Button, entry: String) -> bool:
    var tip := SaSettings.preset_thumb_tip
    if SaPresetThumbs.is_stale(store.dir, entry, tip):
        return false
    return SaBrushPresetsChooser.show_picture(button, SaPresetThumbs.path_for(store.dir, entry, tip))


## The preset in use, from `loaded_source` when a test handed one and from the
## bar otherwise, which is where the grid asks.
func _loaded_name() -> String:
    if loaded_source.is_valid():
        return String(loaded_source.call())
    var presets := ToolOptionsPresets.in_tree(self)
    return presets.selected_preset if presets != null else ""


## The grid's Strokes and Tip choice is this docker's too, so a flip redraws the
## rows with the other picture.
func _on_setting_changed(property: StringName) -> void:
    if property == &"preset_thumb_tip":
        _rebuild()
