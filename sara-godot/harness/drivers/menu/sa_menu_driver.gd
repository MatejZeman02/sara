## Every menu and popup a scenario opens, and the rows it presses in them.
##
## **One class because every one of them is a `Window`.** A menu, a file
## chooser, a question box, the blend list, the preset list and a dropdown are
## all popups, and an injected click does not route into a popup any more than
## it routes into an embedded docker. So each of these starts one step in from
## the click that cannot land, at the signal the control would have emitted, and
## says out loud what it pressed.
##
## Reached by path from the step table rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaMenuDriver
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")

## The adjustments' driver, for the one door the two filters' `open` shares.
const FilterDriver := preload("res://harness/drivers/sa_filter_driver.gd")

## The run, by path like every other harness file this one names.
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

## The run, read for its tree and for the folder a log goes beside.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Opens a top bar menu: a click cannot land on a menu button any more than it
## can on a row, so this emits the title button's own press. `{"menu": "Select"}`.
##
## **Through the button** rather than popping the list by hand at a fixed
## position. The bar rebuilds a menu before it opens one, so a list popped
## behind the bar's back shows whatever state it was built with last, and the
## handler is the same one a painter's press reaches. The press rather than
## the bar's handler by name, because the handler is the bar's own.
func open_menu(menu_name: String) -> void:
    var bar := top_menu_bar()
    if bar == null or not bar.menus.has(menu_name) or bar.menu_buttons.get(menu_name) == null:
        push_warning("SaCapture: no menu called '%s'" % menu_name)
        return
    (bar.menu_buttons[menu_name] as BaseButton).pressed.emit()


## Reaches the Select menu's own handler directly, for an item behind a
## submenu-turned-dialog that a click cannot land on: the popup is an embedded
## subwindow, same reason a Preferences page cannot use a click either.
func click_select_item(id: int) -> void:
    var bar := top_menu_bar()
    if bar == null:
        push_warning("SaCapture: no Select menu found")
        return
    var select_menu := bar.menu("Select") as SaSelectMenu
    if select_menu != null:
        select_menu.on_id_pressed(id)


## Reaches the File menu's own handler directly, because the Export dialog is
## behind an embedded subwindow's menu item, the same reason as
## `click_select_item`.
func click_file_item(id: int) -> void:
    var bar := top_menu_bar()
    if bar == null:
        push_warning("SaCapture: no File menu found")
        return
    var file_menu := bar.menu("File") as SaFileMenu
    if file_menu != null:
        file_menu.on_id_pressed(id)


## Answers the file picker: the one File > Open or any other caller put up,
## `{"file_picker": {"cancel": true}}` closes it the way Escape does and
## `{"file_picker": {"choose": "/path"}}` picks a file in it.
##
## The picker is answered through `SaFilePicker` rather than clicked, because on
## a desktop it is the platform's own window, which no injected click reaches,
## and no node of the tree stands for it. The order this proves is a claim about
## which window is up rather than about what either of them looks like. The line
## names which of the two kinds was up, since a platform with no picker of its
## own gets the engine's dialog, drawn in the shot.
func file_picker(spec: Dictionary) -> String:
    var picker := SaFilePicker.newest()
    if picker == null:
        return "SaCapture: no open file picker"
    var kind := "the engine's dialog" if picker.fallback != null else "the platform's picker"
    if spec.has("choose"):
        var path := String(spec["choose"])
        picker.choose(PackedStringArray([path]))
        return "SaCapture: file picker chose '%s', in %s" % [path, kind]
    picker.cancel()
    return "SaCapture: file picker cancelled, in %s" % kind


## Answers Sara's question: it presses one of the buttons on whatever question
## Sara itself has put up, `{"answer": 1}` is Discard on the unsaved-changes
## prompt.
##
## `{"message": {"close": ...}}` covers Escape, the title bar's close and a
## plain hide, all three of which answer as cancel. Nothing could reach the
## other buttons, so a scenario could watch a question appear and never watch
## it be said yes to. Here rather than on `sa_message.gd`, which `d9` owns.
func answer_question(index: int) -> String:
    var tree := _run.tree()
    var dialog := SaMessage.live_dialog(tree)
    if dialog == null:
        return "SaCapture: no question is up to answer"
    if index < 0 or index >= dialog.buttons.size():
        return "SaCapture: the question has %d buttons, not %d" % [dialog.buttons.size(), index + 1]
    var label := dialog.buttons[index].text
    dialog.buttons[index].pressed.emit()
    return "SaCapture: answered '%s'" % label


