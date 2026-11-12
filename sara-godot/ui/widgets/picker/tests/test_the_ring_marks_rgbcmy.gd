## Yellow was not recognised on the hue circle, so grey small marks indicate
## where RGBCMY are.
##
## Every shape with a ring carries six grey marks, and the HSL square carries
## them on its hue bar. What is held here is that each shape's ring, asked
## where it puts pure red, yellow, green, cyan, blue and magenta, finds a mark
## there within a degree, the angle read from the colour itself through that
## shape's own family rather than from the list the marks were made from.
## The shaders cannot be called from GDScript, so their source is read for the
## uniform and for the ring drawing through it. The shot shows the pixels.
extends "res://tests/test_framework.gd"

const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")
const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")

const HSV_SHADER := "res://shaders/ui/hsv_picker.gdshader"
const OKHSV_SHADER := "res://shaders/ui/okhsv_picker.gdshader"

## A degree, in turns.
const DEGREE := 1.0 / 360.0

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


func _picker() -> SaColorPicker:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    return picker


## The shortest way round between two angles in turns.
func _apart(a: float, b: float) -> float:
    var d := fposmod(a - b, 1.0)
    return minf(d, 1.0 - d)


## The angle *shape*'s ring gives *c*, from the colour's hue in that shape's
## own family.
func _angle_of(c: Color, classic: bool) -> float:
    if classic:
        return SaPickerShape.ring_angle(c.h, true)
    return SaPickerShape.ring_angle(OkhsvConversionsScript.srgb_to_okhsv(c).x, false)


## How far the nearest of *marks* is from *angle*, in turns.
func _nearest(marks: PackedFloat32Array, angle: float) -> float:
    var best := 1.0
    for m: float in marks:
        best = minf(best, _apart(m, angle))
    return best


## The ask's own test: on every shape with a ring, each of the six colours
## has a mark where that shape's ring puts it.
func test_every_ring_marks_the_six_colours_where_they_sit() -> void:
    var picker := _picker()
    var ringed := 0
    for kind in range(SaPickerShape.KIND_KEYS.size()):
        picker.shape.set_kind(kind)
        var report := picker.shape.report()
        var classic := SaPickerShape.is_classic(kind)
        # The disc's rim does the ring's job, so its marks are on the area's
        # own material, and the HSL square has the bar instead.
        var mat := picker.shape.ring_rect.material as ShaderMaterial
        if kind == SaPickerShape.Kind.OKHSL:
            mat = picker.shape.area_rect.material as ShaderMaterial
        elif not report["ring_visible"]:
            continue
        ringed += 1
        var marks: PackedFloat32Array = mat.get_shader_parameter("mark_angles")
        assert_eq(marks.size(), 6, "%s: the ring carries six marks" % report["kind"])
        for name: String in NAMED:
            var angle := _angle_of(NAMED[name], classic)
            var off := _nearest(marks, angle)
            assert_true(off < DEGREE, "%s: %s at %.4f has a mark %.5f turns away" % [report["kind"], name, angle, off])
    assert_eq(ringed, 6, "the wheel, the disc, both triangles and both HSV shapes have a ring")
    picker.get_parent().free()


## The HSL square's bar runs the HSV hue down it, so a colour's place on it is
## its own HSV hue, and the bar's marks are read through the classic shader's
## angle to hue, whose GDScript twin is ring_hue.
func test_the_hue_bar_marks_the_six_colours() -> void:
    var picker := _picker()
    picker.shape.set_kind(SaPickerShape.Kind.HSL_SQUARE)
    assert_true(picker.shape.report()["hue_bar_visible"], "the HSL square shows its bar")
    var marks: PackedFloat32Array = (picker.shape.hue_bar.material as ShaderMaterial).get_shader_parameter("mark_angles")
    var along := PackedFloat32Array()
    for m: float in marks:
        along.append(SaPickerShape.ring_hue(m, true))
    for name: String in NAMED:
        var c: Color = NAMED[name]
        var off := _nearest(along, c.h)
        assert_true(off < DEGREE, "the bar has a mark at %s's hue %.4f, %.5f away" % [name, c.h, off])
    picker.get_parent().free()


## Six marks, and six apart: no two colours share one, so no mark stands at
## an even sixth that happens to be near a colour.
func test_the_marks_are_six_different_places() -> void:
    var marks := SaPickerShape.mark_angles()
    for i in range(marks.size()):
        for j in range(i + 1, marks.size()):
            assert_true(_apart(marks[i], marks[j]) > 0.05, "marks %d and %d stand apart" % [i, j])
    assert_true(_apart(marks[1], 0.25) < 1e-5, "and yellow's is straight down")


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## Both shaders declare the uniform and draw the ring through it, the Oklab
## one on the disc's rim as well and the classic one on the bar.
func test_both_shaders_draw_the_marks() -> void:
    for path: String in [OKHSV_SHADER, HSV_SHADER]:
        var source := _source(path)
        assert_true(source.contains("uniform float mark_angles[6];"), "%s takes the six angles" % path)
        assert_true(source.contains("mark_cover(turn, dist, inner_radius"), "%s draws them on its ring" % path)
    assert_true(_source(OKHSV_SHADER).contains("mark_cover(atan(d.y, d.x)"), "the disc draws them on its rim")
    assert_true(_source(HSV_SHADER).contains("bar_mark_cover(UV)"), "the bar draws them")
