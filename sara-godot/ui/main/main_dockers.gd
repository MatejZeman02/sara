## Every docker Main owns: registering the built-in twelve, building a Window
## for each registered one, the docker rows the Window menu opens with, where
## they sit, the store that remembers it and the focus mode that hides them.
##
## Built with the UI registry, which is the one list every docker is on, and it
## owns everything else it works on: the `DockerLayoutStore`, the
## `MainFocusTab` that Tab goes through, the Window menu's popup once the bar
## exists, and the settle clock that says when a layout save is trusted,
## because a cut owns its state rather than reaching back to `Main` for it. The windows are children of this node, and
## `find_child` by id reaches them from anywhere above, which is how every
## driver and page finds them.
##
## A `Node` rather than a `RefCounted`, for the reason `MainDialogs` is one:
## these methods are connected to `EventBus`, to each docker's `focus_exited`
## and to the host viewport, and Godot drops a connection when its target
## `Object` is freed. A `RefCounted` target would instead be kept alive by the
## connection and outlive the `Main` it points at.
class_name MainDockers
extends Node

## How long after startup before a layout save is trusted. Compositors report
## placeholder geometry while windows are still being mapped.
const LAYOUT_SETTLE_MS: int = 1500

## The Focus Mode row's id and the chord it shows, `MainFocusTab`'s, named here
## so a package outside reaches them through this node rather than the inner
## file.
const FOCUS_MODE_ROW := MainFocusTab.ROW
const FOCUS_MODE_KEY := MainFocusTab.KEY

## The kinds the Window menu groups the dockers by, each its name, whose
## words [method _kind_words] gives, and the built-in dockers under it. The last takes every docker no kind
## names, so a module's docker always has a row.
const KINDS: Array = [
    [
        "Painting",
        [SaDockerIds.TOOLBOX, SaDockerIds.TOOL_OPTIONS, SaDockerIds.BRUSH_PRESETS, SaDockerIds.HISTORY, SaDockerIds.PALETTE]
    ],
    ["Colour", [SaDockerIds.COLOR, SaDockerIds.GRAPH]],
    [
        "Picture",
        [
            SaDockerIds.LAYERS,
            SaDockerIds.MINIMAP,
            SaDockerIds.INFO,
            SaDockerIds.UNDO,
            SaDockerIds.REFERENCE,
            SaDockerIds.FILTERS,
            SaDockerIds.RECORDER,
        ]
    ],
    ["Other", []],
]

## The Window menu's row of the first kind's submenu, and the rest after it, in
## the six hundreds `SaWindowMenu` numbers its own rows in.
const FIRST_KIND_ROW := 610

## The dockers a fresh profile opens, by id, in the order
## `docker_layout_default.cfg` lists them, which is the order the Window menu
## lists them first. Read once, the file being inside the PCK where nothing
## writes to it.
static var _opened_by_default: Array[String] = []

## The registry every docker is on, the skeleton's twelve and a module's alike.
var ui: SaUIRegistry

## Where the dockers sit, and the named layouts. A child of this node under its
## own name, which is how the Workspace page and the Tool Options docker find
## it, and handed in only by a suite that wants a store that writes no file.
var layout_store: DockerLayoutStore

## Tab and the Focus Mode row, whose `SaFocusMode` is a child of this node.
var focus_tab: MainFocusTab = null

## The Layouts section under the docker rows.
var layout_rows: MainLayoutRows = null

## The Window menu's popup, which holds the docker rows, the layout store's
## ticks and the layouts section. Null until the bar exists.
var dockers_menu: SaChoicePopup = null

## The bar, once [method bind_bar] has run: its Window menu fills the popup
## above, and the default docker placement sits below its height.
var _bar: TopMenuBar = null

## The docker most recently raised, which wins a press two dockers overlap under.
## Remembered from the two events that put a docker in front, taking focus and
## being opened. A script can read the stacking order,
## `Viewport.get_embedded_subwindows` is the embedder's own array and
## `DockerFocus` reads it, and this record stands beside it.
var _front_docker: Window = null

## Moves the keyboard to whatever the pointer is over, and passes over a
## summoned docker. Built in `_init`, after the summon it asks.
var _docker_focus: DockerFocus = null

## The docker summoned under the pointer by its chord and sent back when the
## pointer leaves it, on the layout store's borrow.
var summon: DockerSummon = null

## The settle clock. Set once by [method boot_finished], read by the layout
## store's gate to tell a settled window from one still being sized.
var _ready_done: bool = false
var _startup_ticks: int = 0


func _init(registry: SaUIRegistry, store: DockerLayoutStore = null) -> void:
    name = "MainDockers"
    ui = registry
    layout_store = store
    if layout_store == null:
        layout_store = DockerLayoutStore.new()
        @warning_ignore("static_called_on_instance")
        layout_store.path = SaSettings.get_settings_dir().path_join("docker_layout.cfg")
    layout_store.name = "DockerLayoutStore"
    layout_store.dockers_provider = get_docker_config
    layout_store.save_allowed = layout_save_allowed
    layout_store.top_inset = below_bar
    add_child(layout_store)
    summon = DockerSummon.new(layout_store)
    add_child(summon)
    _docker_focus = DockerFocus.new(summon.is_summoned)
    add_child(_docker_focus)
    layout_rows = MainLayoutRows.new(layout_store)
    focus_tab = MainFocusTab.new(layout_store, get_docker_config, _tick_docker_row, self)
    add_child(focus_tab.focus_mode)
    # A module may register a docker after startup, and its window is built
    # here the moment the registry says so.
    if not ui.changed.is_connected(_on_ui_registry_changed):
        ui.changed.connect(_on_ui_registry_changed)