## Runs a menu row: one row of any menu, for a row a click cannot land on,
## `{"menu_item": {"menu": "Layer", "id": 410}}`.
##
## The generic form of the two above, which name their menu because they were
## written for one dialog each. A row that only changes state, as the Layer
## menu's two lock rows do, has nothing for a scenario to open and nothing
## to click, so this is the only way to prove the row does what it says.
func click_menu_item(spec: Dictionary) -> String:
    var bar := top_menu_bar()
    var menu_name := String(spec.get("menu", ""))
    var id := int(spec.get("id", -1))
    var popup := bar.menus.get(menu_name) as SaChoicePopup if bar != null else null
    # **The docker row first, and only where the list carries one under this
    # number**. Those rows are built by `MainDockers` out of the
    # registered dockers rather than by a row of `SaMenu`, so they are keyed
    # `docker_%d` and no id of the Window menu's own answers to them. Pressing
    # the row is what a click does, so this is the same row fired the same way
    # rather than a second path into the handler. Every other menu's popup
    # carries no docker row at all, so for those the branch below is the only
    # one taken and the step behaves as it always has.
    var docker_row := StringName("docker_%d" % id)
    var holder := SaMenu.list_holding(popup, docker_row)
    if holder != null:
        # Pressed rather than emitted, so the disabled row a painter cannot
        # reach is one a scenario cannot reach either. On the kind's submenu
        # that holds it, as a painter's press is.
        if not holder.press_row(docker_row):
            return "SaCapture: %s has no row %d to press" % [menu_name, id]
        return "SaCapture: %s item %d, through its popup" % [menu_name, id]
    var menu := bar.menu(menu_name) if bar != null else null
    if menu != null and SaMenu.group_list(menu.popup, id) != null:
        # A group row opens its submenu beside it, as a painter's press does,
        # so a scenario can show the rows a group holds.
        SaMenu.open_group(menu.popup, id)
        return "SaCapture: %s group %d, opened" % [menu_name, id]
    if menu != null:
        menu.on_id_pressed(id)
        return "SaCapture: %s item %d" % [menu_name, id]
    if popup == null:
        return "SaCapture: no menu called '%s'" % menu_name
    return "SaCapture: %s has no row %d to press" % [menu_name, id]


## Opens the bar's blend list: the one on the tool options bar, `{"blend": ""}`.
## Same reason `open_menu` exists, one level further in again.
##
## *section* names a heading of the menu's one column, which is scrolled to,
## because the menu has headings rather than submenus to open beside it.
func open_blend_menu(section: String = "") -> void:
    var button := blend_button()
    if button == null:
        push_warning("SaCapture: no blend menu on the tool options bar")
        return
    button.pressed.emit()
    if section.is_empty():
        return
    var ids := button.section_ids(section)
    if ids.is_empty():
        push_warning("SaCapture: the blend list has no section called '%s'" % section)
        return
    var first := button.popup.label_button(ids[0])
    if first != null:
        first.grab_focus()


## Picks a blend list row: by its label with `{"blend_row": "multiply"}` and by
## its check box with `{"blend_row": "multiply!"}`. An injected click does not
## route into a popup, which is a `Window` of its own, and the two controls
## are separate presses, which is what a scenario here tells apart.
func press_blend_row(spec: String) -> String:
    var button := blend_button()
    if button == null:
        return "SaCapture: no blend list on the tool options bar"
    var popup := button.popup
    var wants_check := spec.ends_with("!")
    var row_id := StringName(spec.trim_suffix("!"))
    var line := ""
    if wants_check:
        if not popup.press_check(row_id):
            return "SaCapture: no check box on blend row '%s'" % row_id
        line = (
            "ticked %s -> %s, favourites now [%s]" % [row_id, popup.is_checked(row_id), ", ".join(SaSettings.blend_favorites)]
        )
    elif not popup.press_row(row_id):
        return "SaCapture: no blend row called '%s'" % row_id
    else:
        line = "chose %s, the bar reads '%s'" % [row_id, button.text]
    _write_blend_log(line + _docker_blend_line())
    return "SaCapture: " + line


