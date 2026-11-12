## The Flat or Environment button is a `TopMenuBar` element with a view, and the
## bar's own button and a second one built the way a custom docker builds it
## both show and drive the one switch on the canvas's Environment view.
##
## The suite reads the button registered in `TopMenuBar` with a view, builds the
## view a second time as a custom docker does, and finds both showing and
## driving the one state. The button is greyed with its reason on a flat
## document.
##
## The canvas is a real one in a viewport with its Environment view beside it,
## as the main surface has, and since the view composites through the easel
## the suite asks for a GPU.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

var _host: Node = null
var _canvas: SaCanvas = null
var _view: SaEnvironmentView = null
var _was_placeable: bool = false


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _was_placeable = SaSettings.is_placeable(SaTopBarEnvironment.CATEGORY, SaTopBarEnvironment.ELEMENT)
    _host = Node.new()
    _host.name = "EnvironmentButtonTestHost"
    EventBus.add_child(_host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(800, 600)
    _host.add_child(viewport)
    var surface := Control.new()
    surface.size = Vector2(800.0, 600.0)
    viewport.add_child(surface)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(256, 128)
    surface.add_child(_canvas)
    _view = SaEnvironmentView.attach_to(surface, _canvas)


func after_each() -> void:
    if _view != null and _view.on:
        _view.set_on(false)
    if _was_placeable:
        SaTopBarEnvironment.register()
    else:
        SaSettings.unregister_layout_element(SaTopBarEnvironment.CATEGORY, SaTopBarEnvironment.ELEMENT)
    if _host != null:
        _host.free()
        _host = null


## The bar's button, from the same call the top bar makes, and a docker's,
## from the same call a custom docker makes.
func _two_buttons() -> Array[Button]:
    var bar := Control.new()
    _host.add_child(bar)
    var home: Dictionary = SaTopBarEnvironment.home(bar, func() -> SaEnvironmentView: return _view)
    var docker := Control.new()
    _host.add_child(docker)
    var placed := SaSettings.build_element_view(SaTopBarEnvironment.CATEGORY, SaTopBarEnvironment.ELEMENT)
    docker.add_child(placed)
    var out: Array[Button] = [home[SaTopBarEnvironment.ELEMENT], placed as Button]
    return out


## What the button shows this moment, rather than at the next frame.
func _read(button: Button) -> void:
    SaTopBarEnvironment.follower_of(button).sync()


func _make_a_panorama() -> void:
    _canvas.document.projection = SaProjection.new(SaProjection.Equirectangular.new())


func test_the_element_is_on_the_top_bar_with_a_view() -> void:
    var buttons := _two_buttons()
    assert_true(
        SaSettings.is_placeable(SaTopBarEnvironment.CATEGORY, SaTopBarEnvironment.ELEMENT),
        "the button is a TopMenuBar element a custom docker can hold"
    )
    assert_not_null(buttons[0], "the bar has its own button")
    assert_not_null(buttons[1], "the view builds a second button")
    assert_true(buttons[0] != buttons[1], "the second is built fresh, not borrowed from the bar")
    var again := SaSettings.build_element_view(SaTopBarEnvironment.CATEGORY, SaTopBarEnvironment.ELEMENT)
    assert_true(again != buttons[1], "every build is another button")
    again.free()


## "With a shortcut on the Keyboard Shortcuts page": the switch is a command in
## the registry the page lists, in the View category, answering to P, and the
## bar's place for it is the skeleton's own order, at the head of the view's
## group.
func test_the_switch_is_a_command_on_its_key_and_heads_the_view_group() -> void:
    var registries: SaRegistries = Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    var commands := registries.commands
    assert_true(commands.has(SaEnvironmentView.COMMAND), "the switch is a command on the Shortcuts page")
    assert_eq(commands.chord_text(SaEnvironmentView.COMMAND), "P", "answering to P")
    assert_eq(commands.get_descriptor(SaEnvironmentView.COMMAND).category, &"view", "under View")
    router.free()
    var order: Array = SaSettings.DEFAULT_ORDERS[SaTopBarEnvironment.CATEGORY]
    # Before Rotation and not right before it, since the document's switches,
    # Double Resolution among them, follow it in the view's group.
    assert_true(order.find(SaTopBarEnvironment.ELEMENT) < order.find("Rotation"), "and the button stands before Rotation")


func test_a_flat_document_greys_both_with_the_reason() -> void:
    var buttons := _two_buttons()
    for button in buttons:
        _read(button)
        assert_true(button.disabled, "%s is greyed on a flat document" % button.get_parent().name)
        assert_true(button.tooltip_text.contains("Image > Projection"), "and says where a panorama is assigned")
    assert_false(_view.set_on(true), "the view refuses a flat document whatever presses it")
    _canvas.document.projection = SaProjection.new(SaProjection.Polar.new())
    _read(buttons[1])
    assert_false(buttons[1].disabled, "a disc is looked at face on")
    assert_true(buttons[1].tooltip_text.contains("disc"), "and the tooltip says so")


func test_either_button_drives_the_switch_and_both_show_it() -> void:
    _make_a_panorama()
    var buttons := _two_buttons()
    for button in buttons:
        _read(button)
        assert_false(button.disabled, "a panorama can be looked at from inside")
        assert_eq(button.text, "Flat", "and the view starts flat")

    buttons[1].button_pressed = true
    assert_true(_view.on, "the docker's button turned the view on")
    _read(buttons[0])
    assert_true(buttons[0].button_pressed, "the bar's button shows it on")
    assert_eq(buttons[0].text, "Environment", "and says Environment")
    assert_true(SaEnvironmentView.shows(_canvas), "the canvas is shown as the sky")
    assert_eq(_canvas.shown_in_document(), Rect2(), "and the easel composites the whole document for it")

    buttons[0].button_pressed = false
    assert_false(_view.on, "the bar's button turned it off again")
    _read(buttons[1])
    assert_false(buttons[1].button_pressed, "the docker's button shows it off")
    assert_eq(buttons[1].text, "Flat", "and says Flat")


func test_the_flat_view_comes_back_as_it_was() -> void:
    _make_a_panorama()
    var view := _canvas.view()
    view.set_zoom(2.5)
    view.set_pan(Vector2(-123.0, 45.0))
    _view.set_on(true)
    var fov := _view.camera.fov
    # The view reads a move once the frame's moves are in, a deferred call the
    # suite makes itself, since a suite runs inside one frame.
    view.zoom_at(5.0, Vector2(400.0, 300.0))
    _view._settle()
    assert_true(_view.camera.fov < fov, "a zoom in narrows the field of view")
    var yaw := _view.camera.yaw
    view.set_pan(view.get_pan() + Vector2(80.0, 0.0))
    _view._settle()
    assert_true(_view.camera.yaw < yaw, "a drag to the right turns the camera left")
    _view.set_on(false)
    assert_almost_eq(view.get_zoom(), 2.5, 0.0001, "the flat zoom is back")
    assert_eq(view.get_pan(), Vector2(-123.0, 45.0), "and the flat pan")
