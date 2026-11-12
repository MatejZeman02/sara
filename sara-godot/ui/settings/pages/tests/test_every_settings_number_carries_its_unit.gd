## Every number in Preferences carries its unit in the control,
## with no more decimals than its step.
##
## The sweep found Autosave every reading 2.0 with its minutes only in the hint,
## Settle and Cap carrying "(s)" and "(MB)" in their titles, Summoned docker
## waits cut to "1000 m", UI scale and Font size putting their value in the title
## and none beside the slider, and Light direction and Relief strength reading
## 315.00° and 4.00. Each readout is read here off the page a painter opens, at
## the value the request names, and the wait's field is measured after the page
## was built off the tree and put under a theme, which is the order the window
## builds it in and the order that cut it.
extends "res://tests/test_framework.gd"

## The text size the wait's field is measured at, over twice the engine's own.
const TEXT_SIZE := 40

var _saved: Dictionary = {}
var _hosts: Array[Node] = []


func before_each() -> void:
    _saved = {
        "autosave_interval_minutes": SaSettings.autosave_interval_minutes,
        "recorder_settle_seconds": SaSettings.recorder_settle_seconds,
        "recorder_cap_bytes": SaSettings.recorder_cap_bytes,
        "relief_light_angle": SaSettings.relief_light_angle,
        "relief_strength": SaSettings.relief_strength,
    }
    _hosts.clear()


func after_each() -> void:
    for host: Node in _hosts:
        if is_instance_valid(host):
            host.free()
    for key: String in _saved:
        SaSettings.set(key, _saved[key])


## *page* in the tree, so a readout and a field are measured as drawn.
func _in_tree(page: Control) -> Control:
    var host := SaMake.column(EventBus, "Host")
    host.add_child(page)
    _hosts.append(host)
    return page


## The number beside the slider of row *key*, the text a painter reads.
func _readout(page: SaSettingsPage, key: StringName) -> String:
    var row := page.page.row(key)
    assert_not_null(row, "the page has the %s row" % key)
    if row == null:
        return ""
    var readout := row.control.get_parent().get_node_or_null(NodePath(SaPage.READOUT_NAME)) as Label
    assert_not_null(readout, "and %s draws a readout beside its slider" % key)
    return readout.text if readout != null else ""


func test_autosave_every_reads_in_minutes() -> void:
    SaSettings.autosave_interval_minutes = 2.0
    var page := _in_tree(SaFilesPage.new()) as SaFilesPage
    var row := page.page.row(&"autosave_every")
    assert_eq(row.label, "Autosave every", "the title is the row's words alone")
    assert_eq(_readout(page, &"autosave_every"), "2 min", "and the minutes are in the control, with no 2.0")
    row.drive(0.5)
    assert_eq(_readout(page, &"autosave_every"), "0.5 min", "a half minute keeps the decimal its step has")
    assert_almost_eq(SaSettings.autosave_interval_minutes, 0.5, 1e-6, "and is what the setting holds")


func test_settle_and_cap_carry_their_units_beside_the_slider() -> void:
    SaSettings.recorder_settle_seconds = 2.0
    SaSettings.recorder_cap_bytes = 1024 * 1048576
    var page := _in_tree(SaRecorderPage.new()) as SaRecorderPage
    assert_eq(page.page.row(&"settle").label, "Pause before frame", "Pause before frame has no (s) in its title")
    assert_eq(_readout(page, &"settle"), "2 s", "the seconds are in the readout")
    assert_eq(page.page.row(&"cap").label, "Size limit", "Size limit has no (MB) in its title")
    assert_eq(_readout(page, &"cap"), "1024 MB", "the megabytes are in the readout, with no 1024.00")


func test_the_relief_reads_315_degrees_and_a_strength_of_4() -> void:
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    var page := _in_tree(SaDisplayPage.new()) as SaDisplayPage
    assert_eq(_readout(page, &"relief_light_angle"), "315°", "Light direction reads 315° and not 315.00°")
    assert_eq(_readout(page, &"relief_strength"), "4", "Relief strength reads 4 and not 4.00")
    page.page.row(&"relief_strength").drive(4.25)
    assert_eq(_readout(page, &"relief_strength"), "4.25", "and a quarter step shows the two decimals it has")


## The page is built off the tree, the way `SaSettingsWindow` builds one, and
## then put under a theme that draws text at a size the engine's own does not.
## The field was fitted to the engine's sixteen and never again, because the
## fit read the field's theme cache from inside a signal sent before the cache
## was refreshed.
func test_the_wait_reads_1000_ms_whole_at_the_windows_text_size() -> void:
    var borrow := SaDockerBorrow.new()
    var saved_dwell := borrow.dwell_ms
    borrow.dwell_ms = 1000
    var page := SaDockersPage.new()
    var row := page.page.row(&"borrow_dwell")
    var spin := row.control as SpinBox
    var line := spin.get_line_edit()
    # Large enough that the four characters the engine gives a field are not
    # wide enough by themselves, so the fit is what holds the number.
    var theme := Theme.new()
    theme.default_font_size = TEXT_SIZE
    theme.set_font_size(&"font_size", &"LineEdit", TEXT_SIZE)
    var host := SaMake.column(EventBus, "ThemedHost")
    host.theme = theme
    _hosts.append(host)
    host.add_child(page)
    var shown := "1000 ms"
    assert_eq(line.get_theme_font_size(&"font_size"), TEXT_SIZE, "the field draws at the theme's size")
    assert_eq(line.text, shown, "the field reads %s, one space and the unit, where it read 1000  ms" % shown)
    var font := line.get_theme_font(&"font")
    var wanted := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
    var room := line.get_combined_minimum_size().x - line.get_theme_stylebox(&"normal").get_minimum_size().x
    assert_true(room >= wanted, "the field holds %s at %d points, %.0f for %.0f" % [shown, TEXT_SIZE, room, wanted])
    var widest := font.get_string_size("10000 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
    assert_true(room >= widest, "and the widest wait the row allows, %.0f for %.0f" % [room, widest])
    borrow.dwell_ms = saved_dwell


func test_the_interface_sliders_read_a_percentage_beside_the_track() -> void:
    var page := _in_tree(SaWorkspacePage.new()) as SaWorkspacePage
    for key: String in ["ui_scale", "font_size"]:
        var row := page.page.row(StringName(key))
        var slider := page.slider_named(key)
        assert_false(row.label.contains("%"), "%s's title carries no number, '%s'" % [key, row.label])
        # Moved under a held grabber, so the setting behind it, which rescales
        # the running suite's interface, is never written.
        slider.drag_started.emit()
        slider.value = 1.0
        slider.value_changed.emit(slider.value)
        var readout := slider.get_parent().get_node(NodePath(SaPage.READOUT_NAME)) as Label
        assert_eq(readout.text, "100%", "and %s reads 100%% beside its slider" % key)
        slider.drag_ended.emit(false)
    assert_eq(SaWorkspacePage.percent(1.25), "125%", "the welcome window's row formats it the same way")


func test_a_row_that_never_asked_takes_its_decimals_from_its_step() -> void:
    var row := SaPageRow.new()
    assert_eq(row.decimal_places, -1, "a row starts on its step")
    row.step(15.0)
    assert_eq(row.shown_places(), 0, "a step of 15 shows none")
    row.step(0.25)
    assert_eq(row.shown_places(), 2, "a quarter shows two")
    row.step(0.5)
    assert_eq(row.shown_places(), 1, "a half shows one")
    row.decimals(3)
    assert_eq(row.shown_places(), 3, "and a row that asked keeps what it asked for")