## The bar exists, so the Window menu's popup is known. By the bar's own table
## rather than by a node search: the button on the bar is called "Window" and
## the list behind it is "WindowMenu", so a search for the name found the
## button. The dockers' rows are in that list and this is still the popup the
## layout store ticks and the rows are pressed on.
func bind_bar(bar: TopMenuBar) -> void:
    _bar = bar
    dockers_menu = bar.menus.get("Window") if bar != null else null
    assert(dockers_menu is SaChoicePopup, "Expected the Window menu to be an SaChoicePopup")


## The area dockers are placed within: the host viewport for embedded
## subwindows, the OS window for real ones.
func _docker_host_size() -> Vector2i:
    if SaSettings.embed_subwindows and is_inside_tree():
        return Vector2i(get_viewport().get_visible_rect().size)
    return DisplayServer.window_get_size()


## A logical offset in the units `window` measures its geometry in.
func _docker_units(window: Window, logical: Vector2i) -> Vector2i:
    return SaUI.window_size_for(window, logical)


## The skeleton's own dockers, registered through the same door a module uses.
## The list and the slicing live in `SaBuiltinDockers`, and this is the call the
## boot and the suites already make. True once every built-in is registered.
func register_builtin_dockers(slice_usec: int = 0) -> bool:
    return SaBuiltinDockers.register(ui, slice_usec)


## Builds the Window for every registered docker that does not have one yet.
## Runs at startup, again after modules load, and on every later registration.
func instantiate_registered_dockers() -> void:
    for entry: Dictionary in ui.list_dockers():
        var existing := entry["node"] as Window
        if existing != null and is_instance_valid(existing):
            continue
        var win := find_child(String(entry["id"]), true, false) as Window
        if win == null:
            win = (entry["factory"] as Callable).call() as Window
            if win == null:
                push_error("[Sara] docker '%s': factory did not return a Window." % entry["id"])
                continue
            win.name = String(entry["id"])
            add_child(win)
        win.unique_name_in_owner = true
        win.owner = self
        # A side cover, so Fit and Centre leave the docker its room and the
        # painting lands between the columns. A module's docker joins the way
        # a built-in does, because both arrive here.
        win.add_to_group(SaCanvasView.SIDE_COVER_GROUP)
        SaDockerEdges.attach(win)
        SaDockerOpacity.attach(win, layout_store)
        ui.set_docker_node(entry["id"], win)
        _ensure_docker_settings_line(entry, win)


## A registered docker gets a line on Preferences > Layouts and dockers. The
## built-ins already have richer const entries in SaSettings, which win, so
## this only does anything for a docker SaSettings has never heard of. The line
## lasts as long as this node, whose windows it describes.
func _ensure_docker_settings_line(entry: Dictionary, win: Window) -> void:
    var category := String(entry["id"])
    if win.has_method("settings_category"):
        category = win.settings_category()
    var elements: Array = ["Drag Handle", "Resizer"]
    if win.has_method("layout_elements"):
        elements = win.layout_elements()
    SaSettings.register_layout_category(category, String(entry["title"]), elements, self)


## The Window a registered docker is, by its id, or null before it is built.
func registered_docker_node(docker_id: StringName) -> Window:
    return ui.get_docker_entry(docker_id).get("node") as Window


func _on_ui_registry_changed() -> void:
    instantiate_registered_dockers()
    if _ready_done and dockers_menu != null:
        setup_dockers_menu()


## Configuration list for all dockers in the app, read from the UI registry.
func get_docker_config() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry: Dictionary in ui.list_dockers():
        var node := entry["node"] as Window
        if node == null or not is_instance_valid(node):
            continue
        var config := {"id": String(entry["id"]), "name": entry["title"], "node": node, "shortcut": String(entry["shortcut"])}
        config["sentence"] = String(entry.get("sentence", ""))
        config["module"] = String(entry.get("module", ""))
        config.merge({"side": String(entry.get("side", "")), "order": int(entry.get("order", 0))})
        out.append(config)
    return out


## The order the Window menu lists *dockers* in, the list [method
## get_docker_config] answers: the ones a fresh profile opens, in the order the
## default layout's file lists them, and then the rest as they registered.
## Registration order alone would put Info, Recorder and Minimap between Colour
## Picker and Tool Options.
##
## Indices into *dockers* rather than the configs, because a row is keyed by its
## docker's index there and a press, the layout store's tick and a scenario's
## `menu_item` all find the docker by that number. The order moves the rows and
## leaves every key where it was.
static func menu_order(dockers: Array) -> Array[int]:
    var ordered: Array[int] = []
    for docker_id: String in _default_opened():
        for i in dockers.size():
            if String(dockers[i]["id"]) == docker_id:
                ordered.append(i)
    for i in dockers.size():
        if not ordered.has(i):
            ordered.append(i)
    return ordered


