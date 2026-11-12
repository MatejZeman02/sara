## The Krita import of the masking brush's composite op: the
## four ops the bundled presets name besides multiply carry onto
## `SaMaskingBrush.op` and wear no tag, and any other stays multiply and is
## named by its own id.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own suite rather than more of `test_kpp_import.gd`, which holds the
## whole mapping table and is at the linter's count of public methods. What the
## op then paints is `test_masking_ops.gd`, which needs a GPU where this does
## not.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")


## A preset of nothing but *options*, the shape `SaKppReader` hands the import.
func _preset_with(options: Dictionary) -> Dictionary:
    var out := {
        "name": "made",
        "source": "made.kpp",
        "engine": "paintbrush",
        "options": {},
        "resources": {},
        "tags": PackedStringArray(),
        "licence": "",
        "error": "",
        "tip": {"kind": SaKppReader.TIP_NONE}
    }
    for name: String in options:
        out["options"][name] = {"type": "string", "value": String(options[name])}
    return out


## A mask switched on with a generated tip of its own, which carries whole, and
## *op* as its composite, left out when empty.
func _masking(op: String) -> Dictionary:
    var options := {
        "MaskingBrush/Enabled": "true",
        "MaskingBrush/UseMasterSize": "true",
        "MaskingBrush/MasterSizeCoeff": "0.75",
        "MaskingBrush/Preset/brush_definition":
        (
            '<Brush type="auto_brush" spacing="0.3">'
            + ' <MaskGenerator ratio="0.5" type="rect" id="default" diameter="24" hfade="1" vfade="1"/> </Brush>'
        ),
    }
    if not op.is_empty():
        options["MaskingBrush/MaskingCompositeOp"] = op
    return _preset_with(options)


func test_the_four_ops_the_bundle_uses_carry_with_no_tag() -> void:
    var expected := {
        "subtract": SaMaskingBrush.Op.SUBTRACT,
        "darken": SaMaskingBrush.Op.DARKEN,
        "burn": SaMaskingBrush.Op.BURN,
        "overlay": SaMaskingBrush.Op.OVERLAY,
        "multiply": SaMaskingBrush.Op.MULTIPLY,
    }
    for id: String in expected:
        var settings := SettingsScript.new()
        var applied := SaKppImport.apply(_masking(id), settings)
        assert_eq(applied["not_carried"], [], "%s carries with no tag" % id)
        assert_eq(settings.masking.op, expected[id], "%s lands on the op field" % id)
        assert_eq(settings.masking.op_id(), id, "and names itself back by Krita's id")


func test_an_absent_op_is_krita_s_default_multiply() -> void:
    var settings := SettingsScript.new()
    assert_eq(SaKppImport.apply(_masking(""), settings)["not_carried"], [], "no op is no tag")
    assert_eq(settings.masking.op, SaMaskingBrush.Op.MULTIPLY, "and multiply")


func test_an_op_sara_has_no_arithmetic_for_stays_multiply_and_is_named() -> void:
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(_masking("linear_dodge"), settings)
    assert_eq(applied["not_carried"], ["masking composite op linear_dodge"], "the tag names the op")
    assert_eq(settings.masking.op, SaMaskingBrush.Op.MULTIPLY, "and the mask multiplies")


## The op is read before the tip, so a preset whose mask tip is lost keeps its
## op, which is what the two such presets in Krita's own bundles do.
func test_a_mask_whose_tip_is_lost_still_keeps_its_op() -> void:
    var options := _masking("subtract")
    var definition := '<Brush type="png_brush" filename="never-embedded.png" scale="1" spacing="0.3"/>'
    options["options"]["MaskingBrush/Preset/brush_definition"]["value"] = definition
    var settings := SettingsScript.new()
    var applied := SaKppImport.apply(options, settings)
    assert_eq(applied["not_carried"], ["masking tip"], "the tip is what is lost")
    assert_eq(settings.masking.op, SaMaskingBrush.Op.SUBTRACT, "and the op is kept")


func test_a_saved_block_round_trips_its_op() -> void:
    var block := SaMaskingBrush.new()
    assert_eq(block.op, SaMaskingBrush.Op.MULTIPLY, "a new block multiplies, as every block before the field did")
    block.op = SaMaskingBrush.Op.BURN
    var copy: SaMaskingBrush = block.duplicate(true)
    assert_eq(copy.op, SaMaskingBrush.Op.BURN, "the field is exported and travels with the preset")
    assert_eq(SaMaskingBrush.op_of("overlay"), SaMaskingBrush.Op.OVERLAY, "an id is read")
    assert_eq(SaMaskingBrush.op_of("dissolve"), -1, "and an unknown one answers -1")
