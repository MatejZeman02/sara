## Escape closes a dialog once no text field holds the keyboard.
##
## Escape is muscle memory for closing a window. So a dialog closes on Escape as its × closes it, a dialog
## with a Cancel answers Cancel, a text field holding the keyboard lets go
## first, and the pop-up palette goes back as a choice popup closes. No docker
## closes, which `ui/shortcuts/tests/test_escape_closes_docker.gd` still holds.
##
## The key reaches a dialog the way the engine hands it on: the window emits
## `window_input`, which the router watches, and then pushes the event into its
## own tree. `_press` does both, so a handler left inside a window that read
## Escape as well would answer a second time and show here.
extends "res://tests/test_framework.gd"

## Opens real windows, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const PALETTE_SECTION: String = "PaletteDocker"
const KNOB := &"n74_suite.knob"

static var scratch_layout_path: String = SaDataRoot.path("test_n74_escape_layout.cfg")

var _host: Node = null
var _router: ShortcutRouter = null
var _was_embedding: bool = false


## A filter with one number, the shape `test_the_filter_editor.gd` brings, so an
## attached record has a value to put back.
class Knob:
    extends SaFilter

    var amount: SaSlider

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.title("Knob")
        ui.preview()
        amount = ui.slider("Amount", 0, 10, 3)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"amount": float(amount.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("amount"):
            amount.value = values["amount"]

    func run(_ctx: SaFilterContext) -> void:
        pass


## A host in the tree with a router watching every window that joins it, wired
## the way `main.gd` wires one and with nothing behind its providers.
##
## Embedding is forced the way `test_prefs_modal.gd` forces it: without it
## `add_child` maps a real OS window and the run blocks until the watchdog.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "EscapeClosesADialogHost"
    EventBus.add_child(_host)
    _router = ShortcutRouter.new()
    _router.name = "EscapeRouter"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return null
    _host.add_child(_router)
    _router.watch_windows(tree)


func after_each() -> void:
    _host.free()
    _host = null
    _router = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    if FileAccess.file_exists(scratch_layout_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_layout_path))


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


