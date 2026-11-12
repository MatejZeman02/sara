## The thirteen ledger returns, re-driven from a painter's own words.
##
## The `pending_` method is the one defect the sweep filed. A `pending_` method
## is not run: the framework calls what begins with `test_`, so the fixer renames
## it and the suite starts asserting the thing that was wrong. That is the
## convention.
##
## The `test_` method is the arithmetic behind that defect, and it passes today
## because it asserts the collision rather than the absence of one.
extends "res://tests/test_framework.gd"

const SkeletonBlendModes = preload("res://core/loader/skeleton_blend_modes.gd")


## The three pinned Normals lead with their space, so none of them can be spelt
## the way plain Normal is drawn on a document in that space.
##
## `normal` is drawn with the document's own space in brackets, which its own
## table comment says is the point: "plain Normal's label carries the document's
## space in brackets: it says which of the three it currently equals". So on an
## Oklab document it reads `Normal (Oklab)`, and `normal_oklab` used to read
## `Normal (Oklab)` too, in the same section of the same menu. It reads
## `Oklab Normal` now.
##
## The suite asserts that no two entries collide.
func test_the_pinned_normals_lead_with_their_space() -> void:
    var labelled: Dictionary = {}
    for row: Array in SkeletonBlendModes.BLEND_MODES:
        labelled[String(row[0])] = String(row[2])
    assert_eq(labelled.get("normal", ""), "Normal", "Plain Normal's own label carries no space")
    for pair: Array in [["normal_srgb", "sRGB Normal"], ["normal_linear", "Linear Normal"], ["normal_oklab", "Oklab Normal"]]:
        assert_eq(labelled.get(String(pair[0]), ""), String(pair[1]), "%s leads with its space" % pair[0])


## No two rows of the blend menu carry the same label, on any document Sara
## can make.
##
## On a document in Oklab: the Normal section read `Normal (Oklab)`,
## `Normal (sRGB)`, `Normal (linear)`, `Normal (Oklab)`. The first is `normal`,
## drawn with the document's space in brackets so a painter can see which of the
## three it equals, and the fourth was `normal_oklab`, which always equals it.
## They do different things the day the document's space changes and they were
## indistinguishable, which is the worst of both.
##
## **The fix is on the three named modes rather than on the bracket**, because
## the bracket answers a question about this document and nothing else does, and
## because plain Normal is what a fresh profile shows and `BlendModeButton`'s own
## `MIN_WIDTH` is sized for it. Leading with the space is the shorter label as
## well as the unambiguous one.
##
## This walks every space rather than the Oklab that was photographed, because
## the collision happened on all three and a fix for one is not a fix.
func test_the_blend_menu_never_lists_two_rows_with_the_same_label() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var spaces: Array = [SaColorSpace.srgb(), SaColorSpace.linear_srgb(), SaColorSpace.oklab()]
    for space: SaColorSpace in spaces:
        var seen: Dictionary = {}
        for id: StringName in registries.blend_modes.list_ids():
            var label := registries.blend_modes.get_descriptor(id).label_for(space)
            assert_false(
                seen.has(label),
                "%s and %s both read '%s' on a %s document" % [seen.get(label, ""), id, label, space.blend_space_name()]
            )
            seen[label] = String(id)
        assert_eq(
            seen.size(),
            registries.blend_modes.list_ids().size(),
            "and every registered mode has a label of its own on a %s document" % space.blend_space_name()
        )
