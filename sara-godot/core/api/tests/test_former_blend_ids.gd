## A renamed blend mode keeps loading under its former id.
##
## A layer's mode is written into a `.sad` by id, and nothing answered for an id
## no registry held: `resolve_kernel` gives -1 and the compositor falls back to
## Normal, so the rename of `pga_hard_mix` to `hard_mix` would have changed
## what every painting made with it looks like, silently. A descriptor's
## `former_ids` is what the registry files as an alias, and `rebind` is what
## moves a loaded layer onto the id its mode is registered under now.
##
## The round trip at the end is the one that matters: the same writer and reader
## the app uses, over a document whose layer is set to the old id, read back
## twice, once rebound and once not, so the suite says where the fix lives.
##
## Hard Mix was a module's mode when this suite was written and is the
## skeleton's now, a row of `core/loader/skeleton_blend_modes.gd` whose
## `FORMER_IDS` carries the alias, so the registry the fixtures build holds it
## with no module loaded.
extends "res://tests/test_framework.gd"

## The round trip builds a real document, which allocates chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const MODE_ID: StringName = &"hard_mix"

## What a document painted before the rename carries in its `blend_mode` field.
const FORMER_ID: StringName = &"pga_hard_mix"

static var scratch_round_trip_path: String = SaDataRoot.path("test_former_blend_ids.sad")

var _registries: SaRegistries = null

## The clash is provoked on purpose, so the transcript shows the assertion and
## not the alarm it was checking for.
var _was_announcing: bool = true
var _problems_before: int = 0


func before_each() -> void:
    _was_announcing = SaProblems.announce
    SaProblems.announce = false
    _problems_before = SaProblems.pending.size()
    _registries = Fixtures.make_registries()


func after_each() -> void:
    _registries = null
    SaProblems.pending = SaProblems.pending.slice(0, _problems_before)
    SaProblems.announce = _was_announcing
    DirAccess.remove_absolute(scratch_round_trip_path)


## A descriptor that owns a kernel the compiler really holds, so registering it
## exercises the door rather than the refusal beside it.
func _fixture_mode(mode_id: StringName, former: Array[StringName]) -> SaBlendModeDescriptor:
    var descriptor := SaBlendModeDescriptor.create(mode_id, "multiply")
    descriptor.former_ids = former
    return descriptor


func test_the_mode_declares_the_id_it_was_saved_under() -> void:
    var descriptor := _registries.blend_modes.get_descriptor(MODE_ID)
    assert_not_null(descriptor, "the skeleton registered Hard Mix")
    assert_true(descriptor.former_ids.has(FORMER_ID), "and names the id it was saved under before the rename")
    assert_true(SaBlendModeDescriptor.new().former_ids.is_empty(), "while a mode that was never renamed names none")


func test_canonical_answers_both_ways() -> void:
    var registry := _registries.blend_modes
    assert_eq(registry.canonical(FORMER_ID), MODE_ID, "the former id answers with the id the mode holds now")
    assert_eq(registry.canonical(MODE_ID), MODE_ID, "the current id answers with itself")
    assert_eq(registry.canonical(&"multiply"), &"multiply", "a mode that was never renamed answers with itself")
    assert_eq(registry.canonical(&"nothing_at_all"), &"nothing_at_all", "and an id nothing holds is handed back")
    # The alias is for files, not for menus: it must never draw a second row.
    assert_false(registry.has(FORMER_ID), "the alias is not a registered mode")
    assert_eq(registry.resolve_kernel(FORMER_ID), -1, "and resolves to no kernel, so the read has to rebind")


func test_a_former_id_that_is_a_registered_mode_is_refused_and_the_mode_survives() -> void:
    var registry := _registries.blend_modes
    var clashing := _fixture_mode(&"fixture_clash", [&"multiply"] as Array[StringName])

    assert_true(registry.register(clashing), "the mode itself is registered")
    assert_true(registry.has(&"fixture_clash"), "so a painter can still pick it")
    assert_eq(registry.canonical(&"multiply"), &"multiply", "and the registered mode keeps answering for its own id")

    assert_eq(SaProblems.pending.size(), _problems_before + 1, "the clash is kept for the problems window")
    if SaProblems.pending.size() == _problems_before + 1:
        var reported := SaProblems.pending[_problems_before]
        assert_true(reported.begins_with("SaBlendModeRegistry: "), "under the door that refused it")
        assert_true(reported.contains("fixture_clash"), "naming the mode that claimed the alias")
        assert_true(reported.contains("multiply"), "and the id it collided with")


