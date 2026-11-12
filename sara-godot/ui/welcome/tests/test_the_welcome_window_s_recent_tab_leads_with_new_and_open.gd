## The welcome window's Recent tab leads with New and Open.
##
## A first-time painter looks for where to start, and New and Open small at
## the window's foot under a Recent tab of one sentence did not say it. They
## are two large actions across the top of the tab, an empty list offers
## "Open a file" in the sentence's place, and the foot keeps only the switch.
##
## The window is opened in an embedded screen and laid out by hand, the way
## `test_the_welcome_band_gives_way_in_a_short_window.gd` opens it, so the tab
## bar and the actions have the heights a frame would give them. How it looks
## in the running app is
## `scenarios/the-welcome-window-s-recent-tab-leads-with-new-and-open.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_embedding: bool = true
var _saved_recent: Array = []
var _host: Node = null
var _asked_new: int = 0


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "RecentTabHost"
    EventBus.add_child(_host)
    _asked_new = 0
    EventBus.new_document_requested.connect(_on_new_asked)


func after_each() -> void:
    EventBus.new_document_requested.disconnect(_on_new_asked)
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


func _on_new_asked() -> void:
    _asked_new += 1


## On a fresh profile, at both ends of the Font size, New and Open are the
## first row of the Recent tab, above the recovery row and the list, and each
## stands at least as tall as the window's tab bar.
func test_new_and_open_lead_the_recent_tab_as_tall_as_the_tab_bar() -> void:
    for font_scale: float in [1.0, 1.5]:
        SaUI.user_scale = 1.0
        SaUI.user_font_scale = font_scale
        SaUI.init_global_theme(null)
        var window := _opened(Vector2i(1280, 900))
        var pane := window.recent_pane
        assert_eq(window.tabs.current_tab, window.tabs.get_tab_idx_from_control(pane), "the window opens on Recent")
        var actions := pane.find_child("Actions", false, false) as Control
        assert_eq(actions.get_index(), 0, "the actions are the pane's first row")
        var top := actions.get_global_rect().end.y
        if pane.recovery_row.is_visible_in_tree() and pane.recovery_row.size.y > 0.0:
            assert_true(top <= pane.recovery_row.get_global_rect().position.y, "above the recovery row")
        assert_true(top <= pane.recent_grid.get_global_rect().position.y, "and above the list")
        var bar := window.tabs.get_tab_bar().size.y
        assert_true(bar > 0.0, "the tab bar has its height")
        for button: Button in [pane.new_button, pane.open_button]:
            assert_true(actions.is_ancestor_of(button), "%s stands in that row" % button.name)
            var tall := "%s is %.0f tall, the tab bar %.0f, at Font size %.1f" % [button.name, button.size.y, bar, font_scale]
            assert_true(button.size.y >= bar, tall)
            assert_true(button.is_visible_in_tree(), "%s shows" % button.name)
        var widths := pane.new_button.size.x + pane.open_button.size.x
        assert_true(widths >= actions.size.x * 0.9, "and the two share the pane's width between them")
        _host.free()
        _host = Node.new()
        _host.name = "RecentTabHost"
        EventBus.add_child(_host)


## The foot keeps the switch and holds no New or Open of its own any more, and
## the window holds exactly one of each.
func test_the_foot_keeps_only_what_else_it_held() -> void:
    var window := SaWelcomeWindow.new()
    var foot := window.find_child("Buttons", true, false) as Control
    assert_not_null(foot, "the foot row is still there")
    assert_null(foot.find_child("NewButton", true, false), "with no New in it")
    assert_null(foot.find_child("OpenButton", true, false), "and no Open")
    assert_not_null(foot.find_child("ShowAtStart", true, false), "and the switch kept")
    assert_eq(window.find_children("NewButton", "", true, false).size(), 1, "one New in the window")
    assert_eq(window.find_children("OpenButton", "", true, false).size(), 1, "one Open in the window")
    window.free()


## Each action does what its foot button did: New asks the bus for the New
## Document dialog the File menu opens, Open and Open a file run the window's
## own open through the document flow, and all three wait for the boot.
func test_each_action_does_what_its_foot_button_did() -> void:
    var window := SaWelcomeWindow.new()
    var pane := window.recent_pane
    pane.new_button.pressed.emit()
    assert_eq(_asked_new, 1, "New asks for a new document down the bus")
    assert_eq(window.default_button, pane.new_button, "and is the button Enter presses")
    assert_true(pane.open_button.pressed.is_connected(window._on_open_pressed), "Open runs the window's open")
    assert_true(pane.open_a_file.pressed.is_connected(window._on_open_pressed), "and so does Open a file")
    assert_eq(pane.open_button.text, "Open", "Open says what it does")
    assert_eq(pane.open_a_file.text, "Open a file", "and so does the empty list's action")
    window.free()

    var booting := SaWelcomeWindow.new(true)
    var held: Array[Button] = [booting.recent_pane.new_button, booting.recent_pane.open_button, booting.recent_pane.open_a_file]
    for button in held:
        assert_true(button.disabled, "%s waits for the boot" % button.name)
    EventBus.boot_finished.emit()
    for button in held:
        assert_false(button.disabled, "%s works once Sara is whole" % button.name)
    booting.free()


## An empty list puts Open a file where its sentence stood, with the sentence
## under it, and a list with a document in it hides both.
func test_an_empty_list_offers_open_a_file_in_the_sentence_s_place() -> void:
    var pane := WelcomeRecentPane.new()
    var cards := pane.find_child("RecentCards", true, false) as WelcomeRecentGrid
    var empty := cards.empty_line
    assert_eq(empty.name, &"RecentEmpty", "the block beside the cards is the empty list's")
    assert_true(empty.visible, "and shows on a fresh profile")
    assert_eq(pane.open_a_file.get_parent(), empty, "Open a file stands in it")
    var hint := empty.find_child("RecentEmptyHint", false, false) as Label
    assert_true(pane.open_a_file.get_index() < hint.get_index(), "above the sentence")
    var path := SaDataRoot.path("recent-tab-a-recent-document.sad")
    SaSettings.add_recent_file(path)
    cards.rebuild()
    assert_false(empty.visible, "a document in the list hides the offer")
    assert_true(pane.new_button.visible and pane.open_button.visible, "while New and Open stay at the top")
    SaSettings.remove_recent_file(path)
    pane.free()


func _opened(logical: Vector2i) -> SaWelcomeWindow:
    var window := SaWelcomeWindow.new()
    var screen := SubViewport.new()
    screen.size = logical
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    window.popup_centered()
    _settle(window)
    window.fit_opening_size()
    _settle(window)
    return window


## Lays *window* out the way a drawn frame would, the dialog suite's way.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()
