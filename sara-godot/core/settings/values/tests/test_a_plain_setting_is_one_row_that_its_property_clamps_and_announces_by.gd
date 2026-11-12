## A plain preference is declared once, as a row of `SaSettingsKeys.SETTINGS`
## with its section, key, default and bounds, and its property in
## `SaSettingsValues` is a stub whose setter is the row's clamp and the
## announcement.
##
## The fixture beside this suite holds what every key of a fresh instance read
## before the rows carried the defaults, written by the code of that time, so a
## default that moved in the cut fails here by name. A key added since is not in
## it and needs no line here.
extends "res://tests/test_framework.gd"

const BEFORE := "res://core/settings/values/tests/defaults_before_the_cut.cfg"
const PLAIN_SOURCE := "res://core/settings/values/sa_settings_plain.gd"
const VALUES_SOURCE := "res://core/settings/values/sa_settings_values.gd"

var _heard: Array[StringName] = []
var _rebuilds := 0


func _plain() -> Array[String]:
    var plain: Array[String] = []
    for property: String in SaSettingsKeys.SETTINGS:
        if SaSettingsKeys.is_plain(property):
            plain.append(property)
    return plain


func _listening() -> SaSettingsValues:
    _heard.clear()
    _rebuilds = 0
    var values := SaSettingsValues.new()
    values.changed.connect(func(property: StringName) -> void: _heard.append(property))
    values.profile_changed.connect(func() -> void: _rebuilds += 1)
    return values


func test_every_key_reads_the_default_it_read_before_the_cut() -> void:
    var before := ConfigFile.new()
    assert_eq(before.load(BEFORE), OK, "the fixture parses")
    var fresh := SaSettingsValues.new()
    var wrong: Array[String] = []
    for property: String in before.get_section_keys("defaults"):
        var want: Variant = before.get_value("defaults", property)
        var have: Variant = fresh.stored(property) if SaSettingsKeys.KEYS.has(property) else null
        if typeof(want) != typeof(have) or want != have:
            wrong.append("%s: %s against %s" % [property, have, want])
    fresh.free()
    assert_true(before.get_section_keys("defaults").size() >= 100, "the fixture holds the keys of the cut")
    assert_true(wrong.is_empty(), "every default is the one it was: %s" % "; ".join(wrong))


func test_every_plain_row_has_its_stub_and_every_stub_its_row() -> void:
    var source := FileAccess.get_file_as_string(PLAIN_SOURCE)
    var stubs: Array[String] = []
    var found := RegEx.create_from_string('_took\\(&"(\\w+)", (\\w+), val\\)')
    for hit: RegExMatch in found.search_all(source):
        assert_eq(hit.get_string(2), hit.get_string(1), "the stub of %s reads its own property" % hit.get_string(1))
        stubs.append(hit.get_string(1))
    var plain := _plain()
    for property: String in plain:
        assert_true(stubs.has(property), "%s has a row and a stub" % property)
        assert_true(source.contains('_announce(&"%s")' % property), "and the stub announces %s" % property)
    for property: String in stubs:
        assert_true(plain.has(property), "the stub of %s has a plain row" % property)
    assert_true(plain.size() > 40, "most of the values' preferences are plain, %d of them" % plain.size())
    var by_hand := FileAccess.get_file_as_string(VALUES_SOURCE)
    for property: String in plain:
        assert_false(by_hand.contains("\nvar %s:" % property), "%s is written from its row alone, not by hand" % property)
    assert_true(by_hand.count("\n") < 800, "the values file stands under 800 lines")


## The property the script wrote has the type of its row's default, which a
## typed default would otherwise turn into a silent conversion on every write.
func test_every_plain_property_is_typed_as_its_rows_default() -> void:
    var values := SaSettingsValues.new()
    var types := {}
    for entry: Dictionary in values.get_property_list():
        types[entry["name"]] = entry["type"]
    for property: String in _plain():
        var default: Variant = SaSettingsKeys.SETTINGS[property][2]
        assert_eq(types.get(property, TYPE_NIL), typeof(default), "%s is typed as its default" % property)
    values.free()


