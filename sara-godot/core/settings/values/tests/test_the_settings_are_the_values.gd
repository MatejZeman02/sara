## The settings autoload extends `SaSettingsValues` rather than
## forwarding 55 properties to one, and the layout and the file stopped taking
## the autoload back. No key moved, so a profile written before the cut has to
## read back value for value.
##
## The fixture is a hand-written `settings.cfg` at this build's version with
## every key of `SaSettingsKeys.KEYS` set away from its default, in the shape
## `ConfigFile` writes. It is read by a second instance of the autoload's own
## script, never added to the tree, so nothing the running application listens
## to hears the painter's theme or scale change under it.
extends "res://tests/test_framework.gd"

const AUTOLOAD := "res://core/settings/sa_settings.gd"
const FIXTURE := "res://tests/data/every_key_moved.cfg"
static var scratch_path: String = SaDataRoot.path("test_p25_settings.cfg")


func _read_fixture() -> ConfigFile:
    var fixture := ConfigFile.new()
    assert_eq(fixture.load(FIXTURE), OK, "the fixture parses")
    return fixture


## A settings object of the autoload's class reading a copy of the fixture.
func _loaded() -> Node:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    DirAccess.remove_absolute(scratch)
    DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), scratch)
    var settings: Node = load(AUTOLOAD).new()
    settings.settings_path = scratch
    settings.load_settings()
    return settings


func _cleanup() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", SaSettingsFile.BACKUP_SUFFIX]:
        DirAccess.remove_absolute(scratch + suffix)


func test_the_fixture_moves_every_key_away_from_its_default() -> void:
    var fixture := _read_fixture()
    var fresh := SaSettingsValues.new()
    var missing: Array[String] = []
    var at_default: Array[String] = []
    for property: String in SaSettingsKeys.KEYS:
        var place: Array = SaSettingsKeys.KEYS[property]
        if not fixture.has_section_key(place[0], place[1]):
            missing.append(property)
        elif fixture.get_value(place[0], place[1]) == fresh.stored(property):
            at_default.append(property)
    fresh.free()
    assert_true(missing.is_empty(), "the fixture carries every key, missing: %s" % ", ".join(missing))
    assert_true(at_default.is_empty(), "and none at its default: %s" % ", ".join(at_default))


func test_a_profile_written_before_the_cut_reads_back_value_for_value() -> void:
    var fixture := _read_fixture()
    var settings := _loaded()
    var wrong: Array[String] = []
    for property: String in SaSettingsKeys.KEYS:
        var place: Array = SaSettingsKeys.KEYS[property]
        var want: Variant = fixture.get_value(place[0], place[1])
        var have: Variant = settings.stored(property)
        if typeof(want) != typeof(have) or want != have:
            wrong.append("%s: %s against %s" % [property, have, want])
    settings.free()
    _cleanup()
    assert_eq(
        SaSettingsKeys.KEYS.size(),
        113,
        "a hundred and thirteen keys were read: a new key raises this count and joins the table",
    )
    assert_true(wrong.is_empty(), "every key reads back as written: %s" % "; ".join(wrong))


## The load saves the profile on its way out, so the file on disk after it is
## what the file object writes. Every key has to come back unchanged, the two
## proof modes included: their read falls back when no module registered the
## id, and their write must not.
func test_the_profile_the_load_saves_is_the_one_it_read() -> void:
    var fixture := _read_fixture()
    var settings := _loaded()
    var proof_read: String = settings.canvas_proof_mode
    settings.free()
    var written := ConfigFile.new()
    assert_eq(written.load(ProjectSettings.globalize_path(scratch_path)), OK, "the saved profile parses")
    _cleanup()
    var wrong: Array[String] = []
    for property: String in SaSettingsKeys.KEYS:
        var place: Array = SaSettingsKeys.KEYS[property]
        var want: Variant = fixture.get_value(place[0], place[1])
        var have: Variant = written.get_value(place[0], place[1])
        if typeof(want) != typeof(have) or want != have:
            wrong.append("%s: %s against %s" % [property, have, want])
    assert_true(wrong.is_empty(), "every key is written back as it was read: %s" % "; ".join(wrong))
    # A key the skeleton no longer lists waits in the profile for the module
    # that took it over, the MIDI pair for two, so the save keeps it.
    var listed: Array[String] = []
    for property: String in SaSettingsKeys.KEYS:
        listed.append("/".join(SaSettingsKeys.KEYS[property]))
    var dropped: Array[String] = []
    for section: String in fixture.get_sections():
        for key: String in fixture.get_section_keys(section):
            if not listed.has("%s/%s" % [section, key]) and not written.has_section_key(section, key):
                dropped.append("%s/%s" % [section, key])
    assert_true(dropped.is_empty(), "and a key no property lists is kept: %s" % ", ".join(dropped))
    assert_eq(written.get_value("meta", "version"), SaSettingsFile.SETTINGS_VERSION, "and the version did not move")
    assert_eq(
        written.get_value("ui", "canvas_proof_mode"),
        "p25_a_module_not_loaded",
        "the stored proof mode survives the save whatever the read says (%s)" % proof_read
    )


## The facade's two jobs that are not preferences still reach the objects that
## own them: a layout write lands in the profile and is announced on the
## autoload's own signal, and a reset empties the layout's sections.
func test_the_layout_writes_through_the_file_and_announces_on_the_autoload() -> void:
    var settings := _loaded()
    var heard := [0]
    settings.profile_changed.connect(func() -> void: heard[0] += 1)
    settings.set_layout_order("TopMenuBar", ["Edit", "File"])
    var stored_order: Variant = settings.config.get_value("profile_order", "TopMenuBar", [])
    settings.reset_to_defaults()
    var after_reset: bool = settings.config.has_section("profile_order")
    var order_after: Dictionary = settings.layout_orders
    settings.free()
    _cleanup()
    assert_eq(stored_order, ["Edit", "File"], "the order was written into the profile")
    assert_true(heard[0] >= 2, "the order and the reset were both announced, %d times" % heard[0])
    assert_false(after_reset, "the reset erased the order's section")
    assert_true(order_after.is_empty(), "and emptied the layout's own dictionary")