## What the Layers docker's own blend control says, appended to every line the
## step writes. The aim is that the two controls be the same control,
## and the one thing a picture cannot show is that a mode chosen on the bar left
## the docker's own button where it was: they are two `BlendModeButton`s reading
## one registry and one setting, not one control drawn twice.
func _docker_blend_line() -> String:
    var docker := CaptureRun.DockerLookup.window(_run.tree(), DockerIds.LAYERS)
    if docker == null or not "blend_mode_opt" in docker:
        return ""
    var other: BlendModeButton = docker.blend_mode_opt
    if other == null:
        return ""
    return "  |  the docker reads '%s', its list holds %d rows" % [other.text, other.popup.row_ids().size()]


## Appends a line to `blend.txt` in the capture's own directory, for the reason
## `harness/report/sa_cursor_probe.gd` writes `probe.txt`: `scripts/sara_shot.py` shows a
## run's stdout only when something failed, and the whole result of this step is
## text. No block is added to `ui/sa_capture_dump.gd`, because a step whose
## result is its own text needs no place in the dump every capture shares.
func _write_blend_log(line: String) -> void:
    var dir := _run.out_dir
    if dir == "" or line == "":
        return
    var path := dir.path_join("blend.txt")
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line)


## Opens the brush preset list, `{"preset": {"open": true}}`. Same reason
## `open_blend_menu` exists: the list is in a Window an injected click does not
## route into, so without this the only proof of what the list shows is the test
## suite.
##
## Through the group's own opener, so the step reaches whatever the button
## opens, which is the Brush Presets docker.
func open_preset_menu() -> void:
    var bar := options_bar()
    if bar == null or bar.preset_box == null:
        push_warning("SaCapture: no preset chooser on the tool options bar")
        return
    bar.preset_box.open_presets_docker()


## Drives the preset chooser a scenario has open:
## `{"preset": {"open": true, "search": "ink", "tag": "paint", "icon_size": 72,
## "finish": true}}`, applied in that order and each optional.
##
## `"tags"` is one block, `{"menu": "Inky", "tick": "wet", "on": true}` and the
## rest, handed whole to `SaBrushPresetTags` rather than unpacked here: the menu,
## the name field and the delete question are that class's and so is the door
## onto them. Its report goes to `preset_tags.txt` beside the shots for the
## reason the chooser's own report does.
##
## Helpers rather than clicks, for the reason `open_preset_menu` above gives: the
## chooser is inside a `Window` and an injected click does not route into one.
## `finish` drains the render queue, so a scenario that wants the grid finished
## rather than filling says so instead of guessing at a wait.
##
## `star` presses the star on the cells it names, one name or a list, and
## `starred` turns the Starred filter on or off, after the tag and before the
## search, so one step can star, filter and narrow. Both go through
## `SaBrushPresetStars`, which presses the controls a hand would.
##
## The docker's chooser, which is the only one there is: the presets are a
## window of their own rather than a popup of the bar.
func drive_preset_chooser(spec: Dictionary) -> String:
    var tree := _run.tree()
    var docker := CaptureRun.DockerLookup.window(tree, DockerIds.BRUSH_PRESETS)
    var chooser: SaBrushPresetsChooser = docker.get("chooser") if docker != null else null
    if chooser == null:
        return "SaCapture: no preset chooser in the Brush Presets docker"
    if spec.has("tag"):
        chooser.capture_tag(String(spec["tag"]))
    if spec.has("star"):
        var starring: Variant = spec["star"]
        for preset_name: Variant in starring if starring is Array else [starring]:
            chooser.stars.capture_star(String(preset_name))
    if spec.has("starred"):
        chooser.stars.capture_filter(bool(spec["starred"]))
    # The search field and the Strokes and Tip row are plain controls, so the
    # walker types and presses them. An unknown word is a loud failure and not
    # a quiet Strokes, as for a tag. The walker refuses a missing control and a
    # word that is neither a value nor a label of the row, so its false is the
    # one guard, and the warning names the two words it takes.
    if spec.has("search"):
        ControlWalker.move(chooser.search_field, String(spec["search"]))
    if spec.has("thumb") and not ControlWalker.move(chooser.thumb_option, spec["thumb"]):
        push_warning("SaCapture: preset thumb failed, '%s' is neither 'strokes' nor 'tip'" % spec["thumb"])
    if spec.has("tags"):
        # The tags' whole block in one key, unpacked by the gesture that owns it.
        _append_line("preset_tags.txt", JSON.stringify(chooser.capture_tags(spec["tags"])))
    if spec.has("icon_size"):
        SaSettings.preset_icon_size = int(spec["icon_size"])
        chooser.refresh()
    if bool(spec.get("finish", false)):
        chooser.capture_finish()
    var line := "SaCapture: preset_chooser %s" % JSON.stringify(chooser.chooser_report())
    # Beside the shots as well as on stdout, for the reason the cursor probe and
    # the blend log give: `scripts/sara_shot.py` prints the first twenty problem
    # lines of a run and nothing else, so a step whose whole result is text
    # otherwise leaves nothing in the folder a person reviews.
    _append_line("preset_chooser.txt", line)
    return line


