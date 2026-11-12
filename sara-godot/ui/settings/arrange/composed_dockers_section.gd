## The part of Layouts and dockers that makes a docker of your own and deletes
## one: a row with a name, what the docker starts from and a Make button, and
## the Delete a composed docker's line carries beside its Elements….
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter forks an existing docker or starts an empty one, so the start is
## Empty or any docker by its title, and a fork starts with the placeable
## elements of the docker it was forked from, in that docker's order now, its
## hidden ones hidden. A fork of a docker of your own takes what that one holds,
## switches and all. The docker is made in the library `SaComposedDockers`
## keeps, which registers it as any docker, so the Window menu hears of it, and
## `MainDockers` builds its window and gives it a line here. Make then opens it,
## and [signal changed] has the page draw its lines again with the new one among
## them.
##
## **The row is a section of its own, under every docker's line.** The start
## dropdown offers every docker's title, and the search finds a row by what its
## dropdown offers, so a row above the lines would be the first answer to a
## search for "Layers" rather than the Layers line.
##
## **A name no docker has.** Make is dimmed while the name is empty or another
## docker's, built in or of your own, because the Window menu and this page
## list a docker by its name and two of one name are two rows nobody can tell
## apart.
##
## **Delete asks.** A docker of your own is the one thing on this page with
## nothing shipped to go back to, so the question names it and says that what
## it held stays at home, and Cancel is what Enter and Escape answer.
##
## The window is opened through the docker manager's own toggle, found on the
## main scene by the methods the Brush Presets docker's reveal asks for, so the
## Window menu's tick and the saved layout follow it as they follow a menu row.
class_name SaComposedDockersSection
extends RefCounted

## A docker was made or deleted, so the page draws its lines again.
signal changed

## The key of the New docker row.
const FIRST_ROW := &"new_docker"

## The start that holds nothing.
const EMPTY := ""

## The question's two buttons, in the order they stand.
const ANSWER_CANCEL := 0
const ANSWER_DELETE := 1

## The name field, the start dropdown and the Make button of the row, kept so
## the capture door types and presses where a hand would.
var name_edit: LineEdit = null
var start_choice: SaChoiceButton = null
var make_button: Button = null

## The question a Delete put up, while it is up, so a second press does not
## stack another on it.
var question: SaMessage = null

## The library this makes in, or null for the app's.
var _given: SaComposedDockers = null


## *library* is a suite's own. Left out, the section makes in the app's,
## `SaComposedDockers.app`, read at each press because the boot writes it
## after a page may have been built.
func _init(library: SaComposedDockers = null) -> void:
    _given = library


## The section, under every docker's line.
func declare(ui: SaPage) -> void:
    var rows := ui.section(tr("Dockers of your own"))
    var box := SaMake.row(null, "NewDockerBox", SaTheme.GAP)
    name_edit = SaMake.line_edit(box, "NewDockerName", "", tr("Docker name"))
    name_edit.custom_minimum_size.x = SaUI.px(140)
    start_choice = SaMake.choice(box, "NewDockerStart", starts())
    start_choice.ask_for_its_words()
    start_choice.tooltip_text = tr("What the docker starts with: nothing, or what another docker holds.")
    make_button = SaMake.button(box, "NewDockerMake", tr("Create"))
    name_edit.text_changed.connect(_on_name_changed)
    name_edit.text_submitted.connect(_on_name_submitted)
    make_button.pressed.connect(make_from_row)
    _show_makeable()
    var row := rows.custom(tr("New docker"), box).named(FIRST_ROW)
    row.explain(
        tr(
            (
                "A docker of your own, empty or starting with the parts another docker holds, in its order "
                + "and with its hidden parts hidden. Create opens it, and its line joins the dockers' above."
            )
        )
    )
    row.words(tr("Fork Copy Empty Custom Composed Make Create"))


## What the docker can start from: Empty, then every docker by its title, in
## the order their lines are drawn.
func starts() -> Array:
    var out: Array = [{"id": EMPTY, "label": tr("Empty")}]
    for entry: Dictionary in SaDockersPage.dockers():
        out.append({"id": String(entry["id"]), "label": tr(String(entry["title"]))})
    return out


## The Delete a composed docker's line carries in *buttons*, after its
## Elements…. The question goes up under *host*.
func delete_button(buttons: HBoxContainer, category: String, title: String, host: Node) -> Button:
    var tip := tr("Delete the %s docker. You will be asked first.") % title
    var button := SaMake.button(buttons, "Delete_%s" % category, tr("Delete"), tip)
    button.pressed.connect(ask_to_delete.bind(host, StringName(category)))
    return button


