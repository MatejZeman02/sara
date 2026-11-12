## The stock Pink theme's sliders are dark pink.
##
## Sliders read green under stock Pink while they should be dark pink.
## Pink ships `slider_handle` as #7A4C62 and `slider_hover` as #7A4C64.
## What is held here is that every slider part reads
## them under stock Pink, the app's `FactorSlider` and the engine's `HSlider`,
## `VSlider` and `ProgressBar`, that none reads the green `accent_gauge`, and
## that a fork of Pink keeps the states Pink holds rather than deriving them
## from the gauge again.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const HANDLE := Color("#7A4C62")
const HOVER := Color("#7A4C64")

## Class -> the engine's stylebox name -> the colour it has to read under Pink.
const ENGINE_BOXES := {
    "HSlider": {"grabber_area": HANDLE, "grabber_area_highlight": HOVER},
    "VSlider": {"grabber_area": HANDLE, "grabber_area_highlight": HOVER},
    "ProgressBar": {"fill": HANDLE},
}

var _saved_theme: String = "default"
var _saved_shared: Theme = null
var _saved_path: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_shared = SaUI.shared_theme
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_u563.cfg"))
    SaTheme.use_named("pink")


func after_each() -> void:
    _remove_forks()
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_u563.cfg")))


func _remove_forks() -> void:
    for id in SaTheme.custom_ids():
        if id.begins_with(SaTheme.CUSTOM_PREFIX + "test-u563"):
            SaTheme.delete_custom(id)
    var kept := DirAccess.open(SaTheme.deleted_dir())
    if kept == null:
        return
    for file_name in kept.get_files():
        if file_name.begins_with("test-u563"):
            kept.remove(file_name)


func _near(a: Color, b: Color) -> bool:
    return a.is_equal_approx(b) or (absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002)


func test_pink_holds_the_two_slider_colours() -> void:
    var palette := SaTheme.palette
    assert_eq(SaTheme.palette_id, "pink", "stock Pink is the palette in use")
    assert_true(_near(palette.slider_handle, HANDLE), "slider_handle is #7A4C62, reads %s" % palette.slider_handle.to_html(false))
    assert_true(_near(palette.slider_hover, HOVER), "slider_hover is #7A4C64, reads %s" % palette.slider_hover.to_html(false))
    assert_true(palette.overridden_states.has("slider_handle"), "and Pink holds the handle")
    assert_true(palette.overridden_states.has("slider_hover"), "and the hover")


func test_a_factor_sliders_fill_is_dark_pink_and_not_the_gauge() -> void:
    var slider := FactorSlider.new()
    var fill := slider._style_fill
    assert_true(_near(fill.bg_color, HANDLE), "a FactorSlider's fill reads #7A4C62, reads %s" % fill.bg_color.to_html(false))
    assert_false(_near(fill.bg_color, SaTheme.palette.accent_gauge), "and not the green gauge")
    slider.free()


func test_the_engines_slider_boxes_are_dark_pink_and_not_the_gauge() -> void:
    SaUI.init_global_theme(null)
    var theme := SaUI.shared_theme
    var gauge := SaTheme.palette.accent_gauge
    for cls: String in ENGINE_BOXES:
        for box_name: String in ENGINE_BOXES[cls]:
            var label := "%s.%s" % [cls, box_name]
            var flat := theme.get_stylebox(box_name, cls) as StyleBoxFlat
            assert_not_null(flat, "%s is a flat box" % label)
            if flat == null:
                continue
            var wanted: Color = ENGINE_BOXES[cls][box_name]
            var read := flat.bg_color.to_html(false)
            assert_true(_near(flat.bg_color, wanted), "%s reads %s, reads %s" % [label, wanted.to_html(false), read])
            assert_false(_near(flat.bg_color, gauge), "%s is not the green gauge" % label)


func test_the_slider_door_draws_every_part_dark_pink() -> void:
    assert_true(_near(SaTheme.make_slider_style("handle").bg_color, HANDLE), "the handle box SaTheme makes is #7A4C62")
    assert_true(_near(SaTheme.make_slider_style("hover").bg_color, HOVER), "and the hover box #7A4C64")


## A fork of Pink is where the green appeared: a fork that dropped Pink's
## held states would derive the slider from the gauge again.
func test_a_fork_of_pink_keeps_its_held_states() -> void:
    var held := Array(SaTheme.palette.overridden_states)
    var id := SaTheme.fork("Test Pink")
    assert_eq(SaTheme.palette_id, id, "the fork is in use")
    assert_eq(Array(SaTheme.palette.overridden_states), held, "and holds what Pink holds")
    assert_true(_near(SaTheme.palette.slider_handle, HANDLE), "so its slider stays dark pink")
    var reloaded := ResourceLoader.load(SaTheme.custom_path(id), "SaPalette", ResourceLoader.CACHE_MODE_IGNORE) as SaPalette
    assert_not_null(reloaded, "the fork's file loads")
    if reloaded != null:
        reloaded.derive_states()
        assert_true(_near(reloaded.slider_handle, HANDLE), "and read back from its file it is dark pink too")
        assert_false(_near(reloaded.slider_handle, reloaded.accent_gauge), "never the gauge")
