## A proof mode the registry does not hold reads back as one it does.
##
## `SaSettings.canvas_proof_mode` and `minimap_proof_mode` name a view transform
## and were plain strings with nothing checking them, the comment beside them
## saying they were "validated where used" and nothing validating anywhere. A
## profile naming a mode the registry has lost, which is what a painter has the
## moment a module they picked a mode from stops loading, left
## `MinimapDocker._proof_descriptor` answering null, `_sync_material` leaving the
## canvas material alone, and Ctrl+Shift+Y toggling a proof with nothing
## changing on screen.
##
## measured that: `1-control-on-the-docker.json` read `"proof_mode": "normal"`
## beside `"proof_option": {"items": 4, "selected": "", "shown": ""}`. The
## assembled controls are `scenarios/proof-mode-unchecked.json`, which reads
## `lightness_check` and a selected row for the same stored value.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func _registry() -> SaViewTransformRegistry:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries.view_transforms


## The case the filing is about, and the id it uses: `normal` is a blend mode's
## and not a view transform's, which is how the scenario reached the state
## without a module to unload.
func test_an_id_the_registry_never_held_falls_back() -> void:
    var registry := _registry()
    assert_eq(
        SaSettings.proofs.mode_or(registry, "normal", SaSettings.DEFAULT_MINIMAP_PROOF),
        SaSettings.DEFAULT_MINIMAP_PROOF,
        "An id nobody registered reads back as the default"
    )
    assert_eq(
        SaSettings.proofs.mode_or(registry, "a_module_that_stopped_loading", SaSettings.DEFAULT_CANVAS_PROOF),
        SaSettings.DEFAULT_CANVAS_PROOF,
        "and so does a module's id after the module has gone"
    )


## The other half, or the fix would be a setting that ignores what it is told.
func test_a_mode_the_registry_holds_is_kept() -> void:
    var registry := _registry()
    for id: String in ["lightness_check", "hdr_heatmap", "soft_proof", "encoding_off"]:
        assert_eq(SaSettings.proofs.mode_or(registry, id, SaSettings.DEFAULT_MINIMAP_PROOF), id, "%s is a mode and is kept" % id)


## A toggle is registered and is not a mode, so a bare `has` would have passed
## it and left the proof on something that cannot be one.
func test_a_toggle_is_refused_as_well_as_an_unknown_id() -> void:
    var registry := _registry()
    var rolloff := registry.get_descriptor(&"highlight_rolloff")
    assert_not_null(rolloff, "The roll-off is a registered view transform")
    assert_eq(rolloff.kind, SaViewTransformDescriptor.Kind.TOGGLE, "of kind TOGGLE")
    assert_eq(
        SaSettings.proofs.mode_or(registry, "highlight_rolloff", SaSettings.DEFAULT_MINIMAP_PROOF),
        SaSettings.DEFAULT_MINIMAP_PROOF,
        "so a proof set to it reads back as the default"
    )


## Before the registries exist there is nothing to check against, and a guess
## then would overwrite what the file says with a default the painter never
## chose. The settings are an autoload and the modules arrive after them.
func test_nothing_is_decided_without_a_registry() -> void:
    assert_eq(
        SaSettings.proofs.mode_or(null, "a_module_that_has_not_loaded_yet", SaSettings.DEFAULT_MINIMAP_PROOF),
        "a_module_that_has_not_loaded_yet",
        "The stored value comes back untouched"
    )


const STALE := "a_module_that_stopped_loading"


