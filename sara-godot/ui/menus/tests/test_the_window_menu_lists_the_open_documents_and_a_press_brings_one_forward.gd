## The Window menu lists the open documents and a press on a
## row brings that document forward, the tab bar following.
##
## The documents are held the way the document-tabs suite holds them, a first view built
## from `render/main_canvas.gd` under a host that stands in for main and the
## `SaDocumentTabs` over both. The menu is seated over those tabs, where the
## app's finds them in the scene. The scenario
## `the-window-menu-lists-the-open-documents-and-a-press-brings-one-forward.json`
## reads the same in the app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ViewScript := preload("res://render/main_canvas.gd")


## A Window menu handed its document tabs, where the app's finds them in the
## scene.
class SeatedWindowMenu:
    extends SaWindowMenu

    var seated: SaDocumentTabs

    func _init(menu_popup: SaChoicePopup, tabs: SaDocumentTabs) -> void:
        super(menu_popup)
        seated = tabs

    func _document_tabs() -> SaDocumentTabs:
        return seated


var _documents: SaDocuments = null
var _host: Node = null
var _first: Control = null
var _tabs: SaDocumentTabs = null
var _popup: SaChoicePopup = null
var _was_embedding := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U524Host"
    EventBus.add_child(_host)
    _first = ViewScript.new()
    _host.add_child(_first)
    _documents.add(_first.get("surface") as SaSurface)
    _tabs = SaDocumentTabs.new(_host, _documents, _first)
    _host.add_child(_tabs)
    _popup = SaChoicePopup.new()


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    _popup.free()
    _host.free()
    _host = null
    _first = null
    _tabs = null
    _documents = null
    _popup = null
    SaColors.follow(null)


func _document_rows() -> Array[StringName]:
    var rows: Array[StringName] = []
    for row_id: StringName in _popup.row_ids():
        if String(row_id).begins_with(SaWindowMenu.TAB_PREFIX):
            rows.append(row_id)
    return rows


func test_one_document_open_is_listed_only_under_the_krita_profile() -> void:
    var was := SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = "default"
    var menu := SeatedWindowMenu.new(_popup, _tabs)
    menu.populate()
    assert_eq(_document_rows().size(), 0, "One document open puts no document row in the Window menu, as it shows no tab bar")
    SaSettings.shortcuts_profile = SaWindowMenu.KRITA_PROFILE
    menu.populate()
    var rows := _document_rows()
    assert_eq(rows, [&"tab_0"] as Array[StringName], "Under the Krita profile the one document is listed, as Krita lists it")
    assert_true(_popup.is_checked(&"tab_0"), "and ticked, being in front")
    SaSettings.shortcuts_profile = was


func test_a_press_on_the_document_behind_brings_it_forward_and_the_tab_bar_follows() -> void:
    var first := _documents.front
    var second := _tabs.add_document()
    first.get_document().modified = true
    var menu := SeatedWindowMenu.new(_popup, _tabs)
    menu.populate()

    assert_eq(_document_rows(), [&"tab_0", &"tab_1"] as Array[StringName], "A row for each open document, in tab order")
    var labels: Array[String] = []
    for row_id in _document_rows():
        labels.append(_popup.label_button(row_id).text)
    assert_eq(labels, _tabs.bar.tab_texts(), "each named as its tab is named")
    assert_eq(labels, ["Untitled*", "Untitled"] as Array[String], "the modified one with its star")
    assert_false(_popup.is_checked(&"tab_0"), "The one behind is not ticked")
    assert_true(_popup.is_checked(&"tab_1"), "and the one in front is")

    _popup.visible = true
    assert_true(_popup.press_row(&"tab_0"), "The row of the one behind is there to press")
    assert_eq(_documents.front, first, "The press brings that document forward")
    assert_false(_popup.visible, "and closes the list")
    assert_eq(_tabs.bar.front, first, "The tab bar follows")
    var first_tab := _tabs.bar.tabs.get_child(0).get_node("Name") as Button
    var second_tab := _tabs.bar.tabs.get_child(1).get_node("Name") as Button
    assert_true(first_tab.button_pressed, "with the first tab pressed")
    assert_false(second_tab.button_pressed, "and the second let go")
    assert_true(_first.visible, "The first document's view is shown")
    assert_false(_tabs.views[1].visible, "and the second's hidden")
    assert_eq(_documents.surfaces, [first, second] as Array[SaSurface], "The order of the tabs is as it was")

    menu.populate()
    assert_true(_popup.is_checked(&"tab_0"), "The list opened anew ticks the new front")
    assert_false(_popup.is_checked(&"tab_1"), "and not the one it left")
