## `make_float`, `make_enum`, `make_custom`, `make` and
## `make_tip_image` take the fields their callers used to set on the lines
## after, so a row is one expression, and `remade` gives a page another's row
## under an address of its own without changing the row it was handed.
extends "res://tests/test_framework.gd"

## The files the row moved, `state_bucket_fill.gd` and `state_zoom.gd` left to
## Which owns them.
const CALLERS: Array[String] = [
    "res://core/api/smudge/sa_smudge_page.gd",
    "res://core/api/color/sa_paint_exposure.gd",
    "res://modules/sara-noise-brush-engine/module.gd",
    "res://modules/sara-noise-brush-engine/noise_fields.gd",
    "res://modules/sara-noise-brush-engine/field_folder/noise_field_folder.gd",
    "res://modules/sara-noise-brush-engine/randomise/randomise_control.gd",
    "res://modules/sara-noise-brush-engine/tip/tip_row.gd",
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-base-modules/base/gradient/sa_gradient_options.gd",
    "res://modules/sara-base-modules/base/sa_transform_options.gd",
    "res://modules/sara-base-modules/base/liquify/sa_liquify.gd",
    "res://modules/sara-base-modules/stamp-brush/module.gd",
    "res://modules/sara-base-modules/filter-brush/module.gd",
    "res://modules/sara-base-modules/stamp-brush/ui/sa_color_page.gd",
    "res://modules/sara-base-modules/stamp-brush/ui/sa_curve_option_pages.gd",
    "res://modules/sara-base-modules/stamp-brush/ui/sa_masking_page.gd",
    "res://modules/sara-base-modules/stamp-brush/ui/sa_texture_page.gd",
    "res://modules/sara-base-modules/stamp-brush/ui/sa_tip_page.gd",
]

## Two receivers in those files whose fields share a spec field's name and are
## no spec: the randomise control's slider and the eraser's command.
const NOT_SPECS: Array[String] = ["_amount", "toggle_eraser"]


func test_a_float_row_takes_its_fields_in_the_call() -> void:
    var spec := (
        SaOptionSpec
        . make_float(
            &"count",
            "Count",
            1.0,
            9.0,
            1.0,
            {
                "kind": SaOptionSpec.Kind.INT,
                "property": ^"tip:count",
                "decimals": 0,
                "bar": false,
                "shown_when": {"key": &"mode", "value": 2},
                "enabled_when_values": [2, 3],
            }
        )
    )
    assert_eq(spec.kind, SaOptionSpec.Kind.INT, "kind is the one named")
    assert_eq(spec.property_path(), ^"tip:count", "and so is the property")
    assert_eq(spec.decimals, 0, "and the decimals")
    assert_false(spec.bar, "and the bar")
    assert_eq(spec.step, 1.0, "the maker's own step stands")
    # A typed dictionary set through `set` from a literal stays empty and says
    # nothing, which is what the maker's `assign` is for.
    assert_eq(spec.shown_when.get("value"), 2, "a typed dictionary field holds the rule handed it")
    assert_eq(spec.enabled_when_values, [2, 3], "and an array field its values")


func test_an_enum_row_keeps_its_choices_beside_its_fields() -> void:
    var spec := SaOptionSpec.make_enum(&"shape", "Shape", [0, 1], ["Round", "Square"], {"width": 84, "tooltip": "The shape."})
    assert_eq(spec.choices.size(), 2, "both choices")
    assert_eq(spec.width, 84, "the width named")
    assert_eq(spec.tooltip, "The shape.", "and the tooltip")


func test_a_custom_and_a_tip_image_row_take_fields_too() -> void:
    var custom := SaOptionSpec.make_custom(&"ramp", "Ramp", Callable(), Callable(), {"on_tool": true})
    assert_true(custom.on_tool, "the custom row is on the tool")
    var tip := SaOptionSpec.make_tip_image(&"tip_image", "Tip image", {"advanced": true})
    assert_true(tip.advanced, "the tip image row is advanced")
    assert_eq(tip.property_path(), ^"tip:image_path", "and keeps the path its maker gives it")


func test_a_remade_row_is_a_new_row_and_the_first_is_left_as_it_was() -> void:
    var first := SaOptionSpec.make_float(
        &"tip_ratio", "Ratio", 0.0, 1.0, 0.01, {"page": "Brush Tip", "shown_when": {"key": &"tip_generator", "value": 1}}
    )
    var shown := first.shown_when.duplicate()
    shown["key"] = &"masking_tip_generator"
    var second := first.remade({"key": &"masking_tip_ratio", "page": "Masking Brush", "shown_when": shown})
    assert_eq(second.key, &"masking_tip_ratio", "the new row has the new key")
    assert_eq(second.page, "Masking Brush", "and the new page")
    assert_eq(second.label, "Ratio", "and every field not named, the label")
    assert_eq(second.max_value, 1.0, "and the range")
    assert_eq(first.key, &"tip_ratio", "the first row keeps its key")
    assert_eq(first.page, "Brush Tip", "and its page")
    assert_eq(first.shown_when.get("key"), &"tip_generator", "and its rule, which the second does not share")


## The requirement: no caller in the files above sets a field on a spec after a
## maker returns it, read off the source as a reviewer would.
func test_no_caller_sets_a_spec_field_after_the_maker() -> void:
    var fields: Array[String] = []
    for entry: Dictionary in SaOptionSpec.new().get_property_list():
        if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
            fields.append(String(entry["name"]))
    var pattern := RegEx.create_from_string(
        "^\\s*(\\w+)(?:\\[[^\\]]*\\])?\\.(%s)\\b(?:\\[[^\\]]*\\])?\\s*(?:=|\\+=)[^=]" % "|".join(fields)
    )
    var found: Array[String] = []
    for path: String in CALLERS:
        var lines := FileAccess.get_file_as_string(path).split("\n")
        for index in lines.size():
            var hit := pattern.search(lines[index])
            if hit != null and not NOT_SPECS.has(hit.get_string(1)):
                found.append("%s:%d %s" % [path, index + 1, lines[index].strip_edges()])
    assert_eq(found, [] as Array[String], "every field is named in the maker's call")
