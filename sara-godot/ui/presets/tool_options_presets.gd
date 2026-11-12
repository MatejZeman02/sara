## The preset group of the tool options bar: the dropdown, the name field that
## replaces it while saving, and everything the popup's rows do.
##
## Split out of `ui/tool_options/tool_options_bar.gd` when it was 708 lines against the
## rule that a file over 600 gets a sibling. The preset group is the natural cut: it is the
## one part of the bar that owns a store, a filter and a selection of its own, and the rest
## of the bar only ever asks it to build itself and to refresh. What crosses the seam is
## two Callables, `settings_source` and `on_applied`, rather than a reference back to the
## bar, so this can be dropped into any surface with a settings resource behind it.
##
## One control wide, not three. Measured in the running app at 1920 and scale 1,
## the bar's slot is 1227 wide and its contents were 1182, so a dropdown with a
## Save and a Delete button beside it overran by 200 and pushed the exposure
## slider and both pressure toggles out of sight. Save and Delete are therefore
## items in the button's own popup, under the list of presets, and the name field
## takes the button's place rather than sitting next to it.
##
## The name field is inline rather than a dialog window for a second reason
## besides width: the suite runner blocks the moment a test adds a Window to the
## tree, so a modal here would be unverifiable by anything but a screenshot.
class_name ToolOptionsPresets
extends HBoxContainer

## What the preset button says, whatever is loaded: the word for what a press
## opens, rather than the preset in hand, which stays in the tooltip and in the
## docker's highlight. A button that read "Canvas Brush" would leave nothing
## on screen saying where the presets are.
const PRESET_LABEL: String = "Presets"

## The ids `_on_preset_menu_id` answers to, the programmatic door: the grid a
## painter clicks is a control, and a test, a capture and the two action
## buttons all press an action by id rather than by finding a row.
const PRESET_ID_SAVE: int = 10000
const PRESET_ID_DELETE: int = 10001

## Build a preset from the class defaults rather than forking the loaded one.
## There is otherwise no way to see the defaults, because a new preset can only
## be forked from an existing one, so this is the entry that
## answers "what are the default values" without a fork.
const PRESET_ID_NEW: int = 10002

## The tag rows above the list. `All` is the first, then one per tag, so a tag
## row's id is `PRESET_ID_TAG_BASE` plus its place in `_tag_rows`.
const PRESET_ID_TAG_ALL: int = 11000
const PRESET_ID_TAG_BASE: int = 11001

## The name field's narrowest. It replaces the button and opens as wide as the
## button when that is wider, so the bar does not jump while a preset is named.
const PRESET_WIDTH: int = 96

## The widest the button grows to fit its label, which the bar can afford. It
## held a preset's name once and keeps the room so that a language whose word
## for Presets is long is read whole rather than cut.
const PRESET_CAP: int = 180

## How long `prepare_scan` may take of one frame, in microseconds, a quarter of
## a frame at 60 Hz. A preset's facts are one load and a shipped preset one
## write, a few milliseconds each, and a slice passes the mark by at
## most one of them.
const PREPARE_SLICE_USEC: int = 4000

## Where presets are read and written. Its own by default, and replaced by
## whoever builds this when they already hold one: the tool options bar does,
## because the Keep blend checkbox writes to it before any control exists.
var preset_store: SaPresetStore = SaPresetStore.new()

var preset_menu: Button
var preset_name_edit: LineEdit

## **The grid is not here.** The button opens `BrushPresetsDocker`, a window of
## its own rather than a dropdown under the button, and Save as... and Delete
## are not here either, because they belong with the grid.
##
## This file still keeps the list of names and every action id, which is what
## the chords, the capture door and the tests press.

## Answers the tool a thumbnail is drawn by driving. Handed over the same way
## `settings_source` is, and for the same reason: this group has no opinion about
## tools and the surface it sits on does.
var tool_source: Callable = Callable()

## Answers the settings resource a preset is read from and written onto. Set by
## whoever builds this, because which resource that is depends on which tool the
## surface is showing and this group has no opinion about tools.
var settings_source: Callable = Callable()

## Called after a preset has been applied, so the surface can pull its controls
## back into line with the settings that just changed under them.
var on_applied: Callable = Callable()

## Answers the descriptor of the tool the surface shows, or null. Handed over for
## the reason `tool_source` is: the Brush Presets docker dims the cells of an
## engine that tool will not take, and the surface is what knows the tool. The
## docker asks this rather than the bar itself, which would have it walk the
## tree to a class of another package.
var descriptor_source: Callable = Callable()

## Answers the engines the tool the surface shows paints with, each preset engine
## it takes to the `ToolState` that paints it: the stamp and the noise engine
## while the Brush is shown, one entry for a tool of one engine, and none for a
## host that does not say. Handed over for the reason `tool_source` is, and read
## by the shelf a refresh installs, the docker's dim and a load.
var engines_source: Callable = Callable()

## Makes the surface's tool the one that paints presets of the engine it is
## handed, and answers whether it could. A load of another engine's preset asks
## it first, so the Brush takes the noise engine up for a noise preset rather
## than refusing it.
var engine_switch: Callable = Callable()