func test_a_former_id_another_mode_already_claims_is_refused() -> void:
    var registry := _registries.blend_modes
    assert_true(registry.register(_fixture_mode(&"fixture_first", [&"fixture_old"] as Array[StringName])), "the first files it")
    assert_true(
        registry.register(_fixture_mode(&"fixture_second", [&"fixture_old"] as Array[StringName])), "the second registers"
    )

    assert_true(registry.has(&"fixture_second"), "and keeps its mode")
    assert_eq(registry.canonical(&"fixture_old"), &"fixture_first", "while the alias stays with the mode that filed it first")
    assert_eq(SaProblems.pending.size(), _problems_before + 1, "and the second claim is reported once")


func test_unregistering_a_mode_takes_its_aliases_with_it() -> void:
    var registry := _registries.blend_modes
    registry.unregister(MODE_ID)

    assert_false(registry.has(MODE_ID), "the mode is gone")
    assert_eq(registry.canonical(FORMER_ID), FORMER_ID, "and so is the alias, so nothing answers for a mode that is not there")


func test_unregistering_the_module_takes_its_aliases_with_it() -> void:
    var registry := _registries.blend_modes
    var renamed := _fixture_mode(&"fixture_renamed", [&"fixture_before"] as Array[StringName])
    assert_true(registry.register(renamed, &"fixture_module"), "a module's renamed mode registers")
    assert_eq(registry.canonical(&"fixture_before"), &"fixture_renamed", "with its alias")
    registry.unregister_module(&"fixture_module")

    assert_false(registry.has(&"fixture_renamed"), "the module's mode goes with the module")
    assert_eq(registry.canonical(&"fixture_before"), &"fixture_before", "and the alias with the mode")
    assert_eq(registry.canonical(FORMER_ID), MODE_ID, "while the skeleton's own modes and their aliases are untouched")


func test_canonical_list_keeps_the_order_and_drops_the_duplicate() -> void:
    var registry := _registries.blend_modes
    var favourites: Array = ["normal", String(FORMER_ID), "multiply", String(MODE_ID)]
    var current := registry.canonical_list(favourites)

    assert_eq(current, ["normal", "hard_mix", "multiply"], "the old id becomes the new one, in place, and the second copy goes")
    assert_true(current[1] is String, "and a favourite that arrived as a String goes back as one")
    assert_eq(registry.canonical_list([]), [], "an empty list stays empty")


func test_rebind_rewrites_a_layer_and_leaves_an_unknown_id_alone() -> void:
    var known := SaLayer.new()
    known.blend_mode = FORMER_ID
    var stranger := SaLayer.new()
    stranger.blend_mode = &"a_mode_from_a_module_nobody_has"

    _registries.blend_modes.rebind([known, stranger])

    assert_eq(known.blend_mode, MODE_ID, "the layer saved under the former id now names the mode that answers")
    assert_eq(stranger.blend_mode, &"a_mode_from_a_module_nobody_has", "and a mode nothing holds is kept rather than made Normal")
    known.free()
    stranger.free()


## The whole path, through the writer and the reader the app uses.
##
## Read twice from one file: once rebound, which is what `main.gd` does on
## `document_loaded`, and once as it comes off disk. The second assertion is
## what says the fix lives in the rebind and not in the reader.
func test_a_document_saved_under_the_former_id_composites_as_the_renamed_mode() -> void:
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    var painted := _first_layer(document)
    painted.blend_mode = FORMER_ID

    assert_eq(SaExport.save_sad(document, scratch_round_trip_path), OK, "the document is written")

    var bare := SaDocument.new()
    assert_eq(SaExport.load_sad(bare, scratch_round_trip_path, SaCompositor.new()), OK, "and read back")
    var bare_layer := _first_layer(bare)
    assert_eq(bare_layer.blend_mode, FORMER_ID, "the reader keeps the id the file holds")
    assert_eq(
        _registries.blend_modes.resolve_kernel(bare_layer.blend_mode),
        -1,
        "which resolves to nothing, so it would composite as Normal"
    )

    var rebound := SaDocument.new()
    assert_eq(SaExport.load_sad(rebound, scratch_round_trip_path, SaCompositor.new()), OK, "the same file opens again")
    _registries.blend_modes.rebind(rebound.get_children().filter(func(child: Node) -> bool: return child is SaLayer))
    var rebound_layer := _first_layer(rebound)
    assert_eq(rebound_layer.blend_mode, MODE_ID, "and after the rebind the layer names Hard Mix")
    assert_true(
        _registries.blend_modes.resolve_kernel(rebound_layer.blend_mode) >= 0, "which resolves to the module's own kernel"
    )

    bare.free()
    rebound.free()
    document.free()


func _first_layer(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        if child is SaLayer and child != document.stroke_layer:
            return child as SaLayer
    return null
