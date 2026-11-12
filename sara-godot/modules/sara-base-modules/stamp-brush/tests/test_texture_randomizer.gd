## The paper's per-stroke randomiser: the three rows, the jump drawn once when
## the pen goes down, and the Krita params that now carry.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The arithmetic here, the paint in the scenario.**
## `scenarios/the-paper-does-not-repeat-where-the-eye-sees-it.json` paints
## four strokes over one paper with the randomiser off and four with it on, and
## then paints one of them a second time on a layer of its own. Its dumps
## are what says the grain moved: the second stroke reads the first's texels
## exactly while the switch is off, and differs everywhere once it is on. What
## paint cannot say is that the jump was drawn once per stroke rather than once
## per dab, which is the difference between paper and noise, so that is
## asserted here against a pinned seed.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Pinned, so every reading below is a number a reader can check rather than a
## range. `SaStrokeInfo.begin` takes the seed straight when it is not nought.
const SEED: int = 987654321


func _settings() -> Resource:
    var settings: Resource = SettingsScript.new()
    settings.pattern_name = "Paper Grain"
    settings.texture_option.enabled = true
    return settings


## A stroke that has pressed, at *seed_value*, with nothing painted yet.
func _stroke(seed_value: int = SEED) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, seed_value)
    return info


func _target(at: Vector2i) -> SaPaintContext.Target:
    var target := SaPaintContext.Target.new()
    target.grid_pos = at
    return target


# --- The three rows ----------------------------------------------------------------


func test_the_page_declares_the_three_rows_the_note_asked_for() -> void:
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in SaTexturePage.rows():
        keys.append(spec.key)

    assert_true(keys.has(&"texture_random_per_stroke"), "the randomize per stroke checkbox")
    assert_true(keys.has(&"texture_random_offset_x"), "how much in x")
    assert_true(keys.has(&"texture_random_offset_y"), "and how much in y")

    for spec: SaOptionSpec in SaTexturePage.rows():
        if spec.key == &"texture_random_per_stroke":
            assert_eq(spec.kind, SaOptionSpec.Kind.BOOL, "The switch is a checkbox")
            assert_eq(spec.label, "Randomize per stroke", "labelled the way the note asks for it")
        elif spec.key in [&"texture_random_offset_x", &"texture_random_offset_y"]:
            assert_eq(spec.kind, SaOptionSpec.Kind.INT, "%s is a whole number of pixels" % spec.key)
            assert_eq(spec.max_value, float(SaTexturePage.MAX_OFFSET), "with the fixed offset's own ceiling")
        if spec.page == SaTexturePage.PAGE:
            assert_false(spec.bar, "%s stays off the tool options bar" % spec.key)


func test_the_settings_carry_the_three_fields_switched_off() -> void:
    var settings := _settings()

    assert_false(settings.texture_random_per_stroke, "A fresh brush does not move its paper")
    assert_eq(settings.texture_random_offset_x, 0, "and names no amount in x")
    assert_eq(settings.texture_random_offset_y, 0, "nor in y")
    assert_eq(SaDabPattern.random_amount_of(settings), Vector2.ZERO, "so there is no jump to draw")


# --- The jump ----------------------------------------------------------------------


func test_a_brush_with_the_switch_off_reads_the_grid_the_painter_set() -> void:
    var settings := _settings()
    settings.texture_offset_x = 3
    settings.texture_offset_y = 5
    # Named on purpose while the switch is off: an amount is not a jump.
    settings.texture_random_offset_x = 200
    settings.texture_random_offset_y = 200

    assert_eq(SaDabPattern.random_phase(settings, _stroke()), Vector2.ZERO, "The switch is what draws the jump")
    assert_eq(
        SaDabPattern.offset_for(_target(Vector2i(2, 1)), 256, settings, _stroke()),
        Vector2(515.0, 261.0),
        "so the grid is the chunk's own origin plus the painter's offset, exactly as before"
    )


func test_the_jump_is_drawn_once_per_stroke_and_not_once_per_dab() -> void:
    var settings := _settings()
    settings.texture_random_per_stroke = true
    settings.texture_random_offset_x = 128
    settings.texture_random_offset_y = 64
    var info := _stroke()

    var first := SaDabPattern.random_phase(settings, info)
    for dab in range(50):
        info.next_dab()
        assert_eq(SaDabPattern.random_phase(settings, info), first, "dab %d reads the phase the press drew" % dab)

    # And every chunk of that stroke reads the one grid, which is the pattern's
    # rule and the thing a per-dab draw would break first.
    var near := SaDabPattern.offset_for(_target(Vector2i(0, 0)), 256, settings, info)
    var far := SaDabPattern.offset_for(_target(Vector2i(3, 2)), 256, settings, info)
    assert_eq(far - near, Vector2(768.0, 512.0), "two chunks of one stroke differ by their origins and nothing else")


func test_the_next_press_draws_a_different_jump() -> void:
    var settings := _settings()
    settings.texture_random_per_stroke = true
    settings.texture_random_offset_x = 256
    settings.texture_random_offset_y = 256

    var phases: Array[Vector2] = []
    for stroke in range(8):
        phases.append(SaDabPattern.random_phase(settings, _stroke(SEED + stroke)))

    for i in range(phases.size()):
        for j in range(i + 1, phases.size()):
            assert_true(phases[i] != phases[j], "stroke %d and stroke %d landed the paper differently" % [i, j])