## Row index in the popup for each preset name, so a click can be resolved
## without re-reading the directory or trusting the item's label.
## The rows behind `preset_names`, for a caller that wants the popup id of one.
var preset_rows: Array[String] = []
## The preset the button is showing, empty when none is loaded.
var selected_preset: String = ""
## The preset that was in the hand before `selected_preset`, empty until a
## second one has been. What Switch to the previous preset loads.
##
## Kept here rather than read off Recent Presets, whose list is a docker's and
## goes with it when the docker is closed. Every door a preset comes in by, a
## slot, a cell of the grid and the ring, loads through `load_preset`, so each
## counts alike.
var previous_preset: String = ""

## What a load that took the brush to Erase owes it. A preset that erases writes
## the blend mode onto the settings, and this puts the mode back when the
## painter turns to a tool that paints.
var blend_memory: SaBrushPresetErase = null

## The tags the popup is offering, in the order it offers them, and the one
## being filtered by. Empty means All.
var _tag_rows: Array[String] = []
## The tag the list is filtered by, empty for All.
var selected_tag: String = ""

## Whether the bundle files the modules ship have been offered this session.
## Once a session and not once a refresh, because offering one means opening its
## zip to read its title, and a refresh costs no file read at all.
var _bundles_offered: bool = false

## The Brush Presets docker as `_presets_docker` last found it, null until then
## and after it left the tree.
var _docker: BrushPresetsDocker = null

## Emitted once by `scan`, when the list a held boot kept empty is read.
##
## The Brush Presets docker waits on it rather than binding to a store that has
## not been listed yet, so a docker the layout opens during the boot fills when
## the scan lands and never holds a boot frame of its own.
signal scanned

## True from `hold_scan` until `scan`, and while it is, `refresh` reads nothing.
##
## The first refresh with a tool behind it writes the shipped recipes, reads
## every preset's tags and builds the docker's grid, which would make the frame
## that binds the bar to the tool machine the boot's longest. Held, that frame
## lists nothing, and `MainDockers` calls `scan` once the first frame after
## `ready` has drawn.
##
## False on a group nobody holds, which is every suite's, so a bar built
## without the boot lists its presets on the first refresh.
var scan_held: bool = false

## Whether the held scan's `prepare_scan` has written the shipped shelves and
## the modules' bundles, so its later slices only read.
var _shelves_written: bool = false

## How far `scan_in_slices` has come: its reads done, then the first brush.
var _read_ahead: bool = false
var _picked_ahead: bool = false


func _init() -> void:
    name = "PresetBox"
    blend_memory = SaBrushPresetErase.new()
    blend_memory.gave_back.connect(release_preset)
    add_theme_constant_override("separation", 0)
    size_flags_vertical = Control.SIZE_SHRINK_CENTER

    preset_menu = SaMake.button(self, "PresetMenu", tr(PRESET_LABEL), _menu_tip(""))
    preset_menu.clip_text = true
    # A name past the cap ends in a mark, with the whole of it in the tooltip.
    preset_menu.text_overrun_behavior = SaTheme.TEXT_CUT
    # A toggle, not a dropdown whose arrow promised a list. Pressed is
    # the docker being open, which `_sync_pressed` keeps.
    preset_menu.toggle_mode = true
    SaTheme.make_toggle(preset_menu)
    preset_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    preset_menu.set_meta(SaUI.FONT_SCALE_META, SaUI.SMALL_FONT_SCALE)
    _fit_menu()
    # The bar's rule, kept here because the preset group is one of the bar's
    # controls in a file of its own: a click must leave the keyboard with the canvas, not
    # with the button, or a held Space after it pans nothing and opens this
    # instead.
    preset_menu.focus_mode = Control.FOCUS_NONE
    preset_menu.pressed.connect(toggle_presets_docker)

    preset_name_edit = SaMake.line_edit(self, "PresetNameEdit", "", tr("Name"))
    preset_name_edit.visible = false
    preset_name_edit.custom_minimum_size = Vector2(DockerUtils.px(PRESET_WIDTH), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2))
    preset_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    preset_name_edit.set_meta(SaUI.FONT_SCALE_META, SaUI.SMALL_FONT_SCALE)
    preset_name_edit.text_submitted.connect(_on_preset_name_submitted)
    preset_name_edit.focus_exited.connect(_on_preset_name_abandoned)
    # Escape closes the field and stops there, rather than reaching the window
    # or the docker behind it.
    preset_name_edit.gui_input.connect(_on_preset_name_gui_input)
    SaBrushPresetBundles.follow(self, refresh)


func _enter_tree() -> void:
    blend_memory.attach()
    SaPresetsInHand.attach_group(preset_engine, import_presets_through, load_preset)


func _exit_tree() -> void:
    blend_memory.detach()
    SaPresetsInHand.detach_group(self)


