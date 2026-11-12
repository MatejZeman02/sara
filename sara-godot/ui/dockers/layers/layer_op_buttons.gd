## The four operations the Layers docker's action row draws as buttons between
## minus and More: Duplicate, Group, Merge Down and Add Mask.
##
## Buttons rather than rows of the More menu, because they are the operations
## a painter reaches for between strokes, the stretch they stand in is
## otherwise empty, and a menu holding them too grows past the list's cap and
## scrolls its last rows under a clipped edge.
##
## **A class of its own because it owns two things the row does not**: which of
## the four fit, and what each says on hover. Each button is keyed on the id of
## the More menu row it stands in for, so a press is answered by the same
## handler a row's is and a folded button's row is found by the same id.
##
## **A container that asks for no width.** The row's floor stays plus, the
## arrow, minus and More, which is what the docker's floor is measured for,
## and the buttons take what the docker has left. In the row's own
## `HBoxContainer` they would add their widths to the floor and push More off
## the docker's edge at its floor. The buttons that do not fit are hidden
## from the right, and `holds` is what tells the More menu to list them.
class_name SaLayerOpButtons
extends Container

## A button was pressed, by the id of the More menu row it stands in for.
signal chosen(id: StringName)

## The four, in the order they stand, which is the reverse of the order they
## fold in: the row id, the command the Layer menu runs for it, the icon, and
## the words the button says when no registry answers for the command. The row
## id is the command's, because the More menu's rows are `SaLayerMenuRows`'s.
const ENTRIES: Array = [
    [&"layer_duplicate", &"layer_duplicate", "duplicate", "Duplicate Layer"],
    [&"layer_group", &"layer_group", "group", "Group"],
    [&"layer_merge_down", &"layer_merge_down", "merge_down", "Merge Down"],
    [&"layer_mask_add", &"layer_mask_add", "layer_mask", "Add Mask"],
]

## Where a button's sentence and chord come from. Found on Main on first use in
## the running app, the way the actions find the filters, and set by a suite.
var commands: SaCommandRegistry = null

## How many of the buttons, counted from the left, the last layout had room
## for. All of them until a layout says otherwise, because a row never laid out
## has folded nothing. Written only by `fit`.
var shown: int = ENTRIES.size()

var _gap: int = 0
var _buttons: Dictionary = {}
## The words the last `sync` put in place of a command's own, row id -> words,
## kept so a rebound chord can write the hovers again without the row's help.
var _words: Dictionary = {}
## Why each dimmed button will not act, row id -> sentence, from the last
## `sync`, kept for the same reason.
var _reasons: Dictionary = {}


func _init(gap: int) -> void:
    _gap = gap
    name = "OpButtons"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for entry: Array in ENTRIES:
        var words := tr(entry[3])
        var btn := SaMake.button(self, String(entry[3]).replace(" ", "") + "Btn", "", words)
        btn.custom_minimum_size = Vector2(SaUI.px(SaUI.BASE_BTN_H), SaUI.px(SaUI.BASE_BTN_H))
        SaUI.set_button_icon(btn, entry[2], words)
        btn.pressed.connect(_on_pressed.bind(entry[0]))
        _buttons[entry[0]] = btn


func _on_pressed(id: StringName) -> void:
    chosen.emit(id)


## The button standing in for the row *id*, folded or not, or null.
func button(id: StringName) -> Button:
    return _buttons.get(id, null)


## The button standing in for the row *id* while it stands on the row, and null
## while it is folded into the More menu.
func on_row(id: StringName) -> Button:
    var btn := button(id)
    return btn if btn != null and holds(btn) else null


## Whether *btn* stands on the row rather than folded into the More menu.
func holds(btn: Control) -> bool:
    var at := get_children().find(btn)
    return at >= 0 and at < shown


## Dims every button whose id *live* does not hold true, and writes each hover
## again, with the words *words* gives in place of its command's own, which is
## Group reading Ungroup on a group, and on a dimmed button the sentence
## *reasons* gives in place of its command's, which is Merge Down above a
## ground saying why it will not.
func sync(live: Dictionary, words: Dictionary = {}, reasons: Dictionary = {}) -> void:
    _words = words
    _reasons = reasons
    for entry: Array in ENTRIES:
        button(entry[0]).disabled = not bool(live.get(entry[0], false))
    _write_hovers()


## Each hover is "Merge Down (Ctrl+E)" over the command's sentence, read from
## the registry on every write, so a chord rebound on the Shortcuts page is the
## chord it names next. The button's own words alone when no registry answers.
##
## **A dimmed button with a reason says the reason where the sentence goes.**
## The More menu's folded row and the Layer menu's said why already, and the
## button a painter hovers first still said what Merge Down does above a
## ground that will take no merge.
func _write_hovers() -> void:
    var registry := _command_registry()
    for entry: Array in ENTRIES:
        var command_id: StringName = entry[1]
        var descriptor := registry.get_descriptor(command_id) if registry != null else null
        var words := tr(entry[3])
        if descriptor != null and not descriptor.label.is_empty():
            words = tr(descriptor.label)
        words = _words.get(entry[0], words)
        var hover := words
        var sentence := ""
        if descriptor != null:
            var chord := registry.chord_text(command_id, 1)
            hover = words if chord.is_empty() else "%s (%s)" % [words, chord]
            if not descriptor.sentence.is_empty():
                sentence = tr(descriptor.sentence)
        if button(entry[0]).disabled and not str(_reasons.get(entry[0], "")).is_empty():
            sentence = _reasons[entry[0]]
        button(entry[0]).tooltip_text = hover if sentence.is_empty() else "%s\n%s" % [hover, sentence]


## The command registry, found on Main on first use and kept, its `changed`
## answered so a rebound chord reaches the hovers. Null in a suite that sets
## none, and before Main has one.
func _command_registry() -> SaCommandRegistry:
    if commands == null and is_inside_tree() and get_tree().current_scene != null:
        var registries := get_tree().current_scene.get("registries") as SaRegistries
        commands = registries.commands if registries != null else null
    if commands != null and not commands.changed.is_connected(_write_hovers):
        commands.changed.connect(_write_hovers)
    return commands


func _get_minimum_size() -> Vector2:
    var tallest := 0.0
    for child in get_children():
        tallest = maxf(tallest, (child as Control).get_combined_minimum_size().y)
    return Vector2(0.0, tallest)


func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN:
        fit(size.x)


## Shows as many buttons as *room* holds, the leftmost first, and lays them
## against the right edge of *room*, beside More. A visibility is written only
## when it changes, because each write asks for another layout.
func fit(room: float) -> void:
    var buttons := get_children()
    var used := 0.0
    shown = 0
    for child in buttons:
        var wants := (child as Control).get_combined_minimum_size().x + (_gap if shown > 0 else 0)
        if used + wants > room:
            break
        used += wants
        shown += 1
    var x := room - used
    for index in buttons.size():
        var btn := buttons[index] as Control
        var on := index < shown
        if btn.visible != on:
            btn.visible = on
        if on:
            var width := btn.get_combined_minimum_size().x
            fit_child_in_rect(btn, Rect2(x, 0.0, width, size.y))
            x += width + _gap