static func _default_opened() -> Array[String]:
    if _opened_by_default.is_empty():
        var cfg := ConfigFile.new()
        if cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS) == OK:
            for section: String in cfg.get_sections():
                if bool(cfg.get_value(section, "visible", false)):
                    _opened_by_default.append(section)
    return _opened_by_default


## Rebuilds the Window menu, whose docker half this node owns.
##
## **The rows moved into the Window menu and this now rebuilds that one**.
## `dockers_menu` is the Window popup, so everything below that reads it (the
## layout store's ticks, a row press, the layouts section) is unchanged, and the
## popup is rebuilt through the class that owns it rather than cleared here: the
## three window rows share the list now, and a clear from this end would wipe
## them.
##
## Answering a call with no menu is still part of it: the signal reaches a
## `MainDockers` whose `Main` is still building, and a caller that has to check
## first is a caller a signal cannot be.
func setup_dockers_menu() -> void:
    if dockers_menu == null:
        return
    var filler: SaMenu = _bar.menu("Window") if _bar != null else null
    if filler != null:
        filler.populate()
        return
    # A bar with nothing behind the Window popup, which is the scene-bound case
    # `_ensure_window_popup` exists for. There the rows are all the list holds.
    append_menu_rows(dockers_menu)


## The docker rows and the Layouts section, appended into a popup the Window
## menu's own class has just cleared.
##
## **A row draws its chord as words and holds no `Shortcut`**, because an
## engine row holds a frozen copy of the input map and dispatches it before any
## door Sara owns. A row of `SaChoicePopup` fires nothing, so the copy cannot go
## stale, and the rebuild the bar does before every open is what keeps the
## words current. A shortcut row would also take its text from the resource's
## name, which has none, so every docker would read as a bare chord.
##
## One list, with no submenu, for a bar with no Window menu behind its popup.
## The Window menu itself calls [method append_grouped_rows], before every open,
## so the docker half is built there rather than at startup. Every line of
## either is safe to run twice.
##
## **Focus Mode is the first row**, because it is what Tab does to every docker
## under it, and a painter who never pressed Tab had no row to find it by.
## `MainFocusTab` draws it, which owns the mode the row turns.
func append_menu_rows(menu: SaChoicePopup) -> void:
    if menu == null:
        return
    _connect_menu_doors(menu)
    focus_tab.add_row(menu)

    var dockers := get_docker_config()
    for i: int in menu_order(dockers):
        _add_docker_row(menu, dockers, i)
    layout_rows.add_to(menu)


## The Window menu's docker rows, a submenu for each kind of docker, then the
## Layouts section, appended into the menu its own class has just cleared.
##
## **By kind, so the Window menu fits a screen.** One row per docker made the
## menu taller than a laptop's screen once a module added a few. A submenu
## for the dockers that paint, one for colour, one for the picture and one for
## every other docker, a module's among them, keeps it short, and every row
## keeps its `docker_<index>` key, its tick and its chord. A kind with no
## docker draws no row, which [method SaMenu.end_group] sees to.
func append_grouped_rows(menu: SaMenu) -> void:
    if menu == null or menu.popup == null:
        return
    _connect_menu_doors(menu.popup)
    focus_tab.add_row(menu.popup)
    var dockers := get_docker_config()
    var order := menu_order(dockers)
    for at: int in KINDS.size():
        var words := _kind_words(at)
        menu.begin_group(FIRST_KIND_ROW + at, words[0], words[1])
        _connect_menu_doors(menu.popup)
        for i: int in order:
            if _kind_of(String(dockers[i]["id"])) == at:
                _add_docker_row(menu.popup, dockers, i)
        menu.end_group()
    layout_rows.add_to(menu.popup)


## The words of the kind at *at* in [constant KINDS] and the sentence on its
## row's hover, written out so the catalogue finds each.
func _kind_words(at: int) -> PackedStringArray:
    match at:
        0:
            return [tr("Painting"), tr("Show or hide the dockers you paint with.")]
        1:
            return [tr("Colour"), tr("Show or hide the dockers that pick paint and read its values.")]
        2:
            return [tr("Picture"), tr("Show or hide the dockers that read the picture and its history.")]
    return [tr("Other"), tr("Show or hide the dockers modules add, and any other.")]


## The place in [constant KINDS] of the docker *id*, the last for one no kind
## names, which is every module's docker.
static func _kind_of(id: String) -> int:
    for at: int in KINDS.size():
        if (KINDS[at][1] as Array).has(StringName(id)):
            return at
    return KINDS.size() - 1


## One docker's row on *menu*, ticked while the docker is open, and the
## docker's own signals wired once.
func _add_docker_row(menu: SaChoicePopup, dockers: Array[Dictionary], i: int) -> void:
    var config: Dictionary = dockers[i]
    var docker_node: Window = config["node"] as Window
    var chord_of := SaMenu.action_chord(StringName(config["shortcut"]))
    menu.add_row(_docker_key(i), SaDockerIds.display_name(config["name"]), true, docker_node.visible, "", chord_of)
    _say_on_hover(menu, _docker_key(i), tr(config["sentence"]))

    if not docker_node.close_requested.is_connected(_on_docker_closed):
        docker_node.close_requested.connect(_on_docker_closed.bind(i, docker_node))
    # The store owns the save, so a docker that loses the focus is wired to
    # it and not to a forwarder of this file.
    if not docker_node.focus_exited.is_connected(layout_store.save):
        docker_node.focus_exited.connect(layout_store.save)
    if not docker_node.focus_entered.is_connected(_on_docker_focused):
        docker_node.focus_entered.connect(_on_docker_focused.bind(docker_node))


