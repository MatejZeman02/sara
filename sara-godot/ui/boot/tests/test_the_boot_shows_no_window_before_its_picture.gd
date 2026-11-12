## The boot shows no window before its picture, three faults each read off
## frames shot about every 35 ms:
##
## - "Embedded, the welcome window stands under the veil from Ready until the
##   veil clears." The cover drew the window's picture inside the control it
##   fades, so the picture faded too, over the same window under the blur.
## - "With the subwindows off, the welcome window first shows blank at the
##   screen's top left, over the splash." It joined the tree visible, which
##   makes the OS window there, before `popup_centered` moved it.
## - "With the subwindows off, the let-out dockers come up over the blur." The
##   cover is a layer of the main window and a let-out docker is a window of
##   the OS above it, so the layout store's show put it over the blur.
##
## Each is held here on the pieces a boot puts up, the cover, the welcome
## window and a docker, in the order `SaBoot` and `Main` put them up. A window
## that maps one of the OS's own hangs the run, so a docker stands let out
## only while it is hidden: the root embeds nothing while the layout is
## restored behind the cover, and embeds again before the cover's `gone`
## shows it.
extends "res://tests/test_framework.gd"


## The layout store with nothing written and nothing settled, so a restore
## here writes no file and starts no settle loop, and the dockers' shows on
## `gone` are counted.
class StubStore:
    extends DockerLayoutStore

    var reapplied: Array[String] = []

    func save(_by_painter: bool = false) -> void:
        pass

    func reapply_deferred(_win: Window, section: String) -> void:
        reapplied.append(section)

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


const DOCKERS: Array[StringName] = [&"D14DockerA", &"D14DockerB"]

var _host: Node = null
var _previous_embedding: bool = true
var _cover: SaBootCover = null
var _layout_file := ""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "D14Host"
    EventBus.add_child(_host)
    _layout_file = SaDataRoot.path("test_d14_docker_layout.cfg")
    DirAccess.remove_absolute(_layout_file)
    _cover = _new_cover(false)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    DirAccess.remove_absolute(_layout_file)
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


func test_the_welcome_windows_picture_stays_whole_while_the_blur_fades() -> void:
    var welcome := _welcome()
    _cover.reach(&"boot_finished")
    assert_not_null(_cover._tween, "Ready starts the fade")
    _cover._tween.custom_step(SaBootCover.FIT_WAIT_SEC + SaBootCover.FADE_SEC * 0.5)
    assert_almost_eq(_cover._root.modulate.a, 0.5, 0.01, "Halfway through the fade the blur is half gone")
    assert_almost_eq(_alpha_of(_cover._lifted), 1.0, 0.0001, "and the welcome window's picture over it is whole")
    assert_eq(SaBootCover.above(_stack()), [welcome] as Array[Window], "and still drawn, so nothing veils the window")
    assert_true(_cover.is_inside_tree(), "The cover stands until the fade is over")
    _cover._tween.custom_step(SaBootCover.FADE_SEC)
    assert_false(_cover.is_inside_tree(), "and leaves at its end, the engine's own picture of the window taking its place")


func test_a_cover_held_halfway_stops_at_half_and_stays() -> void:
    _cover.free()
    _cover = _new_cover(true, 0.0)
    _welcome()
    var heard: Array[bool] = []
    _cover.gone.connect(func() -> void: heard.append(true))
    _cover.reach(&"boot_finished")
    _cover._tween.custom_step(SaBootCover.FIT_WAIT_SEC + SaBootCover.FADE_SEC * 4.0)
    assert_almost_eq(_cover._root.modulate.a, 0.5, 0.01, "Held halfway, the fade stops at half even in a run with no fade")
    assert_almost_eq(_alpha_of(_cover._lifted), 1.0, 0.0001, "with the welcome window whole over it")
    assert_true(_cover.is_inside_tree(), "and the cover stays for the shot")
    assert_eq(heard, [] as Array[bool], "saying nothing of leaving")


func test_the_welcome_window_is_hidden_until_popup_centered_places_it() -> void:
    var welcome := SaWelcomeWindow.new(true)
    var seen: Array = []
    welcome.tree_entered.connect(func() -> void: seen.append(["entered", welcome.visible, welcome.position]))
    welcome.visibility_changed.connect(
        func() -> void: seen.append(["shown" if welcome.visible else "hidden", welcome.visible, welcome.position])
    )
    SaBoot.put_up(welcome, _host)
    assert_eq(seen.size(), 2, "The window enters the tree and changes its visibility once")
    assert_eq(seen[0][0], "entered", "It enters first")
    assert_false(seen[0][1], "hidden, so no OS window is made at the screen's top left")
    assert_eq(seen[1][0], "shown", "and is then shown")
    assert_eq(seen[1][2], welcome.position, "at the place it stays")
    var host_size := Vector2i(welcome.get_parent().get_viewport().get_visible_rect().size)
    @warning_ignore("integer_division")
    var centred := (host_size - welcome.size) / 2
    assert_eq(welcome.position, centred, "which is the centre `popup_centered` gives it")
    assert_true(welcome.position != Vector2i.ZERO, "and not the corner a window joins the tree at")


