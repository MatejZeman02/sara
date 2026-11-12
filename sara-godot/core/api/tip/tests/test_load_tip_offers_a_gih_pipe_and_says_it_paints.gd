## Load Tip offers GIMP's `.gih` and says it paints.
##
## The engine already paints a pipe, `SaTipCache.ahead` reads a `.gih` and the
## suite beside this one paints one, but the picker listed PNG and GBR only and
## Load Tip's tooltip called a `.gih` "not read yet". Here the filters are read
## as the picker is given them, the tooltip as the Brush Tip page shows it, and
## the single tip reader's refusal of a `.gih` as a painter would read it.
extends "res://tests/test_framework.gd"

const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")


## The filter lines of the picker, one string.
func _filters() -> String:
    return "\n".join(SaBrushTipMask.load_filters())


func _load_tip_tooltip() -> String:
    for spec: SaOptionSpec in ModuleScript.tip_options():
        if spec.key == &"tip_load":
            return spec.tooltip
    return ""


func test_the_picker_lists_gih_among_its_filters() -> void:
    var lines := SaBrushTipMask.load_filters()
    assert_true(_filters().contains("*.gih"), "A .gih is among the filters, read '%s'" % _filters())
    assert_true(lines[0].contains("*.gih"), "The Brush Tip line, the first, takes it, read '%s'" % lines[0])
    assert_true(_filters().contains("GIMP Pipe"), "and a GIMP Pipe line stands of its own, read '%s'" % _filters())
    assert_true(_filters().contains("*.png") and _filters().contains("*.gbr"), "The PNG and GBR lines stay")


func test_the_tooltip_says_a_gih_paints() -> void:
    var tip := _load_tip_tooltip()
    assert_false(tip.is_empty(), "Load Tip has a tooltip")
    assert_true(tip.contains(".gih"), "It names .gih, read '%s'" % tip)
    assert_false(tip.contains("not read yet"), "and does not say not read yet, read '%s'" % tip)
    assert_true(tip.contains("paints"), "It says a pipe paints, read '%s'" % tip)


func test_the_single_tip_reader_sends_a_gih_to_load_tip() -> void:
    var tip := SaTipImage.load_bytes(PackedByteArray([1, 2, 3]), "knife.gih")
    assert_false(tip.error.is_empty(), "The single tip reader still refuses a pipe")
    assert_true(tip.error.contains("Load Tip"), "and points at Load Tip, read '%s'" % tip.error)
    assert_true(tip.error.contains("knife.gih"), "by the file's name, read '%s'" % tip.error)
    assert_false(tip.error.contains("does not read"), "and does not say Sara cannot read it, read '%s'" % tip.error)
    assert_false(tip.error.contains("not read"), "nor that it is not read, read '%s'" % tip.error)
    assert_false(tip.error.contains("cannot read"), "nor that Sara cannot read it, read '%s'" % tip.error)