## Everything a docker row needs that outlives one rebuild of the list: the two
## row presses, the docker windows' own signals, and the app's events that said
## the list has to be built again.
##
## Split out of the rows themselves because the rows are rebuilt before every
## open while these are once each, and `is_connected` guards them here the way it
## did when the two halves were one function.
func _connect_menu_doors(menu: SaChoicePopup) -> void:
    if not menu.chosen.is_connected(_on_docker_row_chosen):
        menu.chosen.connect(_on_docker_row_chosen)
    if not menu.marked.is_connected(_on_docker_row_marked):
        menu.marked.connect(_on_docker_row_marked)

    if not EventBus.docker_layout_changed.is_connected(_painter_changed_the_layout):
        EventBus.docker_layout_changed.connect(_painter_changed_the_layout)
    # The one door besides a docker window a painter changes a layout through,
    # the element pages, heard by their own word rather than every setting's.
    var elements: SaSettingsLayout = SaSettings._layout
    if not elements.profile_changed.is_connected(_painter_changed_the_layout):
        elements.profile_changed.connect(_painter_changed_the_layout)
    # The map moved, so the words a row draws have to be read again.
    if not EventBus.shortcuts_changed.is_connected(setup_dockers_menu):
        EventBus.shortcuts_changed.connect(setup_dockers_menu)
    # A layout saved, loaded or deleted anywhere, the Workspace page included,
    # which the bar never populates this menu for.
    if not layout_store.presets_changed.is_connected(setup_dockers_menu):
        layout_store.presets_changed.connect(setup_dockers_menu)
    # A resize, a scale change and a bar grown a row each move the room the
    # dockers have, and the store puts each back where the user left it, as far
    # as the new room allows. None of them forks.
    if not EventBus.ui_scale_changed.is_connected(_the_host_was_rescaled):
        EventBus.ui_scale_changed.connect(_the_host_was_rescaled)
    var host_viewport := get_viewport()
    if host_viewport != null and not host_viewport.size_changed.is_connected(layout_store.reflow_to_host):
        host_viewport.size_changed.connect(layout_store.reflow_to_host)
    if _bar != null and not _bar.resized.is_connected(layout_store.reflow_to_host):
        _bar.resized.connect(layout_store.reflow_to_host)
    # A right press over an embedded docker has to reach it, and the engine only
    # routes one to a docker it already considers focused.
    var host_window := get_window()
    if host_window != null and not host_window.window_input.is_connected(_focus_docker_under_press):
        host_window.window_input.connect(_focus_docker_under_press)
    _docker_focus.watch(host_window)


## Writes *sentence* as a row's tooltip, where `add_row` had put the row's own
## words as a placeholder. Every menu row keeps the one rule: it says what it
## does on hover, or nothing.
static func _say_on_hover(menu: SaChoicePopup, row_id: StringName, sentence: String) -> void:
    var button := menu.label_button(row_id)
    if button != null:
        button.tooltip_text = sentence


## The row id a docker's index is written as. A layout's row is `layout_` and
## its index, so one list holds both and a press tells them apart by prefix.
static func _docker_key(index: int) -> StringName:
    return StringName("docker_%d" % index)


## A press on a layout row's label, which loads the layout and closes the menu
## behind it. A docker row is not answered here: its label presses its box, so
## both halves of the row reach `_on_docker_row_marked`.
func _on_docker_row_chosen(row_id: StringName) -> void:
    if layout_rows.is_layout(row_id):
        dockers_menu.hide()
        layout_rows.load_at(row_id)


## A press on a docker row or on Focus Mode, on its box or on its label, which
## presses the box.
##
## The box flipped itself on the way here and is put back, because
## [method toggle_docker] reads the docker's own visibility and writes the tick
## from that, which is the only state that matters. Focus Mode's is
## `MainFocusTab`'s to write.
func _on_docker_row_marked(row_id: StringName, on: bool) -> void:
    var text := String(row_id)
    if not text.begins_with("docker_") and row_id != MainFocusTab.ROW:
        return
    var holder := SaMenu.list_holding(dockers_menu, row_id)
    var box := holder.check_box(row_id) if holder != null else null
    if box != null:
        box.set_pressed_no_signal(not on)
    SaQuickCommands.note_docker_row(row_id, get_docker_config(), toggle_docker, toggle_all_dockers)
    if row_id != MainFocusTab.ROW:
        toggle_docker(int(text.substr(7)))
        return
    focus_tab.row_pressed(dockers_menu)


## Writes a docker row's tick without announcing it, which is what a sync is:
## the docker changed elsewhere and the row is catching up.
func _tick_docker_row(index: int, on: bool) -> void:
    if dockers_menu == null:
        return
    var holder := SaMenu.list_holding(dockers_menu, _docker_key(index))
    var box := holder.check_box(_docker_key(index)) if holder != null else null
    if box != null:
        box.set_pressed_no_signal(on)


