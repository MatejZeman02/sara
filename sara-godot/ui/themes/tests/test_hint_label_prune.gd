## A settings row's hint label bound its font colour through
## `SaTheme.bind_font`, and only a theme switch dropped the dead entry.
## A page built and freed many times between switches left
## one `WeakRef` and one array entry behind a build, one per explained row.
extends "res://tests/test_framework.gd"


## What the row binds to. A member of the page rather than a static, because
## the page holds it and nothing holds the page back.
class Knobs:
    extends RefCounted

    var enabled: bool = true


## A page with one row that carries an explanation, the shape that leaked.
class ExplainedPage:
    extends SaSettingsPage

    var knobs := Knobs.new()

    func build(ui: SaPage) -> void:
        var rows := ui.section("Explained")
        rows.toggle("Enabled", knobs, ^"enabled").explain("What the switch does.")


var _saved_theme: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


func test_fifty_builds_of_an_explained_row_leave_the_object_count_where_it_was() -> void:
    SaTheme.use_named("default")
    # One build first, so a cache the first page fills is not read as a leak.
    ExplainedPage.new().free()
    var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
    for i in 50:
        ExplainedPage.new().free()
    var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
    assert_eq(after, before, "the hint label's WeakRef went with its page, with no theme switch in between")


## The prune must not cost the live case anything: a label still on screen
## keeps following a switch exactly as it did before.
func test_a_live_hint_label_still_follows_a_theme_switch() -> void:
    SaTheme.use_named("default")
    var label := SaSettingsRows.hint_label("What the switch does.")
    SaTheme.use_named("photoshop")
    var photoshop := load(SaTheme.PALETTES["photoshop"]) as SaPalette
    assert_eq(label.get_theme_color("font_color"), photoshop.text_muted, "a live hint label repaints on the switch")
    label.free()
