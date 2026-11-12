## A group's attached filters run over the group's composite, and a
## pass-through group isolates while it carries an enabled one: a filter runs over a composite and a
## pass-through group has none. `SaLayerStack.isolates` says so and the `isolated` flag is
## never written for it, so a detach gives the pass-through back.
##
## Two members in Multiply tell the two apart. Passed through, they multiply
## the background. Isolated, the first multiplies an empty intermediate, which
## returns the source, and only the second multiplies anything.
##
## Every case runs twice, with the group folded into a cache and with a member
## active, where the group is a scope rendered through a scratch.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const PALE := Color(0.5, 0.5, 1.0, 1.0)
## Grey background times red times pale.
const PASSED_THROUGH := Color(0.25, 0.0, 0.0, 1.0)
## Red over nothing, times pale, and then the invert of that.
const ISOLATED := Color(0.5, 0.0, 0.0, 1.0)
const ISOLATED_INVERTED := Color(0.5, 1.0, 1.0, 1.0)
const AT := Vector2i(300, 10)


func _member(doc: SaDocument, layer_name: String, colour: Color) -> SaLayer:
    var ops := SaLayerOps.new(doc)
    var member := ops.add()
    member.name = layer_name
    ops.set_blend_mode(member, &"multiply")
    doc.fill_layer(colour, member)
    return member


func _shows(easel: SaEasel, expected: Color, what: String) -> void:
    var found := Bench.texel(easel.output, AT)
    assert_almost_eq(found.r, expected.r, 0.02, "%s, red: %s" % [what, found])
    assert_almost_eq(found.g, expected.g, 0.02, "%s, green: %s" % [what, found])
    assert_almost_eq(found.b, expected.b, 0.02, "%s, blue: %s" % [what, found])


func _check(inside: bool) -> void:
    var easel: SaEasel = Bench.easel(Vector2i(512, 256))
    var doc := easel.document
    var red := _member(doc, "Red", RED)
    var pale := _member(doc, "Pale", PALE)
    var group := SaLayerOps.new(doc).group_layers([red, pale])
    doc.set_active_layer(pale if inside else doc.get_node("Layer 1") as SaLayer)
    var where := " (scope)" if inside else " (folded)"
    Bench.composite(easel)
    assert_false(SaLayerStack.isolates(group), "A new group passes through" + where)
    _shows(easel, PASSED_THROUGH, "and its members multiply the background" + where)

    var ops := SaFilterOps.new(doc)
    var record := ops.attach(group, Bench.INVERT)
    Bench.composite(easel)
    assert_true(SaLayerStack.isolates(group), "An attached filter isolates the group" + where)
    assert_false(group.isolated, "without writing the painter's flag" + where)
    _shows(easel, ISOLATED_INVERTED, "The members composite against the group's own intermediate, then the filter" + where)

    ops.attach(group, Bench.INVERT)
    Bench.composite(easel)
    _shows(easel, ISOLATED, "Two inverts leave the isolated composite" + where)

    for held: SaAttachedFilter in group.filters.duplicate():
        ops.set_enabled(held, false)
    Bench.composite(easel)
    assert_false(SaLayerStack.isolates(group), "Filters that are off isolate nothing" + where)
    _shows(easel, PASSED_THROUGH, "and the group passes through again" + where)

    ops.set_enabled(record, true)
    Bench.composite(easel)
    _shows(easel, ISOLATED_INVERTED, "One back on isolates again" + where)

    for held: SaAttachedFilter in group.filters.duplicate():
        ops.detach(group, held)
    Bench.composite(easel)
    assert_false(SaLayerStack.isolates(group), "Detaching the last filter gives the pass-through back" + where)
    _shows(easel, PASSED_THROUGH, "with nothing else to do" + where)
    easel.free()


func test_a_filtered_pass_through_group_isolates_folded() -> void:
    _check(false)


func test_a_filtered_pass_through_group_isolates_as_a_scope() -> void:
    _check(true)


func test_the_opacity_of_a_group_a_filter_isolates_is_applied_once() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(512, 256))
    var doc := easel.document
    var red := _member(doc, "Red", RED)
    SaLayerOps.new(doc).set_blend_mode(red, &"normal")
    var group := SaLayerOps.new(doc).group_layers([red])
    group.opacity = 0.5
    doc.set_active_layer(doc.get_node("Layer 1") as SaLayer)
    SaFilterOps.new(doc).attach(group, Bench.INVERT)
    Bench.composite(easel)
    # Cyan at a half over the grey background.
    _shows(easel, Color(0.25, 0.75, 0.75), "The group's opacity reaches the inverted composite once, not the member as well")
    easel.free()


func test_the_groups_row_marks_it_isolated_while_a_filter_holds_it() -> void:
    var easel: SaEasel = Bench.easel(Vector2i(512, 256))
    var doc := easel.document
    var group := SaLayerOps.new(doc).group_layers([_member(doc, "Red", RED)])
    var row := SaLayerRowView.new(str(group.name), 0, true, 0, group)
    row.refresh(doc)
    assert_false(row.isolated_mark.visible, "A pass-through group's row carries no mark")
    assert_false(row.report()["isolated_mark"], "and the dump says so")

    var record := SaFilterOps.new(doc).attach(group, Bench.INVERT)
    row.refresh(doc)
    assert_true(row.isolated_mark.visible, "An attached filter shows the group as isolated")
    assert_true(row.isolated_mark.tooltip_text.contains("filter"), "and the mark says what holds it")

    SaFilterOps.new(doc).detach(group, record)
    SaLayerOps.new(doc).set_isolated(group, true)
    row.refresh(doc)
    assert_true(row.isolated_mark.visible, "A group the painter isolated is marked too")
    assert_false(row.isolated_mark.tooltip_text.contains("filter"), "in the painter's own words")

    var plain := SaLayerRowView.new("Layer", 0, false, 1, doc.get_node("Layer 1") as SaLayer)
    assert_null(plain.isolated_mark, "A layer's row has no such mark")
    plain.free()
    row.free()
    easel.free()