func _built_registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The two settings shared one memo, so the second read the first's fallback.
## One unregistered id in both keys, and the canvas has to answer
## `soft_proof` while the minimap answers `lightness_check`, in either order.
##
## Through `resolved_in` rather than through `mode_or`, which is the
## gap the filing named: `mode_or` is the decision and has no memo in it,
## and the memo is where the defect was. What the property adds on top is
## `_view_transforms()` alone, and a headless run cannot be given a
## `current_scene` to walk, because `set_current_scene` demands a direct child
## of the root and the root is busy setting up children for the whole of a run.
## `scenarios/proof-memo-shared-key.json` is the property, on the app.
func test_the_two_proof_settings_do_not_share_one_memo() -> void:
    var registry := _built_registries().view_transforms

    # The canvas asks first, which is the order `display_page.gd` reads them in.
    var canvas_first := SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    var minimap_second := SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_MINIMAP_PROOF)
    # And the other way round, from an empty memo. A registry change is what
    # clears it and it is the door the app itself uses.
    registry.changed.emit()
    var minimap_first := SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_MINIMAP_PROOF)
    var canvas_second := SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    registry.changed.emit()

    assert_eq(canvas_first, SaSettings.DEFAULT_CANVAS_PROOF, "The canvas falls back to its own default")
    assert_eq(minimap_second, SaSettings.DEFAULT_MINIMAP_PROOF, "and the minimap to its own, having asked second")
    assert_eq(minimap_first, SaSettings.DEFAULT_MINIMAP_PROOF, "The minimap falls back to its own default")
    assert_eq(canvas_second, SaSettings.DEFAULT_CANVAS_PROOF, "and the canvas to its own, having asked second")


## It is still a memo: a second read of the same pair answers without a registry
## to walk, which is what the every-frame reader in `MinimapDocker` is paying
## for. A miss with no registry answers the stored id untouched, so the two
## cases are distinguishable.
func test_the_answer_is_still_remembered() -> void:
    var registry := _built_registries().view_transforms
    registry.changed.emit()

    var with_registry := SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    var from_the_memo := SaSettings.proofs.resolved_in(null, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    var never_asked := SaSettings.proofs.resolved_in(null, "an_id_nothing_has_resolved", SaSettings.DEFAULT_CANVAS_PROOF)
    registry.changed.emit()

    assert_eq(with_registry, SaSettings.DEFAULT_CANVAS_PROOF, "The walk answers the fallback")
    assert_eq(from_the_memo, SaSettings.DEFAULT_CANVAS_PROOF, "and the memo answers it again with no registry")
    assert_eq(never_asked, "an_id_nothing_has_resolved", "while a pair nobody has resolved comes back untouched")


## A module registering its mode late takes the setting off the fallback, which
## is what the memo is cleared for, and it has to clear every fallback rather
## than the one that happened to be asked.
func test_a_registry_change_clears_both_fallbacks() -> void:
    var registry := _built_registries().view_transforms
    SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    SaSettings.proofs.resolved_in(registry, STALE, SaSettings.DEFAULT_MINIMAP_PROOF)

    registry.changed.emit()

    var canvas := SaSettings.proofs.resolved_in(null, STALE, SaSettings.DEFAULT_CANVAS_PROOF)
    assert_eq(canvas, STALE, "The canvas answer is forgotten")
    var minimap := SaSettings.proofs.resolved_in(null, STALE, SaSettings.DEFAULT_MINIMAP_PROOF)
    assert_eq(minimap, STALE, "and so is the minimap's")


## What the file keeps is the id that was written, whatever a read answers.
##
## The other half of "what is stored is whatever was written", and the half that
## was not true before the fix. The two setters wrote `config.set_value("ui", key,
## canvas_proof_mode)`, and a read of a property inside its own setter goes
## through that property's getter in GDScript, so what reached the file was the
## resolving answer rather than the stored id. A painter whose module was not
## loaded had their choice replaced by the default the moment anything saved,
## and the next launch of the module found nothing to come back to.
##
## `SaSettingsValues` stores the id and nothing else, and `SaSettingsFile`
## writes that field, so the round trip cannot happen: the resolving read lives
## on `SaSettings` and the file never goes through it. Measured on the running
## app in `scenarios/the-settings-aged.json`, whose version-1 profile names
## `raw` for both keys and comes out of the migration holding `encoding_off`
## where it once came out holding two defaults.
func test_the_file_keeps_the_id_that_was_written() -> void:
    var values := SaSettingsValues.new()
    values.canvas_proof_mode = "a_module_that_stopped_loading"
    values.minimap_proof_mode = "a_module_that_stopped_loading"
    assert_eq(values.canvas_proof_mode, STALE, "The values object holds the id it was given")
    assert_eq(values.minimap_proof_mode, STALE, "for both keys")
    assert_eq(SaSettingsKeys.place_of(&"canvas_proof_mode"), ["ui", "canvas_proof_mode"], "and that is the field the file writes")
    values.free()