## What the row makes: its name and its start, refused while Make is dimmed.
## The empty id when nothing was made.
func make_from_row() -> StringName:
    if make_button == null or make_button.disabled:
        return &""
    var start: Variant = start_choice.selected_value()
    return make(name_edit.text, String(start) if start != null else EMPTY)


## Makes a docker called *docker_name* starting from *start*, a docker's
## category or [constant EMPTY], opens it and says the page changed. Its id, or
## the empty id when there is no library or the name is empty or taken.
func make(docker_name: String, start: String) -> StringName:
    var held := _library()
    var named := docker_name.strip_edges()
    if held == null or not name_free(named):
        return &""
    var docker_id := held.make(named, fork_of(start))
    _open(docker_id)
    changed.emit()
    return docker_id


## What a docker starting from *start* holds: nothing for [constant EMPTY],
## what a docker of your own holds for one, and otherwise the placeable
## elements of *start* in its order now, each hidden where it is hidden there.
func fork_of(start: String) -> Array:
    var out: Array = []
    if start.is_empty():
        return out
    if SaComposedDockers.is_composed(start):
        var held := _library()
        return held.elements_of(StringName(start)) if held != null else out
    for element: Variant in SaSettings.get_layout_order(start):
        var named := String(element)
        if SaSettings.is_placeable(start, named):
            out.append({"category": start, "element": named, "visible": SaSettings.get_element_visible(start, named)})
    return out


## Whether *docker_name* is free for a new docker: not empty, and no docker's
## title, the bar's included, nor any docker's of the library, in any case.
func name_free(docker_name: String) -> bool:
    var named := docker_name.strip_edges()
    if named.is_empty():
        return false
    var taken: Array[String] = []
    for entry: Dictionary in SaSettings.reorderable_categories():
        taken.append(String(entry["title"]))
        taken.append(tr(String(entry["title"])))
    var held := _library()
    if held != null:
        for docker: Dictionary in held.list():
            taken.append(String(docker["name"]))
    for title: String in taken:
        if title.nocasecmp_to(named) == 0:
            return false
    return true


## Puts up the question before *docker_id* is forgotten, under *host*, the
## page, as the Keyboard Shortcuts page puts its own up, or answers the one
## already up.
func ask_to_delete(host: Node, docker_id: StringName) -> SaMessage:
    if question != null and is_instance_valid(question) and question.visible:
        return question
    var held := _library()
    if held == null or not held.has(docker_id):
        return null
    var called := held.name_of(docker_id)
    question = SaMessage.confirm(
        host,
        tr("Delete %s") % called,
        (
            tr("Deletes the %s docker from every layout and closes its window.") % called
            + " "
            + tr("What it held stays in the dockers it came from.")
        ),
        PackedStringArray([tr("Cancel"), tr("Delete")]),
        _on_delete_answered.bind(docker_id),
        ANSWER_CANCEL,
        ANSWER_CANCEL
    )
    return question


## Forgets *docker_id*, frees its window and says the page changed. False for
## an id the library does not hold.
func forget(docker_id: StringName) -> bool:
    var held := _library()
    if held == null or not held.delete(docker_id):
        return false
    changed.emit()
    return true


## The row for `{"layout_rows": {}}`: where its three controls stand, what the
## field and the dropdown read, and whether Make is dimmed.
func describe(origin: Vector2, seen: Rect2) -> Array[String]:
    if make_button == null:
        return []
    var out: Array[String] = []
    var parts: Array[String] = []
    for pair: Array in [["name", name_edit], ["start", start_choice], ["make", make_button]]:
        var at := origin + (pair[1] as Control).get_global_rect().get_center()
        parts.append("%s=(%4d, %4d)%s" % [pair[0], at.x, at.y, "" if SaLayoutPage.reachable(at, seen) else " UNREACHABLE"])
    out.append("  %-18s %s" % [tr("New docker"), " ".join(parts)])
    var says := (
        "      name '%s', start '%s', Make %s" % [name_edit.text, start_choice.text, "dimmed" if make_button.disabled else "live"]
    )
    out.append(says)
    return out


## Whether *spec* is this section's: a name to type, a start to pick, Make to
## press, or a line's Delete.
static func drives(spec: Dictionary) -> bool:
    for key: String in ["name", "start", "make", "delete"]:
        if spec.has(key):
            return true
    return false


