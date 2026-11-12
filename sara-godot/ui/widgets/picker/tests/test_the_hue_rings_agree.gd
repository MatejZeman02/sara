## The HSV and OKHSV hue rings agree: yellow is locked to the bottom on both.
##
## The HSV ring started red at the right and went round in even sixths, the
## OKHSV ring started at Oklab hue zero, so yellow sat at 60 degrees on one and
## 110 on the other. Both now lay the ring out by the colour's own Oklab hue,
## turned so yellow is straight down, and the HSV ring reaches it piecewise
## through its six primaries. What is held here is that a named colour sits at
## one angle on both rings, that the gesture reads the angle back as the same
## colour, and that the two shaders carry the numbers the GDScript twin does,
## read out of their source because GDScript cannot call into a shader.
extends "res://tests/test_framework.gd"

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")
const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

const HSV_SHADER := "res://shaders/ui/hsv_picker.gdshader"
const OKHSV_SHADER := "res://shaders/ui/okhsv_picker.gdshader"

const NAMED := {
    "red": Color(1, 0, 0),
    "yellow": Color(1, 1, 0),
    "green": Color(0, 1, 0),
    "cyan": Color(0, 1, 1),
    "blue": Color(0, 0, 1),
    "magenta": Color(1, 0, 1),
}

var _shape_setting: String = ""


func before_each() -> void:
    _shape_setting = SaSettings.color_picker_shape


func after_each() -> void:
    SaSettings.color_picker_shape = _shape_setting


func _hsv_angle(c: Color) -> float:
    return SaPickerShape.ring_angle(c.h, true)


func _okhsv_angle(c: Color) -> float:
    return SaPickerShape.ring_angle(OkhsvConversionsScript.srgb_to_okhsv(c).x, false)


## The shortest way round between two angles in turns, so 0.999 and 0.001 are
## two thousandths apart rather than nearly a whole turn.
func _apart(a: float, b: float) -> float:
    var d := fposmod(a - b, 1.0)
    return minf(d, 1.0 - d)


## The ask's own test: yellow, red and blue, each at one angle on both rings,
## and yellow straight down. The other three primaries come along with them.
func test_a_named_colour_sits_at_one_angle_on_both_rings() -> void:
    for name: String in NAMED:
        var c: Color = NAMED[name]
        var hsv := _hsv_angle(c)
        var ok := _okhsv_angle(c)
        assert_true(_apart(hsv, ok) < 0.001, "%s sits at one angle, HSV %.4f and OKHSV %.4f" % [name, hsv, ok])
    assert_true(_apart(_hsv_angle(NAMED["yellow"]), 0.25) < 0.001, "and yellow is straight down on the HSV ring")
    assert_true(_apart(_okhsv_angle(NAMED["yellow"]), 0.25) < 0.001, "and on the OKHSV ring")


## Between two primaries the HSV ring keeps going the same way, so an orange
## sits between red and yellow on it as it does on the OKHSV ring.
func test_the_hsv_ring_turns_one_way_all_round() -> void:
    var last := SaPickerShape.ring_angle(0.0, true)
    var travelled := 0.0
    for step in range(1, 361):
        var here := SaPickerShape.ring_angle(float(step) / 360.0, true)
        var d := fposmod(here - last, 1.0)
        assert_true(d > 0.0 and d < 0.01, "a degree of HSV hue moves the ring a little forward, %.5f at %d" % [d, step])
        travelled += d
        last = here
    assert_almost_eq(travelled, 1.0, 1e-4, "and a whole turn of hue is a whole turn of the ring")


## The press reads the angle back through the inverse, so the hue under the
## pointer is the hue the ring was drawn with there.
func test_the_angle_comes_back_as_its_hue() -> void:
    for classic: bool in [true, false]:
        for step in range(0, 100):
            var h := float(step) / 100.0
            var back := SaPickerShape.ring_hue(SaPickerShape.ring_angle(h, classic), classic)
            var said := "hue %.2f comes back from its angle, classic %s" % [h, classic]
            assert_true(_apart(back, h) < 1e-5, said)


## A press straight down on the ring is yellow in either family.
func test_a_press_straight_down_is_yellow_on_both_rings() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    for kind: int in [SaPickerShape.Kind.WHEEL, SaPickerShape.Kind.HSV_SQUARE]:
        picker.shape.set_kind(kind)
        picker.shape.set_from_color(Color(0.3, 0.3, 0.9))
        picker.shape._drag_ring(Vector2(0.0, 100.0))
        var report := picker.shape.report()
        assert_true(_apart(float(report["ring_angle"]), 0.25) < 1e-4, "%s: the report says straight down" % report["kind"])
        var yellow := Color(1, 1, 0)
        var wanted := yellow.h
        if kind != SaPickerShape.Kind.HSV_SQUARE:
            wanted = OkhsvConversionsScript.srgb_to_okhsv(yellow).x
        var said := "%s: and the hue is yellow's, %.4f" % [report["kind"], float(report["hue"])]
        assert_true(_apart(float(report["hue"]), wanted) < 1e-3, said)
    dummy.free()


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The number after `const float <name> =` in a shader, or NAN.
func _shader_number(source: String, name: String) -> float:
    var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % name)
    var m := re.search(source)
    return float(m.get_string(1)) if m != null else NAN


## The two shaders and the GDScript twin hold one yellow and one set of
## primaries, so the ring drawn and the ring pressed cannot drift apart.
func test_the_shaders_hold_the_twins_numbers() -> void:
    var hsv := _source(HSV_SHADER)
    var ok := _source(OKHSV_SHADER)
    for source: String in [hsv, ok]:
        var yellow_hue := _shader_number(source, "RING_YELLOW_HUE")
        assert_almost_eq(yellow_hue, SaPickerShape.RING_YELLOW_HUE, 1e-6, "yellow's hue is the twin's")
        var yellow_angle := _shader_number(source, "RING_YELLOW_ANGLE")
        assert_almost_eq(yellow_angle, SaPickerShape.RING_YELLOW_ANGLE, 1e-6, "and so is its angle")
    var m := RegEx.create_from_string("PRIMARY_HUES\\[7\\] = float\\[7\\]\\(([^)]*)\\)").search(hsv)
    assert_true(m != null, "the HSV shader lists the primaries")
    if m == null:
        return
    var listed := m.get_string(1).split(",")
    assert_eq(listed.size(), 7, "six primaries and red again a turn on")
    for i in range(6):
        assert_almost_eq(float(listed[i].strip_edges()), SaPickerShape.HSV_PRIMARY_HUES[i], 1e-6, "primary %d is the twin's" % i)
    var red_again := SaPickerShape.HSV_PRIMARY_HUES[0] + 1.0
    assert_almost_eq(float(listed[6].strip_edges()), red_again, 1e-6, "and the seventh is red a turn on")
    # The twin's primaries are the Oklab hues of the colours they name.
    var names := ["red", "yellow", "green", "cyan", "blue", "magenta"]
    for i in range(6):
        var hue := OkhsvConversionsScript.srgb_to_okhsv(NAMED[names[i]]).x
        assert_true(_apart(hue, SaPickerShape.HSV_PRIMARY_HUES[i]) < 1e-4, "%s's Oklab hue is %.5f" % [names[i], hue])