## Appends *line* to *file_name* in the capture's own directory.
func _append_line(file_name: String, line: String) -> void:
    var dir := _run.out_dir
    if dir.is_empty():
        return
    var path := dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line.trim_prefix("SaCapture: "))


## Opens a dropdown by name, `{"dropdown": "InputSpaceOption"}`. An
## `OptionButton`'s list is a Window like every other menu here, so a click
## cannot reach it, and it is the one list whose rows the engine builds rather
## than Sara, so the radio dots on its rows are Sara's to take off.
##
## `{"dropdown": {"name": "CompareGamutOption", "row": "Compare: Rec. 2020"}}`
## picks a row instead, by its text or its index, and emits `item_selected` the
## way a hand's click would. A picked row is printed with what the button
## then reads, and a row that is not there is printed with the rows that are,
## so a scenario written against the wrong words says so in its log.
##
## **A name that two surfaces answer to resolves to the docker's copy**.
## The top bar builds its own copy of every tool option it shows, so
## `{"name": "StabilizerModeOpt"}` is the top bar's button as well as the Tool
## Options docker's, and a step taking whichever came first in the tree would
## hang on the tree's order.
## *in* narrows the walk to one node's subtree, for the step that means the top
## bar's copy: `{"name": "BlendModeOpt", "in": "CustomTitleBar"}`.
func open_dropdown(spec: Variant) -> void:
    var tree := _run.tree()
    var node_name := String(spec.get("name", "")) if spec is Dictionary else String(spec)
    var in_node := String(spec.get("in", "")) if spec is Dictionary else ""
    var candidates := _run.nodes_named(tree.root, node_name, in_node)
    for node in candidates:
        var option := node as OptionButton
        if option == null:
            continue
        if spec is Dictionary:
            print(_pick_dropdown_row(option, node_name, spec.get("row")))
            return
        # `show_popup()` rather than `popup()` on the list itself: the button
        # sizes and places it, and a list popped up behind its owner's back
        # left the app unable to quit, which reads as a hung runner.
        option.show_popup()
        return
    # The same step over the control that replaced the engine's dropdown,
    # so a scenario written against `StabilizerModeOpt` still says the words it
    # said when that node was an `OptionButton`.
    for node in candidates:
        var choice := node as SaChoiceButton
        if choice == null:
            continue
        if spec is Dictionary:
            print(_pick_choice_row(choice, node_name, spec.get("row")))
            return
        choice.toggle_list()
        return
    push_warning("SaCapture: no dropdown called '%s'" % node_name)


## Selects *row* on *option*, an item's text or its index, and answers the line
## the step prints.
##
## The one static left in the class, because it reads nothing of the run: it is
## a function of the button and the row, and taking the instance would only hide
## that.
static func _pick_dropdown_row(option: OptionButton, node_name: String, row: Variant) -> String:
    var rows: Array[String] = []
    for index in option.item_count:
        rows.append(option.get_item_text(index))
    var picked := -1
    if row is float or row is int:
        picked = int(row) if int(row) >= 0 and int(row) < option.item_count else -1
    else:
        picked = rows.find(String(row))
    if picked < 0:
        return "SaCapture: dropdown %s has no row %s, its rows are %s" % [node_name, JSON.stringify(row), JSON.stringify(rows)]
    option.select(picked)
    option.item_selected.emit(picked)
    return "SaCapture: dropdown %s picked row %d, %s" % [node_name, picked, JSON.stringify(option.get_item_text(option.selected))]


## The same as `_pick_dropdown_row`, over an `SaChoiceButton`. Separate
## rather than one function over a Variant, because the two controls answer
## nothing in common: one counts items and the other holds values.
static func _pick_choice_row(choice: SaChoiceButton, node_name: String, row: Variant) -> String:
    var rows := choice.choice_labels()
    if not choice.pick_row(row):
        return "SaCapture: dropdown %s has no row %s, its rows are %s" % [node_name, JSON.stringify(row), JSON.stringify(rows)]
    return "SaCapture: dropdown %s picked %s" % [node_name, JSON.stringify(choice.text)]


