## d17: a filter carries a sentence, and the menu and the browser read one string.
##
## `SaCommandDescriptor.sentence` is a sentence: a command explained once is
## explained wherever it is offered. A filter never got one.
## `SaContext.register_filter` built its command with a title and a category and
## nothing else, and `SaFilter` had no method a sentence could come from, so the
## Filter menu could only say who registered a row and the browser showed "This
## filter carries no description" for every filter in the tree.
##
## What this asserts is the filing's proof: `SaFilter.sentence()` beside
## `title()`, written onto the command at registration, read by a pixel filter off
## its own file's leading comment, and one string reaching the command registry,
## the Filter menu's tooltip and the browser's detail column.
##
## `scenarios/a-filter-carries-no-sentence.json` is the same claim on the
## running app, with only the pixel filter fixture loaded.
extends "res://tests/test_framework.gd"

const PIXEL_FIXTURE := "res://tests/fixtures/modules/pixel-filter-fixture/threshold.gmacs"


## A module filter that says what it does.
class SaidFilter:
    extends SaFilter

    var entry_title: String
    var entry_sentence: String

    func _init(text: String, said: String) -> void:
        entry_title = text
        entry_sentence = said

    func title() -> String:
        return entry_title

    func sentence() -> String:
        return entry_sentence

    func run(_ctx: SaFilterContext) -> void:
        pass


class SilentFilter:
    extends SaFilter

    func title() -> String:
        return "Silent"

    func run(_ctx: SaFilterContext) -> void:
        pass


var _filters: SaFilterRegistry = null
var _commands: SaCommandRegistry = null


func before_each() -> void:
    _filters = SaFilterRegistry.new()
    _commands = SaCommandRegistry.new()


func after_each() -> void:
    _filters = null
    _commands = null


func _context() -> SaContext:
    return SaContext.create(null, null, _commands, null, null, null, Callable(), Callable(), _filters)


func _sentence_on_command(filter: SaFilter) -> String:
    var descriptor := _commands.get_descriptor(SaFilterRegistry.command_id(SaFilterRegistry.key_for(&"", filter)))
    return descriptor.sentence if descriptor != null else "<no command>"


func test_a_filter_says_nothing_until_it_is_asked_to() -> void:
    assert_eq(SilentFilter.new().sentence(), "", "The base class answers empty")


func test_registration_writes_the_filters_sentence_onto_its_command() -> void:
    var said := SaidFilter.new("Sharpen", "Pulls the edges of the picture apart.")
    assert_true(_context().register_filter(said), "The filter registers through the public door")
    assert_eq(_sentence_on_command(said), "Pulls the edges of the picture apart.", "and its command carries the sentence")


func test_a_silent_filter_leaves_its_command_empty() -> void:
    var silent := SilentFilter.new()
    _context().register_filter(silent)
    assert_eq(_sentence_on_command(silent), "", "A filter that says nothing puts nothing on its command")


func test_the_browser_reads_the_same_string() -> void:
    var said := SaidFilter.new("Sharpen", "Pulls the edges of the picture apart.")
    _context().register_filter(said)
    var browser := SaFilterBrowser.new()
    browser.watch(_filters, _commands)
    assert_eq(
        browser.sentence_for(SaFilterRegistry.key_for(&"", said)),
        "Pulls the edges of the picture apart.",
        "The browser's detail column reads the filter's own string"
    )
    browser.free()


func test_the_filter_menu_row_says_the_sentence() -> void:
    var said := SaidFilter.new("Sharpen", "Pulls the edges of the picture apart.")
    _context().register_filter(said)
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = _filters
    bar.bind_commands(_commands)
    var list := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var button := list.label_button(SaMenu.key(SaFilterMenu.ID_FILTER_BASE))
    assert_not_null(button, "The filter has a row")
    if button != null:
        assert_true(
            button.tooltip_text.begins_with("Pulls the edges of the picture apart.\nAdded by "),
            "and the row's tooltip is the sentence, then the module, since a section mixes modules: %s" % button.tooltip_text
        )
    bar.free()


func test_a_silent_filters_row_still_says_who_registered_it() -> void:
    _context().register_filter(SilentFilter.new())
    var bar := TopMenuBar.new()
    bar._ready()
    var menu := bar.menu("Filter") as SaFilterMenu
    menu.filters = _filters
    bar.bind_commands(_commands)
    var list := menu.show_section(menu.section_item(SaFilterRegistry.OTHER))
    var button := list.label_button(SaMenu.key(SaFilterMenu.ID_FILTER_BASE))
    assert_not_null(button, "The silent filter has a row")
    if button != null:
        assert_true(
            button.tooltip_text.begins_with("Added by "), "and the row falls back to who added it: %s" % button.tooltip_text
        )
    bar.free()


func test_the_leading_comment_is_read_to_its_first_bare_line() -> void:
    var text := (
        "# Threshold, the shortest door.\n# Black or white by luminance.\n#\n# A second paragraph.\n"
        + "# SPDX-License-Identifier: GPL-3.0-or-later\n\nuniform float level = 0.5\n"
    )
    assert_eq(
        SaPixelFilter.leading_sentence(text),
        "Threshold, the shortest door. Black or white by luminance.",
        "The first paragraph, joined, and nothing after the bare hash"
    )


func test_the_licence_line_is_never_the_sentence() -> void:
    var text := "# SPDX-License-Identifier: GPL-3.0-or-later\n# Blurs the layer.\n\nuniform float r = 1.0\n"
    assert_eq(SaPixelFilter.leading_sentence(text), "Blurs the layer.", "The licence line is skipped")


func test_a_file_with_no_leading_comment_says_nothing() -> void:
    assert_eq(SaPixelFilter.leading_sentence("uniform float level = 0.5\n"), "", "No comment, no sentence")
    assert_eq(SaPixelFilter.leading_sentence(""), "", "and an empty file none either")


func test_a_pixel_filters_sentence_reaches_its_command_from_its_own_file() -> void:
    var pixel := SaPixelFilter.new(PIXEL_FIXTURE)
    var expected := SaPixelFilter.leading_sentence(FileAccess.get_file_as_string(PIXEL_FIXTURE))
    assert_false(expected.is_empty(), "The fixture opens with a comment")
    assert_eq(pixel.sentence(), expected, "The pixel filter reads its first paragraph")
    _context().register_filter(pixel)
    assert_eq(_sentence_on_command(pixel), expected, "and registration puts it on the command")