func test_with_subwindows_off_no_docker_is_shown_before_the_cover_is_gone() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = false
    var store := StubStore.new()
    store.path = _layout_file
    var dockers := _dockers(store)
    var windows := _windows(dockers)
    dockers.load_docker_layout()
    for window in windows:
        assert_false(window.is_embedded(), "%s is a window of its own" % window.name)
        assert_true(SaBootCover.holds_back(window), "which the cover holds back")
        assert_false(window.visible, "so the layout store placed it and left it hidden")
    assert_true(bool(store.value_for(String(DOCKERS[0]), "visible", false)), "though the layout opens it")
    # The restore places each docker once of its own accord.
    store.reapplied.clear()

    dockers.boot_finished()
    _cover.reach(&"boot_finished")
    _cover._tween.custom_step(SaBootCover.FIT_WAIT_SEC + SaBootCover.FADE_SEC * 0.5)
    for window in windows:
        assert_false(window.visible, "Halfway through the fade %s is still hidden" % window.name)
    assert_eq(store.reapplied, [] as Array[String], "and not placed again yet")

    # Embedded again before the dockers are shown, so the shows on `gone` map
    # no window of the OS, which would hang the run. The hold is a group on
    # each window and does not ask the root again.
    tree.root.gui_embed_subwindows = true
    var welcome := _welcome()
    welcome.cascade_off_the_open_dialogs()
    _cover._tween.custom_step(SaBootCover.FADE_SEC)
    assert_false(_cover.is_inside_tree(), "The fade is over and the cover gone")
    for window in windows:
        assert_true(window.visible, "and %s, which the layout opens, is shown" % window.name)
        assert_false(SaBootCover.holds_back(window), "and held no longer, so the next show goes through")
    assert_eq(store.reapplied, [String(DOCKERS[0]), String(DOCKERS[1])], "each placed where the layout keeps it")
    assert_eq(_stack()[-1], welcome, "and the welcome window comes forward over the dockers shown after it")


func test_with_subwindows_embedded_the_dockers_are_shown_under_the_cover() -> void:
    var store := StubStore.new()
    store.path = _layout_file
    var dockers := _dockers(store)
    var windows := _windows(dockers)
    dockers.load_docker_layout()
    for window in windows:
        assert_true(window.is_embedded(), "%s is drawn under the cover's layer" % window.name)
        assert_false(SaBootCover.holds_back(window), "so the cover does not hold it back")
        assert_true(window.visible, "and the layout store shows it as it restores")


func test_a_cover_that_is_leaving_holds_nothing_back_again() -> void:
    assert_eq(SaBootCover.in_tree(_host), _cover, "A standing cover is the tree's")
    var asked: Array = []
    _cover.gone.connect(func() -> void: asked.append(SaBootCover.in_tree(_host)))
    _cover.reach(&"boot_finished")
    _cover._tween.custom_step(SaBootCover.FIT_WAIT_SEC + SaBootCover.FADE_SEC * 2.0)
    assert_eq(asked, [null], "While it says it is gone it is no longer the tree's, so a restore heard then holds nothing back")
    assert_null(SaBootCover.in_tree(_host), "and after it there is none")


# --- Helpers --------------------------------------------------------------------


## A cover as `Main` builds one, with no saved picture.
func _new_cover(halfway: bool, fade_sec: float = SaBootCover.FADE_SEC) -> SaBootCover:
    var no_picture := SaDataRoot.path("test_d14_no_last_session.webp")
    var cover := SaBootCover.new(Vector2i(1280, 800), no_picture, true, fade_sec, halfway)
    _host.add_child(cover)
    return cover


## The welcome window as `SaBoot` puts it up, built for a boot still going.
func _welcome() -> SaWelcomeWindow:
    var welcome := SaWelcomeWindow.new(true)
    SaBoot.put_up(welcome, _host)
    return welcome


## Two registered dockers, each a hidden window under the host, and the dockers
## built over them with *store*.
func _dockers(store: DockerLayoutStore) -> MainDockers:
    var registries := SaRegistries.new()
    for id in DOCKERS:
        var win := Window.new()
        win.name = String(id)
        win.visible = false
        win.borderless = true
        win.size = Vector2i(240, 160)
        _host.add_child(win)
        registries.ui.register_docker(id, String(id), func() -> Window: return Window.new())
        registries.ui.set_docker_node(id, win)
    var dockers := MainDockers.new(registries.ui, store)
    _host.add_child(dockers)
    return dockers


func _windows(dockers: MainDockers) -> Array[Window]:
    var found: Array[Window] = []
    for id in DOCKERS:
        found.append(dockers.registered_docker_node(id))
    return found


func _stack() -> Array[Window]:
    var stack: Array[Window] = []
    stack.assign((Engine.get_main_loop() as SceneTree).root.get_embedded_subwindows())
    return stack


## The alpha *item* is drawn at, its own times every canvas item's above it.
func _alpha_of(item: CanvasItem) -> float:
    var alpha := 1.0
    var node: Node = item
    while node is CanvasItem:
        alpha *= (node as CanvasItem).modulate.a
        node = node.get_parent()
    return alpha * item.self_modulate.a