## The bar's blend menu, or null before the bar has built its controls.
func blend_button() -> BlendModeButton:
    var bar := options_bar()
    return bar.control_for(ToolOptionsBar.BLEND_KEY) as BlendModeButton if bar != null else null


## The one tool options bar in the tree, or null before there is one.
func options_bar() -> ToolOptionsBar:
    var tree := _run.tree()
    for node in tree.root.find_children("*", "HBoxContainer", true, false):
        var bar := node as ToolOptionsBar
        if bar != null:
            return bar
    return null


## The picture the fit dialog is photographed with: 300 by 200 against the
## default 1920 by 1080 canvas, so the sizes differ and the ratios do not
## match, which is the case the dialog exists for. A checkout's fixture, which
## the pack leaves out with the rest of `tests/`, so a scenario driving this
## step on an exported build names a *picture* of its own.
const FIT_PICTURE := "res://tests/data/import_gradient.png"


## Imports that picture through the File menu's own path, which opens the fit
## dialog. `{"open": "import_fit"}`. The Import entry's file dialog cannot be
## driven from a scenario, and neither can a drop, so this starts where both
## of them hand off.
## *space_id* names a `SaColorSpace` preset to leave the dialog's input colour
## space row on, `{"open": "import_fit", "space": "display_p3"}`. The row
## is an `OptionButton`, whose popup is a Window, so an injected click cannot
## reach it any more than it can reach the menu item this step stands in for.
## It prints the space it left, which is what a scenario's log is read for.
##
## *fit_name* picks the fit: "stretch", "actual" or "inside" picks that row of the
## fit dropdown and presses Place, so the picture actually lands and a shot says
## whether the choice did what its sentence promises.
## `{"open": "import_fit", "fit": "stretch"}`. The dropdown's popup is a Window
## for the same reason the space row's is, so this is the same kind of door.
##
## *picture* is a `res://` path to import instead of `FIT_PICTURE`, so a
## scenario can show the window over a file that names its gamut,
## `{"open": "import_fit", "picture": "res://tests/data/display_p3_cicp.png"}`.
func import_picture(space_id: String = "", fit_name: String = "", picture: String = "") -> void:
    var files := SaDocumentFiles.in_tree(_run.tree())
    if files == null:
        push_warning("SaCapture: no document flow to import through")
        return
    files.import_path(picture if not picture.is_empty() else FIT_PICTURE)
    if space_id.is_empty() and fit_name.is_empty():
        return
    var dialog := files.get_node_or_null(NodePath("ImportFitDialog")) as SaImportFitDialog
    if dialog == null:
        push_warning("SaCapture: the import did not open a fit dialog to answer")
        return
    if not space_id.is_empty():
        if not dialog.select_space(StringName(space_id)):
            push_warning("SaCapture: no input colour space called '%s'" % space_id)
            return
        print("import space -> %s" % dialog.chosen_space().id)
    if fit_name.is_empty():
        return
    var fit := SaImportFitDialog.fit_from_setting(fit_name)
    if fit == SaImageImport.Fit.ORIGIN:
        push_warning("SaCapture: no fit called '%s'" % fit_name)
        return
    dialog.select(fit)
    var place := dialog.find_child("PlaceButton", true, false) as Button
    if place == null:
        push_warning("SaCapture: the fit dialog has no Place button")
        return
    place.pressed.emit()
    print("import fit -> %s, placed" % fit_name)


## Sets New Document's gamut: its gamut row goes on a named gamut,
## `{"new_document_gamut": "ACES AP1"}`. The row is an `OptionButton` whose popup
## is a Window, so an injected click cannot reach it any more than it can reach
## the menu item that opened the dialog.
func select_new_document_gamut(gamut_name: String) -> String:
    var tree := _run.tree()
    var dialog := tree.root.find_child("NewDocumentDialog", true, false) as NewDocumentDialog
    if dialog == null or not dialog.visible:
        return "SaCapture: no New Document dialog open"
    if not dialog.select_gamut(gamut_name):
        return "SaCapture: no gamut called '%s'" % gamut_name
    return "SaCapture: new document gamut -> %s" % gamut_name


