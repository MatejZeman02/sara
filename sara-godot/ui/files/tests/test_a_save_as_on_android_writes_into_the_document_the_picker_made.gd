## On Android the picker has already made the document a Save
## As writes into, and its `content://` address carries the name as typed or,
## in Downloads, no name at all. A `.sad` put after it, or a question asking to
## put one, names a document that does not exist and the save fails. So the
## address goes to the save as the picker gave it, with nothing asked.
extends "res://tests/test_framework.gd"

const _BARE: String = "content://com.android.externalstorage.documents/document/primary%3APictures%2Fbare"
const _DOWNLOADS: String = "content://com.android.providers.downloads.documents/document/msf%3A1234"
const _PICTURE: String = "content://com.android.externalstorage.documents/document/primary%3APictures%2Fpicture.png"

var _previous_embedding: bool = true
var _flow: SaDocumentFiles = null
var _chosen: Array[String] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _flow = SaDocumentFiles.new()
    EventBus.add_child(_flow)
    _chosen.clear()


func after_each() -> void:
    if _flow != null:
        _flow.free()
        _flow = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func _asked() -> bool:
    for child in _flow.get_children():
        var dialog := child as SaMessage
        if dialog != null and dialog.visible:
            return true
    return false


func _choose(path: String) -> void:
    _flow.choose_save_name(path, func(chosen: String) -> void: _chosen.append(chosen))


func test_a_bare_content_address_is_saved_into_as_it_came() -> void:
    _choose(_BARE)
    assert_eq(_chosen, [_BARE] as Array[String], "the address the picker made is the one written")
    assert_false(_asked(), "and nothing is asked on the way")


func test_a_downloads_address_with_no_name_is_saved_into_as_it_came() -> void:
    _choose(_DOWNLOADS)
    assert_eq(_chosen, [_DOWNLOADS] as Array[String], "a Downloads address is written as it came")
    assert_false(_asked(), "and nothing is asked on the way")


func test_a_content_address_named_as_a_picture_asks_nothing() -> void:
    _choose(_PICTURE)
    assert_eq(_chosen, [_PICTURE] as Array[String], "the picker made the document already, so it is written")
    assert_false(_asked(), "and no question offers a .sad it could not add")
