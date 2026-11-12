## A module ships its own blend kernel, and the door holds.
##
## `SaBlendModeDescriptor.shader_name` names the shader a mode's kernel lives
## in, and a module's mode names the module's own. Hard Mix walked that door
## first, as a module, and became one of the skeleton's modes once it had, so a
## test module keeps the door walked: `tests/fixtures/blend-kernel/modules/blend-kernel-fixture/`
## registers Hard Mix's old kernel under a name of its own. This suite loads
## that folder rather than a copy of it, so what it asserts is the path a
## third-party module walks.
##
## Hard Mix is chosen because the picture answers the question. Each channel
## lands on 0 or 1, so a composite that ran the module's kernel is black and
## white and one that fell back to Normal is the grey it was painted.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const MODULE_DIR := "res://tests/fixtures/blend-kernel/modules/blend-kernel-fixture"
const FixtureModule = preload("res://tests/fixtures/blend-kernel/modules/blend-kernel-fixture/module.gd")
const MODULE_ID: StringName = &"blend-kernel-fixture"
const MODE_ID: StringName = &"kept_hard_mix"

## Two chunks wide, one tall, so the backdrop can carry two values under one
## uniform source and the same dispatch decides both.
const CANVAS := Vector2i(512, 256)

## Under a source of 0.5, the left half sums to 0.7 and the right to 1.1, which
## is one value either side of Hard Mix's threshold.
const BACKDROP_LOW := 0.2
const BACKDROP_HIGH := 0.6
const SOURCE := 0.5

var _registries: SaRegistries = null
var _module: SaModule = null
var _scoped: SaContext = null
var _easel: SaEasel = null

## The refusal is provoked on purpose, so the transcript shows the assertion
## and not the alarm it was checking for.
var _was_announcing: bool = true
var _problems_before: int = 0


func before_each() -> void:
    _was_announcing = SaProblems.announce
    SaProblems.announce = false
    _problems_before = SaProblems.pending.size()
    _registries = Fixtures.make_registries()
    _module = FixtureModule.new()
    _scoped = _registries.context.for_module(_module.get_id())
    _module.context = _scoped
    _module.register(_scoped)


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    if _module != null and _module.context != null:
        _module.unregister(_scoped)
        _scoped.remove_all_registrations()
        _module.context = null
    _module = null
    _scoped = null
    _registries = null
    SaProblems.pending = SaProblems.pending.slice(0, _problems_before)
    SaProblems.announce = _was_announcing


func test_the_mode_resolves_to_a_kernel_in_the_modules_own_shader() -> void:
    var registry := _registries.blend_modes
    assert_true(registry.has(MODE_ID), "registering the module put the mode in the registry")

    var descriptor := registry.get_descriptor(MODE_ID)
    assert_eq(descriptor.shader_name, FixtureModule.SHADER, "and the mode names the module's shader, not composite")
    assert_true(descriptor.shader_name.begins_with("blend-kernel-fixture/"), "which is qualified by the folder that owns it")
    assert_eq(descriptor.owner_module, MODULE_ID, "attributed to the module that registered it")

    # The index is a position in the module's own file. Asking `composite` for
    # the same name has to answer -1, or the mode would be resolving against
    # Sara's shader and the door would prove nothing.
    var index := registry.resolve_kernel(MODE_ID)
    assert_true(index >= 0, "the kernel resolves to an index")
    assert_eq(index, GlobalShaderCompiler.get_kernel_index(FixtureModule.SHADER, FixtureModule.KERNEL), "in that shader")
    assert_eq(GlobalShaderCompiler.get_kernel_index("composite", FixtureModule.KERNEL), -1, "and nowhere in composite")
    assert_true(_registries.validate().is_empty(), "so the registry's own validation passes")


## The check, run over a registry the module is in: a mode
## naming a kernel that is not there is refused at the door rather than kept as an
## entry that composites as Normal.
##
## The refusal lives in `register`, not in `validate()`, which reports what it is
## given. `register` which is the door the descriptor walks through.
func test_a_mode_naming_a_kernel_the_modules_shader_lacks_is_refused() -> void:
    var absent := SaBlendModeDescriptor.create(&"kept_hard_mix_typo", "kepthardmix", FixtureModule.SHADER)

    assert_false(_registries.blend_modes.register(absent, MODULE_ID), "the registry refuses the descriptor")
    assert_false(_registries.blend_modes.has(&"kept_hard_mix_typo"), "so it never reaches a dropdown")
    assert_true(_registries.validate().is_empty(), "and validation has nothing left to report")

    assert_eq(SaProblems.pending.size(), _problems_before + 1, "the refusal is kept for the problems window")
    if SaProblems.pending.size() == _problems_before + 1:
        var line := SaProblems.pending[_problems_before]
        assert_true(line.begins_with("SaBlendModeRegistry: "), "under the door that refused it")
        assert_true(line.contains("kept_hard_mix_typo"), "naming the mode")
        assert_true(line.contains("kepthardmix"), "the kernel it asked for")
        assert_true(line.contains("blend-kernel-fixture/kept_hard_mix"), "and the shader it looked in")