func test_a_plain_write_lands_and_announces_its_own_name() -> void:
    var values := _listening()
    var wrong: Array[String] = []
    for property: String in _plain():
        var row: Array = SaSettingsKeys.SETTINGS[property]
        var other: Variant = _away_from(row)
        _heard.clear()
        values.set(property, other)
        if values.get(property) != other:
            wrong.append("%s held %s after %s" % [property, values.get(property), other])
        if _heard != [StringName(property)]:
            wrong.append("%s announced %s" % [property, _heard])
    values.free()
    assert_true(wrong.is_empty(), "every stub writes and names its own property: %s" % "; ".join(wrong))


func test_a_number_is_held_to_its_rows_bounds_and_a_string_to_its_list() -> void:
    var values := SaSettingsValues.new()
    var checked := 0
    for property: String in _plain():
        var row: Array = SaSettingsKeys.SETTINGS[property]
        if row.size() < 4 or (row[3] as Array).is_empty():
            continue
        var bounds: Array = row[3]
        match typeof(row[2]):
            TYPE_INT, TYPE_FLOAT:
                values.set(property, bounds[0] - 1)
                assert_eq(values.get(property), bounds[0], "%s stops at its floor" % property)
                if typeof(bounds[1]) == TYPE_FLOAT and is_inf(bounds[1]):
                    continue
                if bounds[1] < SaSettingsKeys.NO_TOP:
                    values.set(property, bounds[1] + 1)
                    assert_eq(values.get(property), bounds[1], "and at its top")
            TYPE_STRING:
                values.set(property, "no_such_choice")
                assert_eq(values.get(property), row[2], "%s reads its default for a choice it does not list" % property)
        checked += 1
    values.free()
    assert_true(checked >= 15, "the bounded rows were checked, %d of them" % checked)


func test_once_announces_a_change_alone_and_rebuild_says_so_too() -> void:
    var values := _listening()
    values.keep_blend_mode = values.keep_blend_mode
    assert_true(_heard.is_empty(), "a once row written its own value says nothing")
    values.keep_blend_mode = not values.keep_blend_mode
    assert_eq(_heard, [&"keep_blend_mode"], "and a change is announced")
    _heard.clear()
    values.show_grid = values.show_grid
    assert_eq(_rebuilds, 0, "a rebuild row written its own value rebuilds nothing")
    values.show_grid = not values.show_grid
    assert_eq(_heard, [&"show_grid"], "a change of it is announced")
    assert_eq(_rebuilds, 1, "and asks for the rebuild once")
    _heard.clear()
    values.integer_zoom = values.integer_zoom
    assert_eq(_heard, [&"integer_zoom"], "a plain row is announced on every write, as its setter always was")
    values.selection_feather = 0.05
    _heard.clear()
    values.selection_feather = 0.05 + 1e-9
    assert_true(_heard.is_empty(), "a once number counts a write within a hair as the same value")
    values.free()


## A value of *row*'s type away from its default, and inside its bounds.
func _away_from(row: Array) -> Variant:
    var default: Variant = row[2]
    var bounds: Array = row[3] if row.size() > 3 else []
    match typeof(default):
        TYPE_BOOL:
            return not default
        TYPE_INT:
            return default + 1 if bounds.is_empty() or default + 1 <= bounds[1] else default - 1
        TYPE_FLOAT:
            var step: float = 0.01
            return default + step if bounds.is_empty() or default + step <= bounds[1] else default - step
        TYPE_STRING:
            for choice: Variant in bounds:
                if choice != default:
                    return choice
            return "moved" if bounds.is_empty() else default
        TYPE_RECT2I:
            return Rect2i(1, 2, 3, 4)
        TYPE_DICTIONARY:
            return {"moved": true}
    return default