## Opens the Brush Presets docker, focused, which is what the Presets button
## does.
##
## *at* is where the docker opens when it is closed, and nothing from the button:
## a button opens a window where the painter left it, and only the right click on
## the canvas has a point to open one at.
##
## Public because an injected click does not route into a docker's `Window`, so
## the capture door presses this. False with no docker to open.
func open_presets_docker(at: Variant = null) -> bool:
    var docker := _presets_docker()
    return docker != null and docker.reveal(at)


## Opens the docker when it is closed and closes it when it is open, which is
## what the Presets button does and what the Z key does beside it.
##
## A second press of the button closes it, and so does a second right press on
## the canvas.
##
## The right press does not arrive through here. A tool machine is built per
## surface and holds no bar, so `_right_click_opens_a_docker` in
## `tool_machine.gd` asks the chosen docker's `toggle_at` through
## `SaRightClickDocker`, which lends it on a borrow.
##
## Answers whether the docker ended up open, false in a host with no docker.
func toggle_presets_docker() -> bool:
    var docker := _presets_docker()
    if docker != null and docker.visible:
        docker.conceal()
    elif docker != null:
        docker.reveal()
    _sync_pressed()
    return docker != null and docker.visible


## Puts the class defaults in front of the painter, with no preset loaded.
##
## There is otherwise no way to see the defaults, because a new preset can only
## be forked from an existing one. So this builds a fresh
## instance of whatever settings script the tool carries and copies it over the
## live resource, which is the same copy a load makes and in the same direction:
## the object every surface holds is written in place rather than replaced.
##
## Nothing is written to disk. A new preset is the defaults on the brush, and
## Save as... beside it is what names them, so a painter who only wanted to look
## at the defaults leaves no file behind.
##
## Answers false when there is no settings resource to write, which is what a
## bar built in a test with no tool gets.
func new_preset() -> bool:
    var settings := _settings()
    var script := settings.get_script() as Script if settings != null else null
    if settings == null or script == null:
        return false
    var defaults := script.new() as Resource
    if defaults == null:
        return false
    SaPresetStore.copy_settings(defaults, settings)
    blend_memory.forget()
    release_preset()
    return true


## Takes the brush off the preset in hand and tells every surface, which is what
## New does and what an edit of the preset's blend mode does.
##
## The same announcement a load makes, so the History docker records that the
## brush changed under it and the grid and the Pop-up Palette drop their mark.
func release_preset() -> void:
    _hold("")
    sync_menu()
    if on_applied.is_valid():
        on_applied.call()
    EventBus.preset_loaded.emit("")


## Presses an action by id, which is what the docker's Delete and New do. Its
## Save as... asks in a field of its own and saves through the same call. The
## ids are the programmatic door, so a chord, a capture and a button agree.
func press_action(id: int) -> void:
    _on_preset_menu_id(id)


## The engine whose presets the tool the surface shows takes, or empty for a tool
## that takes none at all.
##
## **Declared, never a name a script happens to have.** `SaPresetMeta.engine_of`
## answers the id a settings resource is told apart by and falls back to the
## script's global name, so the gradient's `SaGradientEnds` read as an engine
## called `Sa Gradient Ends`: every cell was dimmed under a class name in words no
## painter has seen, and Save as... wrote a preset of it. A tool that declares no
## engine takes no presets, so the grid dims nothing against it and there is
## nothing for a save to write.
##
## The descriptor's own word first, then what the settings it carries declares,
## which is the order the docker's dim has always read the two in. The second is
## the store's reading rather than this file's, so the rule has one owner.
func preset_engine() -> StringName:
    var shown: Variant = descriptor_source.call() if descriptor_source.is_valid() else null
    var descriptor := shown as SaToolDescriptor
    if descriptor != null and not String(descriptor.preset_engine).is_empty():
        return descriptor.preset_engine
    return SaPresetStore.preset_engine_of(_settings())


## Every engine whose presets the tool the surface shows paints: each engine of
## the Brush while it is shown, and otherwise [method preset_engine] alone, or
## nothing for a tool that takes no presets.
##
## The engine in hand first, then the rest in registration order, so the Brush
## on its noise engine answers the noise first. The docker's cells say their
## engine only where it is not the first.
func preset_engines() -> Array[StringName]:
    var engines: Array[StringName] = []
    engines.assign(_engines().keys())
    var own := preset_engine()
    if engines.is_empty() and not String(own).is_empty():
        engines.append(own)
    if engines.has(own):
        engines.erase(own)
        engines.push_front(own)
    return engines


## Whether the action for *id* can be pressed: Delete needs something loaded to
## delete, New needs settings to put the defaults on, and Save as... needs a tool
## that takes presets of some engine.
##
## The rule rather than the control. The buttons are the docker's, so the
## claim "Delete is dead with nothing selected" would otherwise only be askable
## of a host that has a docker in it, and this bar runs in three that do not: a
## test, the info docker's scratchpad and the brush editor's.
func action_available(id: int) -> bool:
    if id == PRESET_ID_DELETE:
        return not selected_preset.is_empty()
    if id == PRESET_ID_NEW:
        return _settings() != null
    if id == PRESET_ID_SAVE:
        return not String(preset_engine()).is_empty()
    return true