## Tab, from the shortcut router and the suites. `MainFocusTab` is the path.
func toggle_all_dockers() -> void:
    focus_tab.toggle()


## Toggles the docker at position *id* in the Window menu's docker rows, from a
## row press or the shortcut router, or has `FiltersDocker.answer_row` answer.
func toggle_docker(id: int) -> void:
    var dockers := get_docker_config()
    if id < 0 or id >= dockers.size():
        return

    var docker_node: Window = dockers[id]["node"] as Window
    if docker_node is FiltersDocker and (docker_node as FiltersDocker).answer_row(self):
        return
    var new_state := not docker_node.visible
    docker_node.visible = new_state
    # What the painter chose under focus mode is theirs, not the Tab's.
    SaFocusMode.forget(String(dockers[id]["id"]))
    SaUsageTally.docker(dockers[id]["id"], SaUsageTally.SHOWN if new_state else SaUsageTally.HIDDEN)
    if new_state:
        _front_docker = docker_node
        var section := DockerLayoutStore.section_for(dockers[id])
        # The whole frame on the host and under the bar, moved as little as can
        # be, noted in the store before the reapply below and its settle loop
        # put the stored one back, so the save after the tick writes the mended
        # place, or a docker stored low opens with its title alone on screen.
        # Here rather than in the store, which has
        # no lines to spare, and a summon is fitted already by its borrow.
        var stored: Vector2i = layout_store.value_for(section, "position", docker_node.position)
        var at := stored if stored != Vector2i() else docker_node.position
        var fitted := SaDockerLayoutRefit.new(below_bar, Callable()).shown(docker_node, at)
        if fitted != at:
            docker_node.position = fitted
            layout_store.note_placement(docker_node)
        layout_store.reapply_deferred(docker_node, section)
    _tick_docker_row(id, new_state)
    # Showing or hiding a docker is an edit, whether it came from the menu row
    # or from the chord `toggle_docker_by_id` routes through here.
    _painter_changed_the_layout()


## Toggles a docker named by its registered id.
##
## The menu's own handler counts positions in the visible list, which a chord
## has no way to know, so this is the door a command uses.
func toggle_docker_by_id(docker_id: StringName) -> void:
    var dockers := get_docker_config()
    for i in dockers.size():
        if StringName(dockers[i]["id"]) == docker_id:
            toggle_docker(i)
            return


## Shows the docker registered as *docker_id* under the pointer, or sends it
## back when its chord ran twice within a second. The door a summon command
## takes, beside [method toggle_docker_by_id].
##
## *locked* holds it out from the first frame, which is the same chord pressed
## with Ctrl. *at*, a centre in the pointer's space, opens it there instead.
##
## Nothing here calls `_painter_changed_the_layout`: a summon is a borrow, and
## nothing is written to the layout while a docker is out, so a workspace preset never learns a position the
## painter did not choose. The Window menu's tick stays with the layout too.
##
## The keyboard stays where it was. Showing an embedded window hands it the
## subwindow focus, so whatever held it before is given it back, the main
## window by the release `DockerFocus` keeps for that. A docker that held the
## keyboard before its chord keeps it, which is a docker the painter has just
## dragged by its title and summons with the pointer still there.
##
## **The release is for an embedded docker only.** It makes the docker
## unfocusable for one `grab_focus`, and Godot 4.7 on Windows writes that flag
## to a window of its own by rebuilding the window's style, which for a
## borderless one leaves `WS_VISIBLE` out. With the subwindows off there is no
## embedded window to say who holds the keyboard, so a docker in front would be
## taken for one the summon had focused and released: Windows would hide it,
## leave its picture on screen taking no input, and the log would say nothing.
func summon_docker_by_id(docker_id: StringName, locked: bool = false, at: Variant = null) -> void:
    for config: Dictionary in get_docker_config():
        if StringName(config["id"]) != docker_id:
            continue
        var win := config["node"] as Window
        var stack: Array[Window] = []
        if is_inside_tree() and get_viewport().is_embedding_subwindows():
            stack.assign(get_viewport().get_embedded_subwindows())
        var focused_before := DockerFocus.focused_of(stack)
        var held_before := win.has_focus()
        var point := Vector2i(at if at is Vector2i else summon.pointer())
        if summon.summon(win, DockerLayoutStore.section_for(config), point, Time.get_ticks_msec(), locked):
            SaUsageTally.docker(String(docker_id), SaUsageTally.SUMMONED)
        if win.has_focus() and not held_before:
            if focused_before != null:
                focused_before.grab_focus()
            elif win.is_embedded():
                DockerFocus.release(win)
        return


## Handles closing the window via the 'X' button
##
## A docker out on a summon or a lend goes home and nothing more, shown or
## hidden as it was, which is what its close says while it is out. No
## borrow outlives the window it lent, so the leave has nothing to show again.
func _on_docker_closed(id: int, node: Window) -> void:
    if summon.is_summoned(node):
        summon.send_back(DockerLayoutStore.section_for(get_docker_config()[id]))
        return
    node.hide()
    SaFocusMode.forget(String(node.name))
    SaUsageTally.docker(String(node.name), SaUsageTally.HIDDEN)
    _tick_docker_row(id, false)
    # The painter hook rather than the plain save, because closing a docker is
    # the painter arranging their workspace and a preset holds which dockers are
    # open.
    _painter_changed_the_layout()