func test_the_jump_is_repeatable_from_a_pinned_seed() -> void:
    var settings := _settings()
    settings.texture_random_per_stroke = true
    settings.texture_random_offset_x = 100
    settings.texture_random_offset_y = 40

    var once := SaDabPattern.random_phase(settings, _stroke())
    var again := SaDabPattern.random_phase(settings, _stroke())

    assert_eq(once, again, "The same seed is the same paper, which is what makes a shot worth comparing")
    assert_true(absf(once.x) <= 100.0, "and the jump stays inside the amount in x, at %f" % once.x)
    assert_true(absf(once.y) <= 40.0, "and inside it in y, at %f" % once.y)


func test_the_two_axes_are_drawn_apart() -> void:
    var only_x := _settings()
    only_x.texture_random_per_stroke = true
    only_x.texture_random_offset_x = 200

    var phase := SaDabPattern.random_phase(only_x, _stroke())
    assert_true(absf(phase.x) > 0.0, "An amount in x alone moves the paper along x")
    assert_almost_eq(phase.y, 0.0, 1e-6, "and leaves y where the painter put it, because paper is not isotropic")


func test_the_jump_is_a_radius_around_the_painter_s_own_offset() -> void:
    var settings := _settings()
    settings.texture_offset_x = 400
    settings.texture_offset_y = 400
    settings.texture_random_per_stroke = true
    settings.texture_random_offset_x = 100
    settings.texture_random_offset_y = 100

    var signs := {}
    for stroke in range(40):
        var phase := SaDabPattern.random_phase(settings, _stroke(SEED + stroke))
        signs[signf(phase.x)] = true

    assert_true(signs.has(-1.0) and signs.has(1.0), "The paper jumps both ways from where the painter set it")


func test_the_dump_says_whether_the_paper_moves_and_by_how_much() -> void:
    var settings := _settings()
    settings.texture_random_per_stroke = true
    settings.texture_random_offset_x = 90
    settings.texture_random_offset_y = 12
    var report := SaDabPattern.new(SaPatternStore.new([SaPatternStore.SHIPPED_DIR])).report(settings)

    assert_true(bool(report["random_per_stroke"]), "A reviewer reads the switch off the dump")
    assert_eq(report["random_amount"], [90.0, 12.0], "and the two amounts beside it")


# --- The import --------------------------------------------------------------------


func _preset(params: Dictionary) -> Dictionary:
    var options := {}
    for name: String in params:
        options[name] = {"value": String(params[name])}
    return {"options": options}


func test_a_preset_with_a_random_offset_carries_the_rows_and_no_tag() -> void:
    var settings := _settings()
    var result := (
        SaKppImport
        . apply(
            _preset(
                {
                    "Texture/Pattern/Enabled": "true",
                    "Texture/Pattern/isRandomOffsetX": "true",
                    "Texture/Pattern/isRandomOffsetY": "true",
                    "Texture/Pattern/MaximumOffsetX": "48",
                    "Texture/Pattern/MaximumOffsetY": "16",
                }
            ),
            settings
        )
    )

    assert_true(settings.texture_random_per_stroke, "The switch came across")
    assert_eq(settings.texture_random_offset_x, 48, "with Krita's own amount in x")
    assert_eq(settings.texture_random_offset_y, 16, "and in y")
    assert_false(
        (result["not_carried"] as Array).has("random texture offset"),
        "and the phrase has left the not-carried list, which is what the unit is for"
    )
    assert_eq(result["unread"], [] as Array[String], "with all four params read")


func test_one_axis_switched_off_carries_as_an_amount_of_nothing() -> void:
    var settings := _settings()
    (
        SaKppImport
        . apply(
            _preset(
                {
                    "Texture/Pattern/Enabled": "true",
                    "Texture/Pattern/isRandomOffsetX": "true",
                    "Texture/Pattern/isRandomOffsetY": "false",
                    "Texture/Pattern/MaximumOffsetX": "60",
                    "Texture/Pattern/MaximumOffsetY": "90",
                }
            ),
            settings
        )
    )

    assert_true(settings.texture_random_per_stroke, "One axis on is a randomiser on")
    assert_eq(settings.texture_random_offset_x, 60, "the switched-on axis keeps its amount")
    assert_eq(settings.texture_random_offset_y, 0, "and the switched-off one arrives at nought, which is the same paper")


func test_a_preset_with_both_axes_off_leaves_the_switch_alone() -> void:
    var settings := _settings()
    var result := (
        SaKppImport
        . apply(
            _preset(
                {
                    "Texture/Pattern/Enabled": "true",
                    "Texture/Pattern/isRandomOffsetX": "false",
                    "Texture/Pattern/isRandomOffsetY": "false",
                }
            ),
            settings
        )
    )

    assert_false(settings.texture_random_per_stroke, "A Krita brush that does not move its paper does not move Sara's")
    assert_false((result["not_carried"] as Array).has("random texture offset"), "and nothing failed to carry")


func test_an_amount_past_the_page_s_ceiling_is_clamped_to_it() -> void:
    var settings := _settings()
    (
        SaKppImport
        . apply(
            _preset(
                {
                    "Texture/Pattern/Enabled": "true",
                    "Texture/Pattern/isRandomOffsetX": "true",
                    "Texture/Pattern/MaximumOffsetX": "99999",
                }
            ),
            settings
        )
    )

    assert_eq(
        settings.texture_random_offset_x,
        SaTexturePage.MAX_OFFSET,
        "A jump the spinbox could not have reached by hand is one nobody can read back off the canvas"
    )
