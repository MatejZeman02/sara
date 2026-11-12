## Sara on a phone turns with it and fits upright.
##
## Two things the phone needs, read here so a change to either is caught
## without an emulator. First, `project.godot` lets the window follow the
## handset's sensor in all four directions: Godot's default for
## `display/window/handheld/orientation` is Landscape, which pins a phone on
## its side however the painter holds it.
##
## Second, the shipped default layout answers the two shapes a Pixel 6a hands
## Sara. Its 1080 by 2400 pixels at the 1.35 the device reports are a logical
## host of 800 by 1778, taller than anything the default was written for, and
## turned it is 2400 by 1080 at 1.80, a host of 1333 by 600, shorter than any
## of them. On both the file's `close_order` closes dockers until the rest
## stand whole on the host with none overlapping and the painting keeps
## `SaDockerLayoutFit.PAINTING_SHARE` of the width. A docker the fit closed is
## still reachable from the Window menu, which is what the phone's shots show.
##
## The shots are `scenarios/sara-on-a-phone-turns-with-it-and-fits-upright.json`.
extends "res://tests/test_framework.gd"

## The first row below the phone's bar, `MainDockers.below_bar` with the second
## row on: the bar is 64 rows there and the dockers in the shots
## stand at 79 in both orientations.
const TOP := 79

## The phone's logical hosts, upright and on its side, measured on a Pixel 6a
## emulator: `root_viewport_rect` of the dumps. The
## 1080 by 2400 pixels come out as 800 by 1778 at the 1.35 the device reports
## upright, and 2400 by 1080 as 1333 by 600 at the 1.80 it reports on its side.
const UPRIGHT := Vector2i(800, 1778)
const ON_ITS_SIDE := Vector2i(1333, 600)

## Each open docker's floor as the fit is handed it at scale 1, the same table
## `test_the_default_layout_fits_the_screen` keeps, because the shipped file
## does not carry every floor itself.
const FLOORS := {
    "ToolBoxDocker": Vector2i(56, 76),
    "ToolOptionsDocker": Vector2i(206, 255),
    "ColorDocker": Vector2i(214, 212),
    "LayersDocker": Vector2i(269, 212),
    "BrushPresetsDocker": Vector2i(295, 212),
}


## The shipped default's open dockers, section to `{"rect", "min"}`.
func _shipped() -> Dictionary:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS), OK, "the shipped default reads")
    var out: Dictionary = {}
    for section in cfg.get_sections():
        if String(section).begins_with("_") or not bool(cfg.get_value(section, "visible", false)):
            continue
        var rect := Rect2i(cfg.get_value(section, "position"), cfg.get_value(section, "size"))
        var floor_size: Vector2i = cfg.get_value(section, SaDockerLayoutRefit.FLOOR_SIZE, Vector2i())
        out[section] = {"rect": rect, "min": floor_size.max(FLOORS.get(section, Vector2i.ONE))}
    return out


## The fit of the shipped default on *host*, with the file's close order.
func _fit(host: Vector2i) -> SaDockerLayoutFit:
    var cfg := ConfigFile.new()
    cfg.load(DockerLayoutStore.SHIPPED_DEFAULTS)
    var order: Array = cfg.get_value(DockerLayoutStore.META_SECTION, SaDockerLayoutRefit.CLOSE_ORDER, [])
    var written_for: Vector2i = cfg.get_value(DockerLayoutStore.META_SECTION, DockerLayoutStore.META_WRITTEN_FOR, Vector2i())
    return SaDockerLayoutFit.new(host, TOP, written_for, order)


## *host* less the rows the status line takes from its foot, the host the store
## hands the fit.
static func _above_the_line(host: Vector2i) -> Vector2i:
    return host - Vector2i(0, SaStatusLine.rows_taken())


## Asserts the fit on *host* leaves every docker whole on the host, none over
## another, each above its floor, and the painting its share of the width.
func _assert_fits(viewport: Vector2i) -> Dictionary:
    var host := _above_the_line(viewport)
    var placed := _fit(host).place(_shipped())
    var sections := placed.keys()
    sections.sort()
    var spans: Array[Vector2i] = []
    for rect: Rect2i in placed.values():
        spans.append(Vector2i(rect.position.x, rect.end.x))
    var painting := host.x - SaWorkspacePage.covered_width(spans)
    var share := "%d of %d" % [painting, host.x]
    assert_true(painting >= host.x * SaDockerLayoutFit.PAINTING_SHARE, "the painting keeps %s at %s" % [share, host])
    var screen := Rect2i(Vector2i(0, TOP), host - Vector2i(0, TOP))
    var floors := _shipped()
    for i in sections.size():
        var rect: Rect2i = placed[sections[i]]
        var floor_size: Vector2i = floors[sections[i]]["min"]
        var floored := rect.size.x >= floor_size.x and rect.size.y >= floor_size.y
        assert_true(screen.encloses(rect), "%s %s is wholly on %s below the bar" % [sections[i], rect, host])
        assert_true(floored, "%s %s keeps its floor at %s" % [sections[i], rect, host])
        for j in range(i + 1, sections.size()):
            assert_false(rect.intersects(placed[sections[j]]), "%s and %s overlap at %s" % [sections[i], sections[j], host])
    return placed


## The one line of `project.godot` the phone depends on: without it the window is
## pinned to Landscape and a painter holding the phone upright paints sideways.
func test_the_window_follows_the_handsets_sensor_in_all_four_directions() -> void:
    var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", DisplayServer.SCREEN_LANDSCAPE))
    assert_eq(orientation, int(DisplayServer.SCREEN_SENSOR), "project.godot lets the handheld window turn with the phone")


func test_the_default_layout_fits_a_phone_held_upright() -> void:
    var placed := _assert_fits(UPRIGHT)
    var open := placed.keys()
    open.sort()
    assert_eq(open, ["ColorDocker", "LayersDocker", "ToolBoxDocker"], "the dockers a phone upright keeps open")


func test_the_default_layout_fits_a_phone_on_its_side() -> void:
    var placed := _assert_fits(ON_ITS_SIDE)
    var open := placed.keys()
    open.sort()
    assert_eq(
        open,
        ["BrushPresetsDocker", "ColorDocker", "ToolBoxDocker", "ToolOptionsDocker"],
        "the dockers a phone on its side keeps open"
    )
