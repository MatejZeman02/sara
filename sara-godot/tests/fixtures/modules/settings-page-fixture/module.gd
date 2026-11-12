## A module that adds one page to Preferences and nothing else.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, and
## `ui/settings/tests/test_a_module_registers_a_preferences_page.gd` registers it by
## hand into registries of its own.
##
## The page extends `SaSettingsPage`, the base class, the way a module author is told
## to write one: it declares a section and a row and the base draws them. The
## word in the row is one no page of the skeleton carries, which is what lets a
## search prove the module's page is indexed.
##
## The second page names the group it goes under, Painting, and the first names
## none and goes under Files and system, so the suite reads both halves of the
## door's group argument.
extends SaModule

const PAGE_ID := &"settings_page_fixture"
const PAGE_TITLE := "Fixture Page"
const ROW_WORD := "wombat"
const PAINTING_PAGE_ID := &"settings_page_fixture_painting"
const PAINTING_PAGE_TITLE := "Fixture Painting Page"
const PAINTING_ROW_WORD := "numbat"


func get_id() -> StringName:
    return &"settings-page-fixture"


func get_name() -> String:
    return "Settings Page Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_settings_page(PAGE_ID, PAGE_TITLE, _build_page)
    ctx.register_settings_page(PAINTING_PAGE_ID, PAINTING_PAGE_TITLE, _build_painting_page, &"painting")


static func _build_page(_window: Node) -> Control:
    return FixturePage.new(ROW_WORD)


static func _build_painting_page(_window: Node) -> Control:
    return FixturePage.new(PAINTING_ROW_WORD)


class FixturePage:
    extends SaSettingsPage

    ## What the row writes to, a page's own member because a fixture has no
    ## setting to keep.
    var enabled := false

    ## The word the page's one row says, which a search finds it by.
    var _word := ""

    func _init(word: String) -> void:
        _word = word
        super()

    func build(ui: SaPage) -> void:
        var rows := ui.section("Fixture")
        rows.toggle("A %s row" % _word, self, ^"enabled")