## A docker that took the keyboard is the one in front, which is the only
## reading of "topmost" available: an embedded subwindow is raised by the
## embedder when it is focused, and it says so nowhere a script can ask.
func _on_docker_focused(docker: Window) -> void:
    _front_docker = docker


## Focuses the embedded docker a right press lands on, before the engine routes
## the press anywhere.
##
## Godot moves the embedded subwindow focus on a left press and on nothing else.
## Every other button is handed to whichever subwindow already holds that focus,
## and when none holds it the forwarding consumes the event and gives it to
## nobody: not the docker, not the host. So without this a right press on a
## toolbox category button does nothing until the painter has left-clicked into
## the toolbox once, and opens the flyout every time after that. The docker and
## the host are alternatives here rather than a race, and `accept_event()` on
## the button has no host press to stop.
##
## `window_input` fires in the window's own input handler before the viewport is
## pushed at, so the focus is already in place when the engine looks at it and
## the same press goes on to the docker under the pointer.
##
## The right button only. The middle button and the wheel have the same hole and
## are left alone on purpose: nothing in Sara reads a middle press on a docker,
## and moving the keyboard focus for a wheel notch is a surprise rather than a
## fix.
func _focus_docker_under_press(raw: InputEvent) -> void:
    var press := raw as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    if not is_inside_tree():
        return
    var host := get_window()
    if host == null:
        return
    # The signal carries the event as the window received it, before the
    # viewport un-scales it, so on a 2x display the position is twice the
    # logical one an embedded window's geometry is measured in. The same
    # arithmetic `MainCanvas._on_window_input` does, for the same reason.
    var at: Vector2 = host.get_final_transform().affine_inverse() * press.position
    var docker := docker_under(SaCursorPolicy.embedded_subwindows(host), at, _front_docker)
    if docker != null and not docker.has_focus():
        docker.grab_focus()


## The embedded docker of *dockers* whose rectangle holds *at*, in the host
## viewport's logical units, or null. Public and free of node state so a test
## can ask it without a window.
##
## Topmost by the memory `_front_docker` keeps: *front* wins when it holds the
## point and the last of the tree order takes it otherwise.
static func docker_under(dockers: Array[Window], at: Vector2, front: Window = null) -> Window:
    if front != null and dockers.has(front) and Rect2(Vector2(front.position), Vector2(front.size)).has_point(at):
        return front
    for i in range(dockers.size() - 1, -1, -1):
        var docker := dockers[i]
        if Rect2(Vector2(docker.position), Vector2(docker.size)).has_point(at):
            return docker
    return null


# --- Docker layout persistence -------------------------------------------------


## Built-in docker placement, in whatever units each docker measures geometry in.
##
## An embedded subwindow sits in the host's already-scaled logical space, a real
## OS window in physical pixels. DockerWindow.apply_window_scale() has already
## sized each one from its logical size, so this sets positions and only the one
## height that depends on the host.
##
## Re-runnable, because the host size is not final during _ready, and the boot
## calls [method place_dockers_until_settled] so it runs again while it settles.
func apply_default_docker_geometry() -> void:
    var host_size := _docker_host_size()
    if host_size.x <= 0 or host_size.y <= 0:
        return

    var top := below_bar()

    var toolbox := registered_docker_node(SaDockerIds.TOOLBOX)
    if toolbox:
        toolbox.position = _docker_units(toolbox, Vector2i(15, top))

    var color := registered_docker_node(SaDockerIds.COLOR)
    if color:
        var color_margin := _docker_units(color, Vector2i(15, top))
        color.position = Vector2i(host_size.x - color.size.x - color_margin.x, color_margin.y)

    var layers := registered_docker_node(SaDockerIds.LAYERS)
    if layers:
        var layers_margin := _docker_units(layers, Vector2i(15, 365))
        layers.position = Vector2i(host_size.x - layers.size.x - layers_margin.x, layers_margin.y)
        var foot := _docker_units(layers, Vector2i(0, 15 + SaStatusLine.rows_taken())).y
        var available := host_size.y - layers_margin.y - foot
        layers.size = Vector2i(layers.size.x, maxi(layers.min_size.y, available))

    var info := registered_docker_node(SaDockerIds.INFO)
    if info:
        # Centring a window, where half a pixel does not exist anyway.
        @warning_ignore("integer_division")
        var centred: Vector2i = (host_size - info.size) / 2
        info.position = centred


## The first logical row a docker's title may start on, below the bar: 65 with
## one row and taller with the second row on, the larger of the two, so a
## one-row layout is what it was. The layout store fits the default layout
## under it as well.
func below_bar() -> int:
    if _bar == null:
        return 65
    return maxi(65, int(_bar.get_combined_minimum_size().y) + 15)


