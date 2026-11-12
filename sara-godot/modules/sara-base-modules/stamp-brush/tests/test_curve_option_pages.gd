## The stamp brush's editor surface is one class the module asks, not a half of
## the module.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `test_brush_options.gd` holds what the pages are and in what order. What is
## here is the cut: the curve pages the module declares are exactly the ones
## `SaCurveOptionPages` answers, first and in its order, and every one of them
## carries that class's three doors rather than a copy left behind in
## `module.gd`. `tests/test_file_length.gd`'s smear check is what says the cut
## was by responsibility and not by count.
extends "res://tests/test_framework.gd"

## By path, the way `test_brush_options.gd` reaches it, since the module has no
## `class_name` of its own.
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")


func _keys(specs: Array[SaOptionSpec]) -> Array[StringName]:
    var out: Array[StringName] = []
    for spec: SaOptionSpec in specs:
        out.append(spec.key)
    return out


## The module's list opens with the class's pages and holds no curve page of its
## own after them, so a curve option added in `module.gd` rather than in the class
## is the red line here.
func test_the_module_declares_the_curve_pages_the_class_answers() -> void:
    var pages := SaCurveOptionPages.rows()
    assert_true(pages.size() > 0, "the class answers the curve pages")
    var declared: Array[SaOptionSpec] = []
    declared.assign(ModuleScript.brush_options())
    var curves: Array[SaOptionSpec] = []
    for spec: SaOptionSpec in declared:
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            curves.append(spec)
    assert_eq(_keys(curves), _keys(pages), "every curve page the module declares is the class's, in its order")
    # The ones before Airbrush Rate follow the two tip previews that open the
    # tip page and General, and come above General's rows, because a page
    # appears in the editor where its first row is declared.
    var cut := 0
    while cut < pages.size() and pages[cut].key != SaCurveOptionPages.AFTER_MASKING:
        cut += 1
    assert_true(cut < pages.size(), "Airbrush Rate is one of the class's pages")
    var previews := ModuleScript.tip_previews().size()
    var head: Array[SaOptionSpec] = []
    head.assign(declared.slice(previews, previews + cut))
    assert_eq(_keys(head), _keys(pages.slice(0, cut)), "and those before Airbrush Rate come next, above General's rows")


## Each page's widget, binding and row text are the curve option control's
## methods, which is what lets the skeleton build and describe one without
## naming it. The control owns them and the class answers for its doors.
func test_every_curve_page_carries_the_class_s_three_doors() -> void:
    for spec: SaOptionSpec in SaCurveOptionPages.rows():
        assert_eq(spec.build_control.get_method(), &"build_control", "%s builds through the class" % spec.key)
        assert_eq(spec.bind_value.get_method(), &"bind_control", "%s binds through the class" % spec.key)
        assert_eq(spec.describe_value.get_method(), &"describe", "%s is described by the class" % spec.key)


## The doors work from the spec alone: the control built is the curve widget, a
## null value binds a throwaway option, and the row text follows the option's
## own switch.
func test_the_doors_build_bind_and_describe_from_the_spec() -> void:
    var spec: SaOptionSpec = SaCurveOptionPages.rows()[0]
    var control: Control = spec.build_control.call(spec, Callable())
    assert_true(control is SaCurveOptionControl, "the page is the curve widget")
    spec.bind_value.call(control, null)
    control.free()

    assert_eq(spec.describe_value.call(null), "None", "no option is unset")
    var option := SaCurveOption.create_default()
    option.enabled = false
    assert_eq(spec.describe_value.call(option), "Off", "a switched-off option reads Off rather than a strength")
