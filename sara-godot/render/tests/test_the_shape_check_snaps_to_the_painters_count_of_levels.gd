## The shape check's Levels half snaps to the painter's count of steps, and a
## profile that never set one keeps the five the shader held before.
##
## The first half of the rule: the
## quantizer "takes over the shape check's fixed five levels: the shape check's
## value half reads the slider's count". The scenario
## `scenarios/the-shape-check-s-levels-are-a-number-the-painter-sets.json` is
## the picture, three flat bands. This is what a picture cannot show: the read of
## a profile written before the key existed, and the path from the preference to
## the canvas material with no call in between, the one `SaSettingsApply`
## opens through `EventBus.tonemap_changed` for every Shape Check uniform.
extends "res://tests/test_framework.gd"

const AUTOLOAD := "res://core/settings/sa_settings.gd"
const SHADER_PATH := "res://shaders/canvas/tonemap.gdshader"
const UNIFORM := "shape_check_level_count"
static var scratch_path: String = SaDataRoot.path("test_q1_a_profile_before_the_count.cfg")

## A canvas builds an easel and its material a shader the renderer compiles.
const REQUIRES_GPU := true

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _kept_count: int = 5
var _kept_method: String = SaSettings.SHAPE_BLOCKS
var _kept_levels: bool = true


func before_each() -> void:
    _kept_count = SaSettings.shape_check_level_count
    _kept_method = SaSettings.shape_check_method
    _kept_levels = SaSettings.shape_check_levels
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _canvas.sync_tonemap()


func after_each() -> void:
    SaSettings.shape_check_level_count = _kept_count
    SaSettings.shape_check_method = _kept_method
    SaSettings.shape_check_levels = _kept_levels
    _canvas.free()
    _easel.free()
    var scratch := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", SaSettingsFile.BACKUP_SUFFIX]:
        DirAccess.remove_absolute(scratch + suffix)


## What the canvas material holds for the count right now.
func _uniform() -> Variant:
    return (_canvas.material as ShaderMaterial).get_shader_parameter(UNIFORM)


## A profile of this build's version that carries the Shape check rows and no
## count, which is every older profile. The rows are the masses method's, the
## method and the switch the one Levels row became.
func _profile_without_the_count() -> ConfigFile:
    var profile := ConfigFile.new()
    profile.set_value("meta", "version", SaSettingsFile.SETTINGS_VERSION)
    profile.set_value("ui", "shape_check_method", SaSettings.SHAPE_NONE)
    profile.set_value("ui", "shape_check_levels", true)
    return profile


func test_a_profile_without_the_key_shows_five_levels() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    assert_eq(_profile_without_the_count().save(scratch), OK, "the old profile is on disk")
    var settings: Node = load(AUTOLOAD).new()
    settings.settings_path = scratch
    settings.load_settings()
    var read: int = settings.shape_check_level_count
    var method: String = settings.shape_check_method
    settings.free()
    assert_eq(method, SaSettings.SHAPE_NONE, "the profile was read, its Shape check rows with it")
    assert_eq(read, 5, "and a profile with no count reads five")

    SaSettings.shape_check_level_count = read
    assert_eq(_uniform(), 5, "five is what the canvas hands the shader for it")
    var shader: Shader = load(SHADER_PATH)
    assert_eq(
        RenderingServer.shader_get_parameter_default(shader.get_rid(), UNIFORM),
        5,
        "and five is what the shader keeps when it is handed nothing, the constant it replaced"
    )
    assert_false(FileAccess.get_file_as_string(SHADER_PATH).contains("SHAPE_CHECK_LEVELS"), "which is gone")


func test_a_count_written_to_the_preference_reaches_the_canvas_uniform() -> void:
    SaSettings.shape_check_level_count = 5
    assert_eq(_uniform(), 5, "the canvas starts at five")
    for count: int in [3, 2, 11, 7]:
        SaSettings.shape_check_level_count = count
        assert_eq(_uniform(), count, "%d written to the preference is the uniform with no sync in between" % count)
        assert_eq(_canvas._shape_check_state()["level_count"], count, "and the dump's shape check block reads %d" % count)


func test_the_count_stays_between_two_and_eleven() -> void:
    SaSettings.shape_check_level_count = 1
    assert_eq(SaSettings.shape_check_level_count, SaSettings.MIN_SHAPE_LEVELS, "one step is held at two")
    assert_eq(_uniform(), 2, "and the shader is handed two, never a band that divides by nothing")
    SaSettings.shape_check_level_count = 40
    assert_eq(SaSettings.shape_check_level_count, SaSettings.MAX_SHAPE_LEVELS, "forty is held at eleven")
    assert_eq(_uniform(), 11, "and the shader is handed eleven")