## The default placement now, and again on every resize until the window has
## settled.
##
## The window is still at project.godot's 1920x1080 during _ready and only
## reaches its real size once the compositor has mapped it, so the host measured
## by the first placement is the wrong one: dockers came out placed for a
## 960-wide logical viewport regardless of the actual display. They are
## re-placed while the window is still settling, after which the user's own
## layout owns geometry.
func place_dockers_until_settled() -> void:
    apply_default_docker_geometry()
    var vp := get_viewport()
    if vp != null and not vp.size_changed.is_connected(_on_host_resized_during_startup):
        vp.size_changed.connect(_on_host_resized_during_startup)


## Re-place dockers while the compositor is still resizing the window.
##
## Bounded by the same settle window that gates saving, so a docker the user has
## dragged is never yanked back: after the window settles this disconnects and
## the stored layout is the only thing that moves anything.
func _on_host_resized_during_startup() -> void:
    if layout_save_allowed():
        var vp := get_viewport()
        if vp != null and vp.size_changed.is_connected(_on_host_resized_during_startup):
            vp.size_changed.disconnect(_on_host_resized_during_startup)
        return
    apply_default_docker_geometry()
    load_docker_layout()


## The boot is over and the settle clock starts, which the layout store's gate
## reads through [method layout_save_allowed]. The dockers the boot cover held
## back and the presets' scan wait for its `gone`. The scan was the long frame
## after Ready, 0.4 to 0.7 s, and the fade stood still through it. It reads in
## slices now, and after the cover still, so the painter has the window
## whole before the presets fill in.
func boot_finished() -> void:
    _ready_done = true
    _startup_ticks = Time.get_ticks_msec()
    var cover := SaBootCover.in_tree(self)
    if cover != null:
        cover.gone.connect(_after_the_cover, CONNECT_ONE_SHOT)
    else:
        _after_the_cover()


## Shows each docker the layout opened that the cover held back, a window of
## its own coming up after the blur rather than blank over it, and then brings
## the dialogs already up in front of them, the welcome window first among them.
func _after_the_cover() -> void:
    var shown := 0
    for config in get_docker_config():
        var win := config["node"] as Window
        var section := DockerLayoutStore.section_for(config)
        if SaBootCover.holds_back(win) and layout_store.value_for(section, "visible", false):
            win.show()
            layout_store.reapply_deferred(win, section)
            shown += 1
    for dialog in get_tree().get_nodes_in_group(SaDialogWindow.OPEN_GROUP) if shown > 0 else []:
        if (dialog as Window).visible:
            (dialog as Window).grab_focus()
    _scan_the_presets_after_the_first_frame()


## Holds the brush presets unread until the boot's first frame after `ready`.
## Called by `Main` once the bar is built and before it is bound to the tool
## machine, whose first refresh is the one that read them.
func hold_the_presets() -> void:
    var presets := ToolOptionsPresets.in_tree(self)
    if presets != null:
        presets.hold_scan()


## Releases what `hold_the_presets` held, a frame after the first frame after
## `ready` has drawn.
##
## Not in the draw's own callback, because `Main` connects the
## `first_frame_after_ready` mark to the same signal after this was connected,
## and the scan would then run and be timed before the mark it has to follow.
## The process frame after it is the next frame's, so the painter has a whole
## window on screen before the scan's first slice begins.
func _scan_the_presets_after_the_first_frame() -> void:
    var presets := ToolOptionsPresets.in_tree(self)
    if presets == null or not presets.scan_held:
        return
    await RenderingServer.frame_post_draw
    await get_tree().process_frame
    if is_instance_valid(presets):
        presets.scan_in_slices()


## Saving is skipped until the window has settled, so a layout is never
## overwritten with the half-built geometry the compositor reports at startup.
##
## A node outside any tree has no compositor mapping its windows, which is what
## a suite's `Main` is: it is never parented, so its saves go through at once,
## and the tree says so without a flag a suite sets.
func layout_save_allowed() -> bool:
    if not is_inside_tree() or DisplayServer.get_name() == "headless":
        return true
    return _ready_done and Time.get_ticks_msec() - _startup_ticks >= LAYOUT_SETTLE_MS


## A change the app can attribute to the painter, rather than to the compositor
## settling a window it has just been handed.
##
## The difference matters because this is what forks a shipped preset. A load
## re-asserts every docker's geometry for sixty frames and each re-assertion
## emits `size_changed`, so a fork driven by every `save()` would fork the
## preset it had just loaded, every time, with the painter touching nothing.
## `docker_layout_changed` is emitted only by the drag handle and the resizer,
## which is the same distinction `main.gd` relies on. The show, the
## hide and the close call this directly, knowing it is the painter. Tab, the
## scale and every setting but an element page never do.
func _painter_changed_the_layout() -> void:
    # Through the settle gate, because this signal is the definition of what the
    # gate is not protecting against.
    layout_store.save(true)
    if not layout_store.fork_for_painter_edit().is_empty():
        setup_dockers_menu()


## The scale moved the host's logical size, so the dockers are placed on it
## again once each has re-derived its own size. Saving them where the change
## pushed them and forking lost the whole arrangement to one trip to scale 2.
func _the_host_was_rescaled(_scale: float) -> void:
    layout_store.reflow_to_host()


