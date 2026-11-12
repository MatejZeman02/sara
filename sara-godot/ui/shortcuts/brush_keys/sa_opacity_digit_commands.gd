## The ten opacity digits: a bare 1 to 9 or 0 typed over the canvas sets an
## opacity, by Photoshop's rule, the one most painters who ask for this know.
##
## **What a digit sets.** The brush's opacity while a painting tool whose
## settings carry one is active, and the active layer's with any other tool.
## 1 to 9 are 10 to 90 %, 0 is 100 %, and a second digit typed within
## `PAIR_MSEC` of the first makes the pair one exact value, so 4 then 5 is
## 45 %, 0 then 5 is 5 % and 0 then 0 is 0 %. The corner says what changed
## and to what in one shape, 'Opacity 50%, brush "Soft Round"' or 'Opacity 50%,
## layer "Layer 1"'.
##
## **Ten commands rather than one reading the key**, so the Keyboard Shortcuts
## page has a row per digit and a painter who wants the keys for something else
## rebinds them. Each answers to its digit on the row and on the numpad, a
## second chord on one command, which is how `sa_brush_slot_commands.gd` gives
## its slots the numpad. A digit typed into a text field or a spin box stays
## there, because `ShortcutRouter.text_field_keeps` holds every plain key for a
## focused box and a spin box types into its own `LineEdit`.
##
## **The Czech digit row.** On a Czech keyboard the row types letters
## without Shift, so its keys arrive with the letter as their keycode and the
## digit only as their physical position, and no chord written by keycode
## matches them. `answer_by_position` is the second try the router makes with
## the position read as the key. It is a rule about the digit row rather than
## about these ten, so a painter who rebinds 5 to something else finds the Czech
## 5 follows the rebind.
class_name SaOpacityDigitCommands
extends RefCounted

