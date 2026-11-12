## A painter locks a finished title, and a later click on its letters with the
## Text tool, a key typed after it, and the door's `text` steps naming it all
## leave its words as they were, the click saying in the corner why.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The keys go through the shortcut router as a keyboard's do, and the click is
## the tool's own press at a document point, as in the suite that letters a
## title.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const StateText = preload("res://modules/sara-base-modules/text/edit/state_text.gd")
const Door = preload("res://modules/sara-base-modules/text/door/sa_text_door.gd")

const SIZE := Vector2i(512, 256)
const WORDS := "LOCKED"
const SAID := "'%s' is locked. Unlock it in the Layers docker first."

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _title: SaLayer = null


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.get_document()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _surface.easel, func() -> Array: return [_surface])
    _registries.register_builtins()
    _modules.clear()
    for path: String in ["stamp-brush", "base", "text"]:
        var module: SaModule = load("res://modules/sara-base-modules/%s/module.gd" % path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _surface.tool_machine = _machine
    _machine.set_active_tool(&"text")
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    var made := Door.text_step(_doc, {"content": WORDS, "at": [100.0, 140.0], "size": 64.0})
    assert_true(made.begins_with("SaCapture: text {"), "The title is made, %s" % made)
    _title = _doc.active_layer
    _title.is_locked = true


func after_each() -> void:
    _router.free()
    for i in range(_modules.size() - 1, -1, -1):
        _modules[i].unregister(_registries.context)
    _modules.clear()
    _surface.tool_machine = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _registries = null
    _title = null


func _tool() -> StateText:
    return _machine.active_tool as StateText


func _words() -> String:
    return (_title.recipe as Recipe).text


## A point inside the title's letters.
func _on_letters() -> Vector2:
    return Rect2((_title.recipe as Recipe).bounds()).get_center()


## A press and a release of the X key typing an x, through the router.
func _type_x() -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = KEY_X
        event.physical_keycode = KEY_X
        event.unicode = "x".unicode_at(0)
        event.pressed = pressed
        _router.handle_viewport_input(event, null)


## The corner lines *act* says, the ones kept before it set aside and put back.
func _refusals_of(act: Callable) -> Array[String]:
    var lines: Array[String] = []
    var announcing := SaProblems.announce
    SaProblems.announce = false
    var kept_faults := SaProblems.pending
    var kept_refusals := SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    act.call()
    SaProblems.detach_sink()
    SaProblems.pending = kept_faults
    SaProblems.pending_refusals = kept_refusals
    SaProblems.announce = announcing
    return lines


func test_a_click_on_a_locked_title_opens_nothing_says_why_and_a_key_leaves_its_words() -> void:
    var steps := _doc.history.position()
    var layers := _doc.get_child_count()
    var said := _refusals_of(func() -> void: _tool().press(_on_letters()))
    assert_false(_tool().editing(), "A click on a locked title's letters opens no block")
    assert_eq(said, [SAID % _title.name], "and the corner says the layer is locked")
    _type_x()
    assert_eq(_words(), WORDS, "A key typed after it leaves the words as they were")
    assert_eq(_doc.get_child_count(), layers, "and the click made no layer")
    assert_eq(_doc.history.position(), steps, "and nothing is recorded")


func test_the_door_s_text_steps_naming_a_locked_title_are_refused_and_change_nothing() -> void:
    var steps := _doc.history.position()
    var answer := Door.text_step(_doc, {"layer": String(_title.name), "content": "changed"})
    assert_eq(answer, "SaCapture: text refused, " + SAID % _title.name, "The door's text step is refused for the lock")
    assert_eq(_words(), WORDS, "and the words stay")
    var caret := Door.text_edit_step(_doc, {"layer": String(_title.name)}, _machine)
    assert_eq(caret, "SaCapture: text refused, " + SAID % _title.name, "So is its caret step")
    assert_false(_tool().editing(), "which opens no block")
    assert_eq(_doc.history.position(), steps, "and nothing is recorded")


func test_the_same_title_unlocked_opens_under_a_click_as_before() -> void:
    _title.is_locked = false
    _tool().press(_on_letters())
    assert_true(_tool().editing(), "An unlocked title's letters open under a click")
    _type_x()
    assert_eq(_tool()._text.length(), WORDS.length() + 1, "and a key types into it")