## Types the name, picks the start and presses Make, in that order and as far
## as *spec* asks, `{"name": "Mine", "start": "Empty", "make": true}`, or
## presses the Delete on a line named by title or category, `{"delete":
## "Mine"}`, *lines* being the page's lines by key.
##
## The name is typed a key at a time into the field, which takes the keyboard
## first, as a click on it gives it, and the keys go into the Preferences
## window, since a key pushed at the root carries no point and reaches the main
## window instead. The start is the dropdown's row pressed by its words, which
## is what `SaChoiceButton.pick_row` does for a hand, since a press on the
## dropdown opens a list no coordinate reaches. Make and Delete are clicks.
func drive(tree: SceneTree, origin: Vector2, spec: Dictionary, lines: Dictionary) -> String:
    if make_button == null:
        return "SaCapture: layout_gesture found no New docker row"
    var said: Array[String] = []
    if spec.has("name"):
        said.append(_type(String(spec["name"])))
    if spec.has("start"):
        var wanted := String(spec["start"])
        if not start_choice.pick_row(_start_label(wanted)):
            var offered := ", ".join(start_choice.choice_labels())
            return "SaCapture: layout_gesture found no start '%s', it offers %s" % [wanted, offered]
        said.append("picked '%s'" % start_choice.text)
    if bool(spec.get("make", false)):
        if make_button.disabled:
            return "SaCapture: layout_gesture %s, and Make is dimmed, %s" % [", ".join(said), make_button.tooltip_text]
        said.append(SaLayoutPage.click(tree, origin, make_button, "Make").trim_prefix("SaCapture: layout_gesture "))
    if spec.has("delete"):
        var wanted := String(spec["delete"])
        var button: Button = null
        for line: Dictionary in lines.values():
            if wanted == String(line["title"]) or wanted == String(line["category"]):
                button = line.get("delete") as Button
        if button == null:
            return "SaCapture: layout_gesture found no docker of your own called '%s' to delete" % wanted
        said.append(SaLayoutPage.click(tree, origin, button, "Delete on '%s'" % wanted).trim_prefix("SaCapture: layout_gesture "))
    return "SaCapture: layout_gesture %s" % ", ".join(said)


## The words of the start *wanted* names, by its words or by its category.
func _start_label(wanted: String) -> String:
    var values := start_choice.choice_values()
    var labels := start_choice.choice_labels()
    var at := values.find(wanted)
    return labels[at] if at >= 0 else wanted


func _type(text: String) -> String:
    if not name_edit.is_inside_tree():
        return "found the name field in no window"
    var window := name_edit.get_window()
    name_edit.grab_focus()
    name_edit.edit()
    name_edit.select_all()
    for i in text.length():
        for pressed: bool in [true, false]:
            var event := InputEventKey.new()
            event.keycode = OS.find_keycode_from_string(text[i].to_upper())
            event.physical_keycode = event.keycode
            event.unicode = text.unicode_at(i)
            event.pressed = pressed
            window.push_input(event, true)
    # The field says text_changed a frame late, so Make is judged here as well.
    _show_makeable()
    var said := "typed '%s', the field reads '%s'" % [text, name_edit.text]
    if name_edit.text != text:
        var owner := window.gui_get_focus_owner()
        said += ", the keys going to %s" % (String(owner.get_path()) if owner != null else "nothing")
    return said


## The library a press makes in.
func _library() -> SaComposedDockers:
    return _given if _given != null else SaComposedDockers.app


## Dims Make while there is nothing to make, and says why on hover.
func _show_makeable() -> void:
    if make_button == null:
        return
    var available := name_free(name_edit.text)
    make_button.disabled = _library() == null or not available
    if name_edit.text.strip_edges().is_empty():
        make_button.tooltip_text = tr("Name the docker first.")
    elif not available:
        make_button.tooltip_text = tr("A docker is already called that.")
    else:
        make_button.tooltip_text = tr("Create the docker and open it.")


func _on_name_changed(_text: String) -> void:
    _show_makeable()


func _on_name_submitted(_text: String) -> void:
    make_from_row()


func _on_delete_answered(answer: int, docker_id: StringName) -> void:
    question = null
    if answer == ANSWER_DELETE:
        forget(docker_id)


## Shows the window of *docker_id* through the docker manager, when the main
## scene has one and the window is built and hidden.
func _open(docker_id: StringName) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("dockers" in main_node):
        return
    var dockers: Object = main_node.get("dockers")
    if dockers == null or not dockers.has_method("toggle_docker_by_id") or not dockers.has_method("registered_docker_node"):
        return
    var window := dockers.call("registered_docker_node", docker_id) as Window
    if window != null and not window.visible:
        dockers.call("toggle_docker_by_id", docker_id)