## Opens a welcome window built as `SaBoot` builds it on a profile's first
## launch, with `SaSettings.first_launch_done` put back to false first, so the
## window that opens is the boot's own path from the window's construction on.
## What it does not cover is the boot's refusals, which a capture run meets.
##
## The window is the door's and not `MainDialogs`', so a later plain `open`
## shows that one, as a later launch would. Any welcome window up is put away
## first, and the door's window is freed when it is put away in turn.
func open_first_launch_welcome() -> String:
    var tree := _run.tree()
    for node in tree.root.find_children("*", "Window", true, false):
        if node is SaWelcomeWindow:
            (node as Window).hide()
    SaSettings.first_launch_done = false
    var window := SaWelcomeWindow.new(false, true)
    var main_node := tree.current_scene
    var registries: SaRegistries = main_node.get("registries") if main_node != null else null
    if registries != null:
        window.follow_catalogues(registries.translations)
    window.visibility_changed.connect(
        func() -> void:
            if not window.visible:
                window.queue_free()
    )
    SaBoot.put_up(window, tree.root)
    return (
        "SaCapture: first launch welcome on '%s', first_launch_done %s"
        % [window.tabs.get_tab_title(window.tabs.current_tab), SaSettings.first_launch_done]
    )


## The one `TopMenuBar` in the tree, or null before there is one. Main's own
## bar first, because a walk of the whole tree was 8 ms of every menu step in a
## timed freeze check, a cost a painter's click never pays. The
## walk stays for a tree with no Main, a suite's.
func top_menu_bar() -> TopMenuBar:
    var tree := _run.tree()
    var main := tree.current_scene as Main
    if main != null and is_instance_valid(main.custom_title_bar):
        return main.custom_title_bar
    for node in tree.root.find_children("*", "PanelContainer", true, false):
        var bar := node as TopMenuBar
        if bar != null:
            return bar
    return null


## Opens a menu's dialog: by emitting the signal the menu emits.
##
## `click` cannot reach a menu item: Wayland will not let a client place the
## pointer, and an injected click does not route into an embedded subwindow, which
## is where the menus live. That left the three dialogs unreachable from a
## scenario, and it is why File > New shipped with its Create button off the
## bottom edge for a whole session: nothing that ran here had ever seen it.
##
## Moved here from `sa__runner.gd` when that file reached the thousand-line
## limit: opening a dialog a menu opens is this file's subject.
##
## This starts one step further in than a click would, at the menu handler's own
## deferred emit, so everything from the dialog's construction onward is the real
## path. What it does not cover is the menu item itself.
##
## `{"open": "welcome", "launch": "first"}` opens the welcome window in the
## state the first launch's boot builds it in, which the boot itself refuses
## under a capture run: see `open_first_launch_welcome`. `{"open": "modules",
## "space": "kaleidoscope"}` opens the Modules window on that module's page.
func open_dialog(which: String, space_id: String = "", fit_name: String = "", picture: String = "", launch: String = "") -> void:
    match which:
        "new_document":
            EventBus.new_document_requested.emit()
        "color_space":
            EventBus.color_space_requested.emit()
        "canvas_size":
            EventBus.canvas_size_requested.emit()
        "image_size":
            EventBus.image_size_requested.emit()
        "preferences":
            EventBus.preferences_requested.emit()
        "about":
            EventBus.about_requested.emit()
        # A module's row in Modules > Active Modules, `space` naming the module
        # whose page it turns to, the first module's when it names none.
        "modules":
            EventBus.module_page_requested.emit(StringName(space_id))
        # Help opens it again, and the boot opens it through the same signal,
        # so a scenario's door is the app's own.
        "welcome":
            if launch == "first":
                print(open_first_launch_welcome())
            else:
                EventBus.welcome_requested.emit()
        "shortcuts":
            EventBus.shortcuts_requested.emit()
        "tablet_sweep":
            EventBus.tablet_sweep_requested.emit()
        # The base module's filters, opened the way their
        # Filter menu row opens them, by asking the registry.
        "levels", "curves":
            FilterDriver.invoke_filter(_run.tree(), which)
        "import_fit":
            import_picture(space_id, fit_name, picture)
        "feather":
            click_select_item(SaSelectMenu.ID_FEATHER)
        "border":
            click_select_item(SaSelectMenu.ID_BORDER)
        "export":
            click_file_item(SaFileMenu.ID_EXPORT)
        _:
            push_warning("SaCapture: no dialog called '%s'" % which)
