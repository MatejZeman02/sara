## A filter row in the Filter menu promises a chord only when it has one.
##
## A row such as "Box blur", lower case among Gaussian Blur and Motion Blur,
## must not carry the tooltip "A filter Box Blur registered. This row and its
## chord open the same dialog." with no chord. A filter that writes no
## sentence says who added it and nothing about a chord, which no other
## menu row explains either. The box blur writes its own title and sentence,
## so its row reads the way the base module's blurs do.
##
## Each filter registers through `SaContext`, the door the loader uses, so the
## command, its sentence and its chord are the ones a module's would be.
extends "res://tests/test_framework.gd"

## Module ids nobody ships, so their InputMap actions are this suite's to erase.
const QUIET_ID := &"n123-quiet"
const CHORDED_ID := &"n123-chorded"

## The module the box blur registers under here, one nobody ships, so the
## suite's registration leaves the base module's own alone.
const BOX_BLUR_ID := &"n123-box-blur"
## The base module's Box Blur, registered alone so its row is read without the
## rest of the base module's filters.
const BoxBlur = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

## The commands these filters register, whose actions the InputMap keeps after
## the registries are gone.
const ACTIONS: Array[StringName] = [
    &"filter_n123-quiet_quiet_tint", &"filter_n123-chorded_chorded_tint", &"filter_n123-box-blur_box_blur"
]


## A filter with no sentence and the chord it is given, if any.
##
## The members are public because a `title()` or `chord()` reading a private back
## is the getter shape `tests/test_privates_rule.gd` counts. Written by this class
## alone, in `_init`, which is what the rule asks of a member set from outside.
class UndescribedFilter:
    extends SaFilter
    var entry_title: String
    var entry_chord: Array[InputEvent] = []

    func _init(text: String, key: Key = KEY_NONE) -> void:
        entry_title = text
        if key != KEY_NONE:
            var event := InputEventKey.new()
            event.keycode = key
            event.ctrl_pressed = true
            event.alt_pressed = true
            entry_chord.append(event)

    func title() -> String:
        return entry_title

    func chord() -> Array[InputEvent]:
        return entry_chord

    func run(_ctx: SaFilterContext) -> void:
        pass


var _bar: TopMenuBar = null


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    for action: StringName in ACTIONS:
        if InputMap.has_action(action):
            InputMap.erase_action(action)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The Filter menu over *registries*, its commands bound so a row can read its
## chord and its sentence the way the running app's do.
func _menu(registries: SaRegistries) -> SaFilterMenu:
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(registries.commands)
    var menu := _bar.menu("Filter") as SaFilterMenu
    menu.filters = registries.filters
    return menu


## The tooltip and the hint of the row titled *title* in *section*'s list.
func _row(menu: SaFilterMenu, section: StringName, title: String) -> Dictionary:
    var list := menu.show_section(menu.section_item(section))
    if list == null:
        return {}
    var labels := list.row_labels()
    var at := labels.find(title)
    if at < 0:
        return {}
    var hint := ""
    for entry: Dictionary in list.row_report():
        if String(entry.get("label", "")) == title:
            hint = String(entry.get("hint", ""))
    return {"tooltip": list.label_button(list.row_ids()[at]).tooltip_text, "hint": hint}


func test_a_row_with_no_sentence_and_no_chord_names_only_its_module() -> void:
    var registries := _registries()
    var filter := UndescribedFilter.new("Quiet Tint")
    assert_true(registries.context.for_module(QUIET_ID).register_filter(filter), "the filter registers")
    var row := _row(_menu(registries), SaFilterRegistry.OTHER, "Quiet Tint")
    assert_false(row.is_empty(), "its row is in Other")
    if row.is_empty():
        return
    assert_eq(row["hint"], "", "the row shows no chord")
    assert_eq(row["tooltip"], "Added by n123-quiet.", "and its tooltip says who added it and nothing more")
    assert_false(String(row["tooltip"]).contains("chord"), "with no chord promised")


func test_a_row_with_no_sentence_and_a_chord_says_only_who_added_it() -> void:
    var registries := _registries()
    var filter := UndescribedFilter.new("Chorded Tint", KEY_J)
    assert_true(registries.context.for_module(CHORDED_ID).register_filter(filter), "the filter registers with its chord")
    var row := _row(_menu(registries), SaFilterRegistry.OTHER, "Chorded Tint")
    assert_false(row.is_empty(), "its row is in Other")
    if row.is_empty():
        return
    assert_false(String(row["hint"]).is_empty(), "the row shows its chord: %s" % row["hint"])
    assert_eq(row["tooltip"], "Added by n123-chorded.", "and its tooltip says who added it, the chord needing no sentence")


func test_the_box_blur_row_reads_like_its_neighbours() -> void:
    var registries := _registries()
    assert_true(registries.context.for_module(BOX_BLUR_ID).register_filter(BoxBlur.new()), "the box blur registers")
    var row := _row(_menu(registries), &"other", "Box Blur")
    assert_false(row.is_empty(), "the box blur's row reads Box Blur, under Other with no base module to give it Blur")
    if row.is_empty():
        return
    assert_eq(row["hint"], "", "it ships no chord")
    assert_eq(
        row["tooltip"],
        (
            "Soften the picture with a flat average of each pixel's neighbours in a square whose reach is the radius, "
            + "in pixels.\nAdded by n123-box-blur."
        ),
        "and its tooltip says what it does to the picture, then who added it"
    )
    assert_false(String(row["tooltip"]).contains("chord"), "with no chord promised")