## A key the way the engine hands it to *window*: `window_input` first, which
## is where the router hears it, and then the window's own tree.
static func _press(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


## Types *text* into the focused field of *window* one key at a time.
static func _type(window: Window, text: String) -> void:
    for character: String in text:
        var key := InputEventKey.new()
        key.unicode = character.unicode_at(0)
        key.keycode = OS.find_keycode_from_string(character)
        key.pressed = true
        _press(window, key)


func _open(dialog: SaDialogWindow) -> SaDialogWindow:
    _host.add_child(dialog)
    dialog.show()
    return dialog


## The Preferences search box. The first Escape lets the field go and leaves the
## window, which keeps the search bar from losing its window, and only the second
## closes it.
func test_the_first_escape_lets_the_search_go_and_the_second_closes_preferences() -> void:
    var prefs := _open(SaSettingsWindow.new())
    var field := prefs.find_child("PreferencesSearch", true, false) as LineEdit
    assert_not_null(field, "Preferences has its search box")
    field.grab_focus()
    _type(prefs, "gam")
    assert_eq(field.text, "gam", "the letters were typed into the search, not taken as chords")

    _press(prefs, _escape())
    assert_false(field.has_focus(), "The first Escape lets the search go")
    assert_true(prefs.visible, "and Preferences stays open")
    assert_eq(field.text, "gam", "with what was typed still in the box")

    _press(prefs, _escape())
    assert_false(prefs.visible, "The second Escape closes it")


## A filter dialog answers Escape with its Cancel: the preview leaves the
## canvas, nothing is attached, no step is made and the layer is what it was.
func test_escape_cancels_a_filter_dialog_and_leaves_the_layer_unchanged() -> void:
    var easel := Bench.easel(Vector2i(256, 256))
    var document := easel.document
    document.fill_layer(PAINT, document.active_layer)
    Bench.composite(easel)
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var registry := SaFilterRegistry.new()
    registry.register(Bench.threshold(), &"sara-base-modules")
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.watch(registry)
    _host.add_child(window)
    var before := Bench.texel(document.active_layer.get_field(Vector2i.ZERO), Vector2i(100, 100))
    var steps := document.history.step_count()

    window.open_filter(&"sara-base-modules.threshold")
    window.dialog.row(&"level").drive(0.8)
    window.dialog.flush_rerun()
    assert_not_null(easel.compositor.point_preview.for_document(document), "The preview is on the canvas")

    _press(window, _escape())
    assert_false(window.visible, "Escape closes the filter dialog")
    assert_null(window.dialog, "and takes its page down")
    assert_null(easel.compositor.point_preview.for_document(document), "the preview leaves the canvas")
    assert_eq(document.history.step_count(), steps, "no step was made")
    assert_true(document.active_layer.filters.is_empty(), "and nothing was attached")
    Bench.composite(easel)
    var after := Bench.texel(document.active_layer.get_field(Vector2i.ZERO), Vector2i(100, 100))
    assert_true(after.is_equal_approx(before), "The layer is unchanged: %s against %s" % [after, before])

    window.free()
    canvas.free()
    easel.free()


## A number typed into a slider's field is cancelled by the first Escape, not
## committed, and the second closes the window. A router that let the field
## go from `window_input`, before the field could hear the key, would let the
## focus leaving commit what was typed: 0.99 into the Brush Editor's Strength
## once left it at 1 %.
func test_the_first_escape_cancels_a_typed_number_and_the_second_closes() -> void:
    var easel := Bench.easel(Vector2i(128, 128))
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var registry := SaFilterRegistry.new()
    registry.register(Bench.threshold(), &"sara-base-modules")
    var window := SaFilterDialogWindow.new()
    window.target_canvas = canvas
    window.watch(registry)
    _host.add_child(window)
    window.open_filter(&"sara-base-modules.threshold")
    var slider := window.dialog.row(&"level").custom_control as FactorSlider
    var was := slider.value
    slider.start_editing()
    slider._line_edit.text = "0.99"

    _press(window, _escape())
    assert_false(slider._line_edit.visible, "The first Escape closes the field")
    assert_almost_eq(slider.value, was, 1e-6, "and the number typed into it is not taken")
    assert_true(window.visible, "The window stays")
    _press(window, _escape())
    assert_false(window.visible, "and the second Escape closes it")

    window.free()
    canvas.free()
    easel.free()


## The same field in a docker: its own Escape cancels, and the docker stays.
func test_a_slider_field_in_a_docker_cancels_on_escape() -> void:
    var docker := Window.new()
    docker.name = "ADocker"
    _host.add_child(docker)
    var slider := FactorSlider.new()
    docker.add_child(slider)
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 40.0
    slider.start_editing()
    slider._line_edit.text = "99"

    _press(docker, _escape())
    assert_false(slider._line_edit.visible, "Escape closes the field")
    assert_almost_eq(slider.value, 40.0, 1e-6, "and leaves the value where it was")
    assert_true(docker.visible, "and the docker is left open")


## A question answers its Cancel, once, and goes.
func test_escape_answers_a_questions_cancel() -> void:
    var message := SaMessage.new()
    _host.add_child(message)
    var answers: Array[int] = []
    var labels := PackedStringArray(["Save", "Discard", "Cancel"])
    message.ask("Unsaved changes", "Save first?", labels, func(i: int) -> void: answers.append(i))

    _press(message, _escape())
    assert_eq(answers, [2], "Escape is the Cancel answer, given once")
    assert_false(message.visible, "and the question is gone")


## The two windows that once never closed on Escape.
## The browser opens with the keyboard in its search, so the first Escape lets
## that go, by the same rule. The Filters browser is a docker,
## and the layer kind browser is the window its search is in.
func test_escape_closes_the_brush_editor_and_the_filter_browser() -> void:
    var editor := _open(SaBrushEditorWindow.new())
    editor.gui_release_focus()
    _press(editor, _escape())
    assert_false(editor.visible, "Escape closes the Brush Editor")

    var browser := _open(SaLayerKindBrowser.new())
    var search := browser.find_child("BrowserSearch", true, false) as LineEdit
    search.grab_focus()
    _press(browser, _escape())
    assert_true(browser.visible, "The browser's search lets go first")
    _press(browser, _escape())
    assert_false(browser.visible, "and the next Escape closes the browser")


## An attached filter's editor answers Escape with its Cancel too: the value the
## window opened on goes back on the record. Its × alone would only hide it, which
## leaves a live-previewed value on the record with no step to undo.
func test_escape_puts_an_attached_filters_values_back() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var document := easel.document
    var registry := SaFilterRegistry.new()
    registry.register(Knob.new(), &"n74_suite")
    var record := SaFilterOps.new(document).attach(document.active_layer, KNOB, {"amount": 7.0})
    var window := SaFilterEditWindow.new()
    window.watch(registry)
    window.open(record, document)
    window.dialog.row(&"amount").drive(2.0)
    window.dialog.flush_rerun()
    assert_eq(record.parameters, {"amount": 2.0}, "The change is live while the window is open")

    _router.handle_docker_input(_escape(), window)
    assert_eq(record.parameters, {"amount": 7.0}, "Escape puts the value it opened with back")
    assert_false(window.visible, "and closes the editor")

    window.free()
    easel.free()


## The × and Escape are one request, `close_requested`, so whatever a dialog
## does on its × it does on Escape. A held key closes one window and not every
## window behind it, so its repeats are left alone.
func test_the_cross_and_escape_are_one_request_and_a_held_key_is_one() -> void:
    var dialog := _open(SaLayerKindBrowser.new())
    var asked: Array = []
    dialog.close_requested.connect(func() -> void: asked.append(true))
    dialog.gui_release_focus()
    dialog.close_button.pressed.emit()
    assert_eq(asked.size(), 1, "The × asks the window to close")
    dialog.show()
    var held := _escape()
    held.echo = true
    _press(dialog, held)
    assert_true(dialog.visible, "A repeat of a held Escape closes nothing")
    _press(dialog, _escape())
    assert_eq(asked.size(), 2, "and Escape makes the same request")
    assert_false(dialog.visible, "which closes it")


## The palette and a store that knows it, which is what a summon borrows from.
func _summoned_palette() -> Dictionary:
    var win := PaletteDocker.new()
    win.position = Vector2i(1500, 120)
    win.visible = false
    var store := DockerLayoutStore.new()
    store.path = scratch_layout_path
    var config := {"node": win, "id": PALETTE_SECTION, "name": "Pop-up Palette"}
    store.dockers_provider = func() -> Array: return [config]
    store.save(true)
    var summon := DockerSummon.new(store)
    _router.summon = summon
    _router.dockers_provider = func() -> Array[Dictionary]: return [config]
    return {"win": win, "store": store, "summon": summon}


func _free_palette(bench: Dictionary) -> void:
    _router.summon = null
    (bench["summon"] as Node).free()
    (bench["win"] as Node).free()
    (bench["store"] as Node).free()


## The pop-up palette goes back on Escape, as a choice popup closes on it. The
## key arrives in the main window, because a summon takes no focus.
func test_the_pop_up_palette_goes_back_on_escape() -> void:
    var bench := _summoned_palette()
    var win: PaletteDocker = bench["win"]
    var store: DockerLayoutStore = bench["store"]
    assert_true((bench["summon"] as DockerSummon).summon(win, PALETTE_SECTION, Vector2i(700, 500), 10000), "The chord summons it")
    assert_true(win.visible, "and it is up")

    _router.handle_viewport_input(_escape(), null)
    assert_false(win.visible, "Escape sends it back")
    assert_false(store.is_borrowed(PALETTE_SECTION), "and the borrow is over")

    win.visible = true
    _router.handle_viewport_input(_escape(), null)
    assert_true(win.visible, "Opened from the Window menu it is a docker, and Escape closes no docker")

    _free_palette(bench)


## Any other docker out on a summon is a docker, and stays.
func test_another_summoned_docker_stays() -> void:
    var bench := _summoned_palette()
    var layers := Window.new()
    layers.name = "LayersDocker"
    layers.visible = false
    var config := {"node": layers, "id": "LayersDocker", "name": "Layers"}
    var store: DockerLayoutStore = bench["store"]
    store.dockers_provider = func() -> Array: return [config]
    _router.dockers_provider = func() -> Array[Dictionary]: return [config]
    assert_true((bench["summon"] as DockerSummon).summon(layers, "LayersDocker", Vector2i(700, 500), 10000), "Layers is summoned")

    _router.handle_viewport_input(_escape(), null)
    assert_true(layers.visible, "Escape leaves a summoned docker out")
    assert_true(store.is_borrowed("LayersDocker"), "on its borrow")

    (bench["summon"] as DockerSummon).send_back("LayersDocker")
    layers.free()
    _free_palette(bench)