## Restores every docker from the store, which ticks the Window menu's rows as
## it goes. While the boot cover stands, a docker that is a window of its own is
## held back and stays hidden until it is gone, since no layer covers it.
func load_docker_layout() -> void:
    var cover := SaBootCover.in_tree(self)
    for config in get_docker_config() if cover != null else []:
        cover.hold_back(config["node"] as Window)
    layout_store.dockers_menu = dockers_menu
    layout_store.restore_all()


## The named layouts, what is in use, and everything a preset holds.
##
## A picture of the Layouts submenu says which names are offered and nothing
## about what loading one did, and the three things a preset carries beyond
## geometry are a float and two dictionaries. So the dump carries all of it.
static func capture_layout_state(root: Window) -> Dictionary:
    var dockers := root.find_child("MainDockers", true, false)
    return dockers.call("layout_report") if dockers != null else {}


## This node's own half of [method capture_layout_state].
func layout_report() -> Dictionary:
    var open_dockers: Array = []
    for config: Dictionary in get_docker_config():
        var win := config["node"] as Window
        if win != null and win.visible:
            open_dockers.append(String(config["id"]))
    open_dockers.sort()
    var hidden: Array = []
    for category: Dictionary in SaSettings.reorderable_categories():
        var id := String(category["id"])
        for element: String in SaSettings.get_layout_order(id):
            if not SaSettings.get_element_visible(id, element):
                hidden.append("%s/%s" % [id, element])
    hidden.sort()
    return {
        "presets": layout_store.list_presets(),
        "current": layout_store.current_preset(),
        "open_dockers": open_dockers,
        # What the store thinks each open docker's position is, beside what the
        # window reports in `windows`. A drag that the window shows and the store
        # does not is a drag the settle loop is about to undo, and the two
        # numbers are the only way to tell that apart from a drag that never
        # happened.
        "stored_positions": layout_store.stored_positions(),
        # The dockers out on a summon, which `open_dockers` counts among the
        # open ones while they are out.
        "borrowed": _borrowed_ids(),
        "saves_allowed": layout_store.save_allowed.is_valid() and layout_store.save_allowed.call(),
        "ui_scale": SaSettings.ui_scale,
        "hidden_elements": hidden,
        "top_bar_order": SaSettings.get_layout_order("TopMenuBar"),
    }


func _borrowed_ids() -> Array:
    var out: Array = []
    for config: Dictionary in get_docker_config():
        if layout_store.is_borrowed(DockerLayoutStore.section_for(config)):
            out.append(String(config["id"]))
    out.sort()
    return out


## Where a `docker` step has just put *win*, told to the layout store.
##
## Here rather than in `SaDockerDriver` because the store is this node's, and
## reached by name from the capture the way every other door on this node is.
func note_docker_placement(win: Window) -> bool:
    if layout_store == null:
        return false
    return layout_store.note_placement(win)


## Drives the layout presets: the way the Dockers menu's Layouts submenu drives
## them, `{"layout_preset": {"load": "Painting"}}`, `{"save": "Painting"}`,
## `{"edit":...}` or `{"delete":...}`, and `{"close": true}`, the save the
## window's close and a switch to another program make, so a scenario's next
## start reads what a close would have left.
##
## By name rather than by clicking the submenu row, for the reason every other
## menu step here exists: a `PopupMenu` is a Window an injected click cannot
## land on. `{"edit": true}` is the painter moving something, which is what
## forks a shipped preset.
##
## Static because the executor dispatches through the class and not through a
## node it holds, and the node is found here rather than passed in. The work is
## [method drive_layout_preset], which is the instance half and the one that
## reaches the store. Documented from this end: the catalogue reads the `##`
## above the function the executor names, so a pair documented from the other
## end reports the step kind as undocumented.
static func capture_layout_preset(tree: SceneTree, spec: Dictionary) -> String:
    var dockers := tree.root.find_child("MainDockers", true, false)
    if dockers == null:
        return "SaCapture: no MainDockers to reach the layouts through"
    return dockers.call("drive_layout_preset", spec)


## This node's own half of [method capture_layout_preset].
func drive_layout_preset(spec: Dictionary) -> String:
    var store: DockerLayoutStore = layout_store
    if spec.has("load"):
        var wanted := String(spec["load"])
        if not store.load_preset(wanted):
            return "SaCapture: no layout called '%s'" % wanted
        return "SaCapture: layout '%s' loaded" % wanted
    if spec.has("save"):
        var under := String(spec["save"])
        if not store.save_preset(under):
            return "SaCapture: layout '%s' would not save" % under
        return "SaCapture: layout saved, in use '%s'" % store.current_preset()
    if spec.has("close"):
        store.save()
        return "SaCapture: layout saved as a close saves it, focus mode %s" % SaFocusMode.status_text()
    if spec.has("edit"):
        _painter_changed_the_layout()
        return "SaCapture: layout edited, in use '%s'" % store.current_preset()
    if spec.has("delete"):
        # A scenario's own reset. A painter's copy of a shipped name shadows the
        # one that ships, so a run that saved `user` yesterday loads yesterday's
        # `user` today, and the first dump stops meaning anything.
        var gone := String(spec["delete"])
        store.delete_preset(gone)
        return "SaCapture: layout '%s' deleted, in use '%s'" % [gone, store.current_preset()]
    return "SaCapture: layout_preset wants load, save, edit, delete or close"
