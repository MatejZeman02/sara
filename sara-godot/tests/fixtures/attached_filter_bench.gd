## What the three attached-filter suites share: an easel whose compositor can
## answer the fixture invert's key, and a reader of one texel of a texture.
##
## The invert is `tests/fixtures/modules/point-fixture`, registered under
## its module's id so the context the chain builds finds the kernel the shader
## index filed under that folder.
extends RefCounted

const Fixtures = preload("res://tests/fixtures.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const OWNER: StringName = &"point-fixture"
## The key the fixture answers to, its module's id and its own.
const INVERT: StringName = &"point-fixture.point_fixture_invert"
## The base module's Threshold, a pixel function, not a written class.
const THRESHOLD_PATH: String = "res://modules/sara-base-modules/base/usual/threshold.gmacs"


## Threshold as the base module registers it, under the same key and section.
static func threshold() -> SaPixelFilter:
    return SaPixelFilter.new(THRESHOLD_PATH, "Threshold", 0, &"tone")


## An easel of *size* whose compositor knows the blend modes and the invert.
static func easel(size: Vector2i) -> SaEasel:
    var made := SaEasel.create_default(size)
    made.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(InvertFilter.new(), OWNER)
    made.compositor.filter_chain.registry = filters
    return made


static func composite(made: SaEasel) -> void:
    made.document.update_caches()
    made.request_full_composite()
    made.process_pending_composite()


static func texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)