## The bar's preset group in the tree *node* stands in, or null when *node* is
## out of the tree or the tree holds no bar.
##
## The one place that knows the group is the bar's and what it is called. The
## two presets dockers and the capture doors ask here rather than each walking
## the tree to `ToolOptionsBar` and taking its member, four copies of one lookup
## naming a class of another package to reach a class of this one. A node
## rather than a tree, so a docker asks with itself and a static with the root.
static func in_tree(node: Node) -> ToolOptionsPresets:
    if node == null or not node.is_inside_tree():
        return null
    return node.get_tree().root.find_child("PresetBox", true, false) as ToolOptionsPresets


## Runs *importer* against this group's store and settings, then lists what
## arrived: the one door a module's `preset_import` role takes into the presets.
## *importer* is called with the store and the settings resource, which may be
## null, and answers the importer's result dictionaries, each carrying the
## `name` it stored under. The last name stored is selected and announced, as
## the docker's Import button has always done.
##
## A module never names this class, which sits behind no door, so it asks
## `SaPresetsInHand`, which this group attaches to while it is in the tree.
func import_presets_through(importer: Callable) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    results.assign(importer.call(preset_store, _settings()))
    var last := ""
    for result: Dictionary in results:
        if not String(result.get("name", "")).is_empty():
            last = String(result["name"])
    refresh(last)
    if not last.is_empty():
        EventBus.preset_store_changed.emit(last, true)
    return results


## The Brush Presets docker, or null in a host that has none.
##
## **Found once and held**. A tool switch asks for it three
## times, and the docker's own handler asks `in_tree` for this group three
## more, each of them otherwise a search of the whole tree. The docker is held from the first
## search that finds it and forgotten when it leaves the tree, so a docker
## rebuilt by a layout reset is found again. A search that finds none holds
## nothing, since a docker can arrive after the bar.
func _presets_docker() -> BrushPresetsDocker:
    if not is_inside_tree():
        return null
    if is_instance_valid(_docker) and _docker.is_inside_tree():
        return _docker
    _docker = get_tree().root.find_child(SaDockerIds.BRUSH_PRESETS, true, false) as BrushPresetsDocker
    if _docker != null and not _docker.tree_exiting.is_connected(_forget_docker):
        _docker.tree_exiting.connect(_forget_docker)
    if _docker != null and not _docker.visibility_changed.is_connected(_sync_pressed):
        _docker.visibility_changed.connect(_sync_pressed)
    return _docker


func _forget_docker() -> void:
    _docker = null
    _sync_pressed()


## Presses the button exactly while the docker is open. Every door, the button,
## the Window menu, the chord and the docker's own close, ends in its
## `visibility_changed`, and `sync_menu` finds the docker on the first refresh.
func _sync_pressed() -> void:
    if preset_menu == null:
        return
    var open := is_instance_valid(_docker) and _docker.is_inside_tree() and _docker.visible
    preset_menu.set_pressed_no_signal(open)


