## The Window menu: fullscreen, secondary workspaces on other monitors, the way
## back, and the dockers, under a submenu for each kind, with the named layouts
## they arrange.
##
## **The dockers are in here rather than under a Dockers button of their own**.
## The rows are built by `MainDockers`, which owns the registry they come from,
## and this menu asks it to append them: the bar still does not learn what a
## docker is, and `MainDockers` does not build a menu of its own.
##
## **The three command rows' ids are their own range, six hundred**. This popup now holds a
## second family of rows, the docker ones, which are keyed `docker_0` upwards and
## are pressed by number from a scenario. Small ids would have put Fullscreen and
## the toolbox on the same number, so the range is free and reads as this menu's
## own the way View's teens and Layer's four hundreds do.
##
## **A docker row closes the menu once the docker has been toggled**. A painter
## picking a docker wants the window, as in every menu of Photoshop, and the
## ticks of the other menus keep their lists open. The close is this menu's and
## not the one `MainDockers` makes, so it listens to the same `marked` after the dockers
## have answered it, which the order of the two connections guarantees.
##
## **The open documents follow the menu's own rows**, as Krita's Window menu
## lists them, one row each in tab order, named as its tab is named, the front
## one ticked. A press brings that document forward through
## `SaDocumentTabs.bring_forward`, the call a click on its tab makes, and closes
## the list. The rows are keyed `tab_<index>` the way the docker rows are keyed,
## so a scenario presses one by name. The section shows from two documents up,
## when the tab bar does, so the menu and the bar agree on when Sara has more
## than one painting to walk between. Under the Krita shortcut profile it shows
## a single document too, since Krita lists one, and a painter who set Sara up
## like Krita looks for the paintings where Krita keeps them.
class_name SaWindowMenu
extends SaMenu

const ID_NEW_SECONDARY := 600
const ID_GATHER_DOCKERS := 601
const ID_FULLSCREEN := 602

## What a document's row id starts with, its index in tab order after it.
const TAB_PREFIX := "tab_"

## The shortcut profile under which a single open document is listed too.
const KRITA_PROFILE := "Krita"


func _add_items() -> void:
    add_commands(
        [
            [ID_FULLSCREEN, &"window_fullscreen"],
            LINE,
            [ID_NEW_SECONDARY, &"window_new_secondary"],
            LINE,
            [ID_GATHER_DOCKERS, &"window_gather_dockers"],
        ]
    )
    _add_document_rows()
    if not popup.marked.is_connected(_after_a_row_of_its_own):
        popup.marked.connect(_after_a_row_of_its_own)
    var dockers := _main_dockers()
    if dockers == null:
        # A bar built on its own, which is what the suites build, has no app
        # around it, and then the section is absent rather than empty: a heading
        # with nothing under it is a menu telling a painter about a hole.
        return
    add_separator()
    add_heading(tr("Dockers"))
    # Connected after the dockers' own answer, so the docker is toggled before
    # the list goes. The rows' own handler is connected on the first build,
    # before the dockers' is, so it is moved behind them here once, on the
    # menu's list and on each submenu's.
    if popup.marked.is_connected(_after_a_row_of_its_own):
        popup.marked.disconnect(_after_a_row_of_its_own)
    dockers.append_grouped_rows(self)
    popup.marked.connect(_after_a_row_of_its_own)
    for at: int in MainDockers.KINDS.size():
        var list := group_list(popup, MainDockers.FIRST_KIND_ROW + at)
        if list != null and not list.marked.is_connected(_after_a_row_of_its_own):
            list.marked.connect(_after_a_row_of_its_own)


## A docker row's command, the toggle its chord runs, where one is registered,
## so a right click on the row can keep it or bind it. The row ids are
## `docker_<index>` into the dockers' table, and a layout row has none.
func row_command(row_id: StringName) -> StringName:
    var text := String(row_id)
    var dockers := _main_dockers()
    if not text.begins_with("docker_") or dockers == null:
        return super(row_id)
    var config := dockers.get_docker_config()
    var index := int(text.trim_prefix("docker_"))
    var action := StringName(config[index].get("shortcut", "")) if index >= 0 and index < config.size() else &""
    return action if commands != null and commands.has(action) else &""


## A press on a document's row brings that document forward and closes the
## list. A press on a docker's row or on Focus Mode, which `MainDockers` has
## answered already, closes it too. The layouts' rows close it on their own, being
## command rows, and a tick of this menu's own, Fullscreen, keeps its old way.
func _after_a_row_of_its_own(row_id: StringName, _on: bool) -> void:
    if String(row_id).begins_with(TAB_PREFIX):
        _bring_forward(row_id)
        popup.hide()
    elif String(row_id).begins_with("docker_") or row_id == MainDockers.FOCUS_MODE_ROW:
        # The kind's submenu the row is on goes first, so no list is left
        # standing beside a menu that closed.
        popup.close_child()
        popup.hide()


## One row per open document in tab order, the front one ticked, under a line.
## None while fewer than two are open, when the tab bar hides too, unless the
## Krita profile is in force.
func _add_document_rows() -> void:
    var tabs := _document_tabs()
    if tabs == null or tabs.documents == null or tabs.documents.surfaces.is_empty():
        return
    if tabs.documents.surfaces.size() < 2 and SaSettings.shortcuts_profile != KRITA_PROFILE:
        return
    add_separator()
    var open := tabs.documents.surfaces
    for at in open.size():
        var surface := open[at]
        var shown := SaDocumentTabs.tab_text(surface.get_document())
        popup.add_row(StringName(TAB_PREFIX + str(at)), shown, true, surface == tabs.documents.front)


## Brings forward the document whose row is *row_id*, if it is still open.
func _bring_forward(row_id: StringName) -> void:
    var tabs := _document_tabs()
    if tabs == null or tabs.documents == null:
        return
    var at := int(String(row_id).trim_prefix(TAB_PREFIX))
    var open := tabs.documents.surfaces
    if at >= 0 and at < open.size():
        tabs.bring_forward(open[at])


## The tabs that hold the open documents, or null for a bar outside the app.
func _document_tabs() -> SaDocumentTabs:
    return SaDocumentTabs.in_tree(popup.get_tree()) if in_tree() else null


## The node that owns the docker registry, or null when there is none to ask.
##
## A bar built on its own is not inside a tree and has no scene above it, which
## is the whole of the null cases here.
func _main_dockers() -> MainDockers:
    var scene := main_scene()
    if scene == null:
        return null
    return scene.find_child("MainDockers", true, false) as MainDockers