## The digit row in digit order, 0 first, so a digit is its own index.
const KEYS: Array = [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

## The same ten on the numpad.
const NUMPAD_KEYS: Array = [KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]

## How long after one digit the next still makes a pair with it, in
## milliseconds. Photoshop publishes no number for its moment, and at this one
## two digits typed as a number pair up while a painter who presses 3, looks at
## the canvas and presses 5 gets 50 % rather than 35 %.
const PAIR_MSEC: int = 800

## The digit that opened a pair and is waiting for its second, or -1. Static,
## because the ten commands are ten handlers of one keyboard.
static var _pending_digit: int = -1

## When `_pending_digit` was typed, in `Time.get_ticks_msec()`.
static var _pending_at: int = 0


## The command id for *digit*, 0 to 9. Under `brush_`, so the Keyboard
## Shortcuts page files the ten rows in the Brush section beside the slots.
static func command_id(digit: int) -> StringName:
    return StringName("brush_opacity_digit_%d" % digit)


## Registers all ten against whatever module *ctx* belongs to. *tool_machine_provider*
## answers the main canvas's tool machine, and a host with none, which is what
## a test that only wants the rows builds, gets commands that decline.
static func register_all(ctx: SaContext, tool_machine_provider: Callable) -> void:
    for digit in range(10):
        var command := SaCommandDescriptor.create(
            command_id(digit), "Opacity %d%%" % single_value(digit), _typed.bind(digit, tool_machine_provider)
        )
        command.title_pattern = "Opacity %d%%"
        command.title_value = single_value(digit)
        # Bare keys, so Ctrl with a digit stays the slots' and the zoom's.
        command.default_events = [SaAppCommands.chord(KEYS[digit]), SaAppCommands.chord(NUMPAD_KEYS[digit])]
        command.category = &"brush"
        command.sentence = (
            "Set the brush's opacity with a painting tool, or the active layer's with any other, to %d%%." % single_value(digit)
            + " Two digits typed quickly set the exact value."
        )
        ctx.register_command(command)


## The per cent one digit on its own means: 1 to 9 are tens and 0 is the whole.
static func single_value(digit: int) -> int:
    return 100 if digit == 0 else digit * 10


## The per cent *digit* makes, typed at *now_msec*, and whether it closed a
## pair. Keeps the pending digit, so this is the rule and the memory at once,
## and a test hands the clock in rather than sleeping.
static func value_for(digit: int, now_msec: int) -> int:
    if _pending_digit >= 0 and now_msec - _pending_at <= PAIR_MSEC:
        var pair := _pending_digit * 10 + digit
        _pending_digit = -1
        return pair
    _pending_digit = digit
    _pending_at = now_msec
    return single_value(digit)


## Forgets a digit waiting for its pair, so a suite starts each case clean.
static func forget_pending() -> void:
    _pending_digit = -1


## The command's own handler.
static func _typed(digit: int, tool_machine_provider: Callable) -> bool:
    var tool_machine: ToolMachine = tool_machine_provider.call() if tool_machine_provider.is_valid() else null
    return apply(tool_machine, digit, Time.get_ticks_msec())


## Sets whichever opacity *digit* means with *tool_machine*'s active tool, and
## answers whether anything took it. False with no machine, and with no brush
## and no layer to set, so the key is left to whatever else binds it.
static func apply(tool_machine: ToolMachine, digit: int, now_msec: int) -> bool:
    if tool_machine == null:
        return false
    var percent := value_for(digit, now_msec)
    var settings := brush_settings(tool_machine)
    var document: SaDocument = tool_machine.surface.get_document() if tool_machine.surface != null else null
    var layer: SaLayer = document.active_layer if document != null else null
    if settings != null:
        settings.opacity = percent / 100.0
        # Nothing observes brush settings, so this is what makes the options
        # bar read the Opacity row again, the way the bracket keys do.
        EventBus.tool_options_moved.emit()
    elif layer != null:
        SaLayerOps.new(document).set_opacity(layer, percent / 100.0)
    else:
        return false
    if settings != null:
        var said := TranslationServer.translate_plural('Opacity %d%%, brush "%s"', 'Opacity %d%%, brush "%s"', percent)
        SaMessage.notice(said % [percent, brush_name(tool_machine)])
    else:
        var said := TranslationServer.translate_plural('Opacity %d%%, layer "%s"', 'Opacity %d%%, layer "%s"', percent)
        SaMessage.notice(said % [percent, layer.name])
    return true


## What the corner calls the brush a digit set: the preset the bar has loaded,
## or the tool's own name while none is or the tool takes no presets.
static func brush_name(tool_machine: ToolMachine) -> String:
    var descriptor := tool_machine.get_descriptor(tool_machine.active_tool_name)
    var presets := SaBrushSlotCommands.preset_box() if not String(descriptor.preset_engine).is_empty() else null
    var loaded := presets.selected_preset if presets != null else ""
    return loaded if not loaded.is_empty() else descriptor.display_name


## The settings a digit sets the opacity of: the active tool's, when its
## descriptor says it paints and its settings carry an `opacity`. Null for
## every other tool, which is what sends the digit to the layer. A painting
## tool with no opacity of its own sends it there as well, because the digit
## has to set something.
static func brush_settings(tool_machine: ToolMachine) -> Resource:
    var tool := tool_machine.active_tool
    var descriptor := tool_machine.get_descriptor(tool_machine.active_tool_name)
    if tool == null or descriptor == null or not descriptor.is_painting:
        return null
    var settings: Resource = tool.get("settings")
    if settings != null and "opacity" in settings:
        return settings
    return null


## The router's second try for a key on the digit row whose keycode is not its
## digit: the same press with its position read as the key, handed to
## *commands*. False for every other key, and for a digit row that already
## types digits, which the first try has had.
static func answer_by_position(commands: SaCommandRegistry, event: InputEvent) -> bool:
    var key := event as InputEventKey
    if commands == null or key == null:
        return false
    var position: Key = key.physical_keycode
    if position < KEY_0 or position > KEY_9 or key.keycode == position:
        return false
    var twin := key.duplicate() as InputEventKey
    twin.keycode = position
    return commands.try_handle_input(twin)