## Sizes the button to its label up to `PRESET_CAP`. `clip_text` is on, so the
## button asks for no width of its own and this is the whole of its minimum.
func _fit_menu() -> void:
    var font := preset_menu.get_theme_font(&"font")
    var wide := preset_menu.get_theme_stylebox(&"normal").get_minimum_size().x
    var points := preset_menu.get_theme_font_size(&"font_size")
    wide += font.get_string_size(preset_menu.text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x if font != null else 0.0
    var tall := DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    preset_menu.custom_minimum_size = Vector2(minf(ceilf(wide) + 1.0, DockerUtils.px(PRESET_CAP)), tall)


## The button's tooltip: the preset, and what a press does.
func _menu_tip(preset_name: String) -> String:
    if preset_name.is_empty():
        return tr("No preset loaded. Shows or hides Brush Presets, where presets are picked, saved and deleted.")
    return tr("%s. Shows or hides Brush Presets.") % preset_name


## Rebuilds the popup from disk and shows *select_name*, falling back to the
## placeholder when that preset is not there, which is what a delete leaves.
## The popup, top to bottom: the tag filter, the presets that pass it, then
## Save and Delete.
##
## The tag row is Krita's answer to sorting: a preset carries
## any number of tags in its own file, and the row filters the list rather than
## grouping it, because a brush belongs to more than one group. It is not drawn
## at all while nothing is tagged, so a painter who never tags a preset never
## sees a filter that can only say All.
func refresh(select_name: String = "") -> void:
    if preset_menu == null or scan_held:
        return
    # The three shipped presets are written on the first refresh that has a
    # settings resource to copy them from, rather than in `_ready`. `_ready` runs
    # before `main.gd` binds the tool machine and before the modules that
    # provide the brush load, so it would ask a null machine and install
    # nothing, and a fresh profile would open on "No presets saved yet". A
    # refresh after the first costs no file read at all: the store
    # keeps what each bundle has offered this profile, and the install writes
    # only a recipe that is in neither that record nor the directory.
    #
    # The recipes come through the `shipped_presets` role: they are the stamp
    # brush's own field paths, so they live in the module that owns them, and a
    # build with no stamp brush installs nothing and says nothing rather than
    # writing presets nothing can paint.
    #
    # Then every engine's shelf the tool paints with, as `_shelves` says, and
    # the modules' bundles after them.
    _install_shelves()
    preset_rows.clear()
    _tag_rows.clear()

    for tag: String in preset_store.all_tags():
        _tag_rows.append(tag)
    if not _tag_rows.has(selected_tag):
        selected_tag = ""
    for stored_name: String in preset_store.names_tagged(selected_tag):
        if SaBrushPresetBundles.loaded(preset_store, stored_name):
            preset_rows.append(stored_name)

    # The rows a painter sees are the chooser's cells, and the list above them
    # is what every other caller reads: `preset_names`, the capture step and the
    # tag filter all ask this file rather than a control, so the grid being the
    # docker's changes nothing here.
    #
    # `follow_tag` rather than `capture_tag`, because this runs on every tool
    # switch and the grid it would rebuild is the one the docker has just built
    # for the same switch. It rebuilds when the tag or the list
    # moved and not otherwise.
    var docker := _presets_docker()
    if docker != null and docker.chooser != null:
        docker.chooser.follow_tag(selected_tag)

    # A filter hides rows, it does not unload what is loaded, so the selection
    # survives a tag that does not list it.
    var wanted := select_name if not select_name.is_empty() else selected_preset
    selected_preset = wanted if preset_store.has_preset(wanted) else ""
    sync_menu()


## Keeps `refresh` from reading the store until `scan` runs. Called by the boot
## before the bar is bound to a tool, and by nothing else.
func hold_scan() -> void:
    scan_held = true


## Reads the store a held boot kept unread, once, and tells the docker waiting on
## it. A group that was never held has nothing to release and does nothing.
##
## The loaded preset is kept, because a door or a chord may have applied one
## while the list was held, and the list is what was missing, not the choice.
func scan() -> void:
    if not scan_held:
        return
    scan_held = false
    refresh(selected_preset)
    pick_first_brush(SaSettings.brush_slots)
    SaBootMarks.mark(&"presets_scanned")
    scanned.emit()


## Calls `scan` once `prepare_scan` has done its reads, a slice in this process
## frame and each one after. What `MainDockers` calls in place of `scan` itself,
## a frame after the first frame after Ready. A bar outside the tree has no
## frames to slice and scans at once.
func scan_in_slices() -> void:
    if not scan_held or not is_inside_tree():
        scan()
        return
    if not get_tree().process_frame.is_connected(_scan_a_slice):
        get_tree().process_frame.connect(_scan_a_slice)
    _scan_a_slice()


## One frame's share of `scan_in_slices`: a slice of the reads, the first brush,
## then the scan. A scan someone else ran meanwhile ends it too. The brush is a
## large share of the scan's frame, so it has a frame of its own, the one
## before the scan, which keeps a load made while held. The docker the scan
## binds builds its grid in shares.
func _scan_a_slice() -> void:
    if scan_held and not _read_ahead:
        _read_ahead = prepare_scan(PREPARE_SLICE_USEC)
        return
    if scan_held and not _picked_ahead:
        _picked_ahead = true
        pick_first_brush(SaSettings.brush_slots)
        return
    get_tree().process_frame.disconnect(_scan_a_slice)
    var docker := _presets_docker()
    if docker != null and docker.chooser != null:
        docker.chooser.in_shares = true
    scan()


## The scan's reads done ahead of it while it is held, about *budget_usec* of
## them a call: the shelves `refresh` writes, the modules' bundles, and every
## preset's facts, so the scan finds them written and read. Answers whether
## nothing is left, and `MainDockers` calls `scan` once it does.
##
## Run in one frame, the scan would hold the window for a good part of a
## second, most of it reading every preset and, on a fresh profile, writing the
## shipped presets and then reading their tags. The store reads a preset once,
## and here, a few a frame.
func prepare_scan(budget_usec: int) -> bool:
    var deadline := Time.get_ticks_usec() + budget_usec
    if not _shelves_written:
        if not _install_shelves(deadline):
            return false
        _shelves_written = true
    return preset_store.learn_listed(deadline)


## Writes every shelf `_shelves` names and then the modules' bundles, and
## answers whether all of it is written. A *deadline_usec* stops it after the
## first preset written past it, as `SaPresetStore.install_shipped` says, and
## the next call writes on from there.
func _install_shelves(deadline_usec: int = -1) -> bool:
    var written := 0
    for shelf: Array in _shelves():
        written += preset_store.install_shipped(shelf[0], _role_script(shelf[1]), deadline_usec)
    # A shelf stops early only after a write past the deadline, so a pass that
    # wrote nothing or ended in time has every shelf written.
    if deadline_usec >= 0 and written > 0 and Time.get_ticks_usec() > deadline_usec:
        return false
    _install_module_bundles()
    return true


## Every shelf of shipped presets `refresh` writes, each a template and the role
## of its recipes.
##
## The tool's own shelf, then every engine's shelf the tool paints with, onto
## that engine's own settings, so the Brush's shelf holds the noise presets
## before a painter has ever held the noise engine. A host that names no engines
## has the shown tool's shelf alone.
func _shelves() -> Array:
    var shelves: Array = [[_settings(), &"shipped_presets"]]
    var engines := _engines()
    if engines.is_empty():
        shelves.append([_settings(), StringName("shipped_presets_%s" % preset_engine())])
    for engine: StringName in engines:
        var painter: Variant = engines[engine]
        var template: Resource = painter.get("settings") if painter is Object and "settings" in painter else null
        shelves.append([template, StringName("shipped_presets_%s" % engine)])
    return shelves


## Loads the first of *slots* the store has and the tool takes, when nothing is
## loaded yet, and answers the name it loaded or "".
##
## Without it a session opens on "Unsaved brush" with "No preset" and no cell
## marked, because a tool's settings are not kept between sessions and nothing
## loaded a preset until the painter did. The brush slots are the list asked,
## rather than a name of its own, because they are already the painter's ten
## brushes in the order they chose: a fresh profile's slot 1 is a shipped
## preset, and a painter who put another in slot 1 starts on that one.
##
## Through [method load_preset], the pick path a cell, a chord and the bar
## take, so the docker marks the cell and the brush editor has a name. A slot
## that does not load, gone or of an engine the tool refuses, is passed over
## for the next one. A slot list with nothing loadable leaves the session as it
## was.
##
## Public because the boot's `scan` is its one caller and a suite asks it
## without a boot.
func pick_first_brush(slots: Array) -> String:
    if not selected_preset.is_empty():
        return ""
    for raw: Variant in slots:
        var preset_name := str(raw)
        # A missing preset's load answers false without a word, and one the tool
        # refuses says why in the canvas corner, which is true of a slot too.
        if not preset_name.is_empty() and load_preset(preset_name):
            return preset_name
    return ""


## The tags the popup is offering, in the order it offers them.
func preset_tags() -> Array[String]:
    return _tag_rows.duplicate()


## Filters the list to *tag*, or to everything when it is empty.
##
## Public because the popup is a Window and an injected click does not route
## into one, which is the same reason `load_preset` is.
##
## A tag nothing carries leaves the filter where it was rather than clearing it.
## `refresh` above still clears one whose presets have all gone, which is a
## different question and stays. The warning is the chooser's, in `capture_tag`,
## because it knows the tags there are and this is also the path a painter's own
## tag row takes, where every row exists by construction.
func filter_by_tag(tag: String) -> void:
    if not tag.is_empty() and not _tag_rows.has(tag):
        return
    selected_tag = tag
    refresh(selected_preset)


## Mirrors the loaded preset onto the button's tooltip and onto the row the
## popup opens highlighted, and greys Delete out when there is nothing to
## delete. The label itself never moves, see [constant PRESET_LABEL].
func sync_menu() -> void:
    if preset_menu == null:
        return
    preset_menu.text = tr(PRESET_LABEL)
    preset_menu.tooltip_text = _menu_tip(selected_preset)
    _fit_menu()
    # Delete is dead with nothing loaded, and the button is the docker's, so the
    # docker is told rather than a button held here.
    var docker := _presets_docker()
    _sync_pressed()
    if docker != null:
        docker.sync_actions()


## Every preset the popup is offering, in the order it offers them.
func preset_names() -> Array[String]:
    return preset_rows.duplicate()


## One popup, two kinds of row: a preset to load, and the two actions under it.
func _on_preset_menu_id(id: int) -> void:
    if id == PRESET_ID_SAVE:
        _open_preset_name_field()
    elif id == PRESET_ID_DELETE:
        delete_loaded_preset()
    elif id == PRESET_ID_NEW:
        new_preset()
    elif id == PRESET_ID_TAG_ALL:
        filter_by_tag("")
    elif id >= PRESET_ID_TAG_BASE and id - PRESET_ID_TAG_BASE < _tag_rows.size():
        filter_by_tag(_tag_rows[id - PRESET_ID_TAG_BASE])
    elif id >= 0 and id < preset_rows.size():
        load_preset(preset_rows[id])


## Loading a preset copies onto the live settings object rather than replacing
## it. The base module hands one instance to every surface, so a replacement
## would leave the info docker's scratchpad pointing at the old one.
##
## Public because `harness/sa_capture.gd` drives it: the list lives in a MenuButton's
## popup, which is a Window, and an injected click does not route into one.
##
## A preset of another engine the shown tool also paints with switches to that
## engine first, so a noise preset picked with the Brush in hand paints the next
## stroke through the noise engine and a stamp preset through the stamp.
##
## **A tool that takes no presets is left for the tool that does.** The lasso
## shows the brush's settings on the bar, so `preset_engine` reads their engine
## and no switch was asked for: the painter picked Inked Pen and the next press
## started a selection. A pick under such a tool asks for the switch whatever the
## bar reads, and the surface answers whether any tool takes the engine.
func load_preset(stored_name: String) -> bool:
    var engine := preset_store.engine_for(stored_name)
    if engine_switch.is_valid() and _asks_for_switch(engine):
        engine_switch.call(engine)
    var settings := _settings()
    var blend_before: Variant = settings.get("blend_mode") if settings != null else null
    if settings == null or not preset_store.apply_preset(stored_name, settings):
        return false
    blend_memory.loaded(settings, blend_before, descriptor_source, preset_store.erases(stored_name))
    _hold(stored_name)
    sync_menu()
    if on_applied.is_valid():
        on_applied.call()
    # The History docker's one hook. Announced after the load rather than
    # before, so nothing records a preset that failed to apply.
    EventBus.preset_loaded.emit(stored_name)
    return true


## Loads the preset that was in the hand before this one and answers whether it
## did, so a second call comes back to where the first started.
##
## Nothing remembered, or the preset remembered being the one in hand, does
## nothing and says nothing. A remembered preset deleted since fails in
## `load_preset`, which keeps the memory as it was.
func load_previous_preset() -> bool:
    if previous_preset.is_empty() or previous_preset == selected_preset:
        return false
    return load_preset(previous_preset)


## Puts *stored_name* in the hand, "" for a brush of no preset, and remembers the
## preset it replaces.
##
## The preset in hand loaded again remembers nothing, or a slot pressed twice
## would leave nothing to go back to. Nor does a hand that held no preset, so a
## painter who loaded A, looked at New's defaults and loaded B goes back to A.
func _hold(stored_name: String) -> void:
    if stored_name == selected_preset:
        return
    if not selected_preset.is_empty():
        previous_preset = selected_preset
    selected_preset = stored_name


## Registers Switch to the previous preset on `/`, Krita's chord for its own
## Switch to Previous Preset, in the brush's category beside the ten slots.
##
## Here rather than in `ui/shortcuts/brush_keys/sa_brush_slot_commands.gd` beside the
## slots, because that folder stands at its line budget and the swap the
## command runs is this class's. The Reference docker registers its Show one
## picture alone from its own class the same way.
##
## `brush_` and not `preset_`, because the Keyboard Shortcuts page files a row
## under the section its prefix names, and with no Preset section the row would
## not be on the page at all.
static func register_previous(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(&"brush_preset_previous", "Switch to the previous preset", _previous_in_tree)
    command.category = &"brush"
    command.sentence = "Load the brush preset in use before this one. A second press comes back to this one."
    ctx.register_command(command)


## The command's handler. It declines the key when there is nothing to go back
## to, the way Undo with an empty history does, so `/` is not swallowed.
static func _previous_in_tree() -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    var presets := in_tree(tree.root) if tree != null else null
    return presets != null and presets.load_previous_preset()


## Writes the settings in front of the user under *preset_name* and shows it as
## loaded. Returns the name it was stored under, empty when nothing was written.
##
## **Nothing is written for a tool that takes no presets**. The settings in front
## of the painter are then not a brush at all, and a save of them would leave
## in the preset folder a file no tool can load, a cell beside the stamp ones
## that nothing paints with.
func save_current_as_preset(preset_name: String) -> String:
    var settings := _settings()
    if settings == null or String(preset_engine()).is_empty():
        return ""
    # A copy under a new name says what the loaded preset said, as the editor's Save As does.
    var copied := not selected_preset.is_empty() and not preset_store.has_preset(preset_name)
    var said := {SaPresetStore.DESCRIPTION_META: preset_store.about_for(selected_preset)} if copied else {}
    var stored := preset_store.save_preset(preset_name, settings, PackedStringArray(), said)
    if stored.is_empty():
        return ""
    refresh(stored)
    # Announced after the write, the way a load is announced after it applies, so
    # nothing redraws a grid around a preset that was never stored.
    EventBus.preset_store_changed.emit(stored, true)
    return stored


## Deletes the stored preset and leaves the brush exactly as it is. Throwing away
## the recipe is not the same as undoing the meal. The preset's star goes with it.
func delete_loaded_preset() -> void:
    if selected_preset.is_empty():
        return
    var removed := selected_preset
    preset_store.delete_preset(removed)
    SaSettings.drop_preset_favorite(removed)
    refresh()
    EventBus.preset_store_changed.emit(removed, false)


## Whether a load of a preset of *engine* asks the surface to change tool first.
func _asks_for_switch(engine: StringName) -> bool:
    if takes_no_presets():
        return not String(engine).is_empty()
    return preset_engines().has(engine) and engine != preset_engine()


## Whether the tool the surface shows has a descriptor that declares no preset
## engine, which is a tool that takes no presets: the lasso, the eyedropper, the
## gradient. False for a surface with no descriptor behind it, the brush editor's
## and the info docker's, where the settings in hand are the only word there is.
func takes_no_presets() -> bool:
    var shown: Variant = descriptor_source.call() if descriptor_source.is_valid() else null
    var descriptor := shown as SaToolDescriptor
    return descriptor != null and String(descriptor.preset_engine).is_empty()


func _settings() -> Resource:
    return settings_source.call() as Resource if settings_source.is_valid() else null


## What [member engines_source] answers, or an empty table without one.
func _engines() -> Dictionary:
    var answered: Variant = engines_source.call() if engines_source.is_valid() else null
    return answered if answered is Dictionary else {}


## The Krita bundles the loaded modules ship as files, imported after the
## recipes and once a session.
##
## Asked of the bar rather than folded into `SaPresetStore.install_shipped`,
## because the bundles are a second thing the bar installs rather than a second
## pass of the recipes. The session's answer is kept only once there was a
## settings resource and the role to ask, so a refresh before the modules loaded
## tries again.
func _install_module_bundles() -> void:
    if _bundles_offered:
        return
    var template := _settings()
    var bundles := _role_script(&"shipped_bundles")
    if template == null or bundles == null:
        return
    _bundles_offered = true
    bundles.call("install_from_modules", preset_store, template)


## The script a module registered under *role*, or null in a build with no
## module registering it: the recipes the brush ships and the bundle files the
## modules ship.
##
## A role and not a `preload("res://modules/...")`, which is a parse error in a
## skeleton that boots with `modules/` empty. The same door the capture steps
## take for `kpp_capture` and `preset_import`, and the same walk to a main scene
## that `SaGeneratedLayer` makes for a layer type.
func _role_script(role: StringName) -> Script:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.registries
    return registries.roles.script_for(role) if registries != null else null


## Swaps the name field in where the button was, prefilled with the loaded
## preset's name so saving over one is a click and a Return.
func _open_preset_name_field() -> void:
    if preset_name_edit == null or preset_menu == null:
        return
    preset_name_edit.text = selected_preset
    preset_name_edit.custom_minimum_size.x = maxf(DockerUtils.px(PRESET_WIDTH), preset_menu.custom_minimum_size.x)
    preset_name_edit.visible = true
    preset_menu.visible = false
    if preset_name_edit.is_inside_tree():
        preset_name_edit.grab_focus()
        preset_name_edit.select_all()


func _on_preset_name_submitted(preset_name: String) -> void:
    _close_preset_name_field()
    SaPresetReplace.ask(self, preset_store, preset_name, selected_preset, save_current_as_preset)


## Clicking away is the cancel. There is nothing to confirm and nothing lost, so
## a field left open over the bar would be worse than one that simply closes.
func _on_preset_name_abandoned() -> void:
    _close_preset_name_field()


## Escape closes the name field and nothing else.
##
## Closing is what leaving the field means, so all this adds is
## `accept_event`: without it the key goes on to
## `ShortcutRouter._release_text_focus`, which releases the focus and closes the
## docker the field sits in, or to `sa_dialog_window.gd`'s `_input`, which hides
## the window. One press for the field, the next for whatever is behind it.
func _on_preset_name_gui_input(event: InputEvent) -> void:
    if not SaShortcutKeys.is_escape(event):
        return
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo():
        return
    _close_preset_name_field()
    preset_name_edit.release_focus()
    preset_name_edit.accept_event()


func _close_preset_name_field() -> void:
    if preset_name_edit != null:
        preset_name_edit.visible = false
    if preset_menu != null:
        preset_menu.visible = true


## Types a preset name: it opens the field of the tool options and types into it
## with `{"preset_name": {"type": "Nameless"}}`, sends the key with `{"escape":
## true}`, presses Return in it with `"submit": true`, and says what happened
## with `{"read": true}`.
##
## The slider's twin, and here for the same reason: the requirement names two
## controls, the brush editor's value field and this one, and neither can be
## reached by an injected click or an injected key. `FactorSlider.capture_edit`
## carries the paragraph about what the substitution is and what it is not.
static func capture_name_field(tree: SceneTree, raw: Variant) -> String:
    var spec: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
    if tree == null or tree.root == null:
        return "SaCapture: no tree to reach the preset name field in"
    var presets := in_tree(tree.root)
    if presets == null or presets.preset_name_edit == null:
        return "SaCapture: no preset name field on the bar"

    if bool(spec.get("read", false)):
        var window := presets.get_window()
        return (
            "SaCapture: preset_name naming=%s focused=%s text='%s' presets=%d window='%s' shown=%s"
            % [
                str(presets.preset_name_edit.visible),
                str(presets.preset_name_edit.has_focus()),
                presets.preset_name_edit.text,
                presets.preset_names().size(),
                window.title if window != null else "<none>",
                str(window.visible) if window != null else "<none>",
            ]
        )

    if bool(spec.get("escape", false)):
        var key := InputEventKey.new()
        key.keycode = KEY_ESCAPE
        key.physical_keycode = KEY_ESCAPE
        key.pressed = true
        presets._on_preset_name_gui_input(key)
        return "SaCapture: preset_name escaped, naming=%s" % str(presets.preset_name_edit.visible)

    presets._open_preset_name_field()
    if spec.has("type"):
        presets.preset_name_edit.text = String(spec["type"])
    if bool(spec.get("submit", false)):
        presets.preset_name_edit.text_submitted.emit(presets.preset_name_edit.text)
    return "SaCapture: preset_name open, text='%s'" % presets.preset_name_edit.text