func test_unloading_the_module_takes_the_mode_out_of_the_registry() -> void:
    ModuleLoader.loaded_modules[MODULE_ID] = _module
    ModuleLoader.unload_module(MODULE_ID)
    _module = null
    _scoped = null

    assert_false(_registries.blend_modes.has(MODE_ID), "the mode goes with the module")
    assert_false(ModuleLoader.is_loaded(MODULE_ID), "which is no longer loaded")
    assert_true(_registries.blend_modes.has(&"multiply"), "and the skeleton's own modes stay")


func test_the_dropdown_shows_the_mode_under_a_section() -> void:
    var button := BlendModeButton.new()
    button.registry = _registries.blend_modes
    button.include_hidden_in_layers = false
    button.refresh()

    assert_true(button.mode_ids().has(MODE_ID), "the list a dropdown builds holds the module's mode")
    assert_true(button.section_titles().has("Contrast"), "the section it declared is drawn")
    var ids := button.section_ids("Contrast")
    assert_true(ids.has(MODE_ID), "with the mode in it")
    # Beside the built-ins rather than instead of them, and after the
    # skeleton's Hard Mix, which is what its sort order asks for.
    assert_true(ids.has(&"hard_mix"), "beside the built-in it sorts after")
    assert_true(ids.find(MODE_ID) > ids.find(&"hard_mix"), "and after it")

    assert_true(button.select_mode(MODE_ID), "a dropdown can select it")
    assert_eq(button.text, "Kept Hard Mix", "and then reads the module's own label")
    button.free()


func test_the_composite_runs_the_modules_kernel() -> void:
    var grey := _composite_with(SaLayer.BLEND_MODE.NORMAL)
    assert_almost_eq(grey[0], SOURCE, 0.002, "under Normal the source covers the low half")
    assert_almost_eq(grey[1], SOURCE, 0.002, "and the high one, which is the before picture")

    var mixed := _composite_with(MODE_ID)
    # 0.5 + 0.2 is under the window's top and 0.5 + 0.6 is over it, so the one
    # dispatch answers 0 on the left and 1 on the right. Neither is a value any
    # built-in produces from this pair, which is what makes the picture proof.
    assert_almost_eq(mixed[0], 0.0, 0.002, "Hard Mix drops the half that does not reach the top")
    assert_almost_eq(mixed[1], 1.0, 0.002, "and lifts the half that does")


## The composited red channel at the middle of each half, with the upper layer
## set to *mode_id*. A fresh easel each time, so the two runs share nothing but
## the registry, and the compositor is given that registry because without one
## every mode resolves to Normal, which is the fallback this suite must not be
## fooled by.
func _composite_with(mode_id: StringName) -> Array[float]:
    if _easel != null:
        _easel.free()
    _easel = SaEasel.create_default(CANVAS)
    _easel.compositor.set_registry(_registries.blend_modes)

    var document := _easel.document
    var backdrop := document.get_node("Background") as SaLayer
    backdrop.get_or_create_chunk(Vector2i(0, 0)).clear(Color(BACKDROP_LOW, BACKDROP_LOW, BACKDROP_LOW, 1.0))
    backdrop.get_or_create_chunk(Vector2i(1, 0)).clear(Color(BACKDROP_HIGH, BACKDROP_HIGH, BACKDROP_HIGH, 1.0))

    var source := document.get_node("Layer 1") as SaLayer
    source.allocate_grid(CANVAS)
    source.fill(Color(SOURCE, SOURCE, SOURCE, 1.0))
    SaLayerOps.new(document).set_blend_mode(source, mode_id)

    document.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var read: Array[float] = [_texel(_easel.output, 128, 128).r, _texel(_easel.output, 384, 128).r]
    return read


## One texel of a texture, as stored.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))
