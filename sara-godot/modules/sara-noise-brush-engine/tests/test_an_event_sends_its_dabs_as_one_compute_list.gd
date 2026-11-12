## A frame's noise dabs go to the card as one compute list, however many pen
## motions the frame brought, and the strokes paint what they painted when each
## dab was a list of its own.
##
## **A frame's motions, not an event's.** A pen's motions are swept as they
## come and laid together at the frame, so the list is the frame's. The rule
## the last test reads is three motions gathered and laid at the frame as one
## list, which is what an event at full pressure was before. The strokes the
## hashes read still lay each sample as an update of its own, through
## `add_sample`, so the fixture did not move.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Before and after, two ways.** The fixture holds a SHA-256 of the float
## texels each shipped preset painted on the tree before the
## change, on the adapter it names, and on that adapter each stroke is held to
## it. The texels a driver rounds are its own, so another adapter skips that
## comparison and says so. On every adapter each stroke is painted again with a
## list that sends each dab the moment it is laid, which is the route before the
## change, and the two are read back equal texel for texel, colour and height.
##
## **Taken again for a change**, whose swept stroke paints no dab and so
## paints every preset differently on purpose. The fixture holds the strokes
## as that change left them, and an event is one stretch now, laid as one list with a
## dispatch for each chunk the stretch reaches, against the same stretch sent
## a list a laying.
##
## **Taken again for a change**, which reads every field along the stroke
## and makes the pressure the cut, and holds a press until the path says where
## it goes, so every preset paints its texture laid along its path rather than
## still under it, on purpose again.
##
## **Taken again for a change**, which moves the tip after the cut, so a
## texel the tip covers only partly takes the stroke at that share of its alpha
## where the field once moved the tip's rim in and out, on purpose a third time.
##
## **Taken again for a change**, which piles height at a stroke's sides
## under a hard press, so every preset that lays height and whose S presses
## past 0.7 has a pile along its sides where the stroke is firmest, on purpose
## a fourth time. The colour is the same in all eight, the albedo of every
## chunk hashed apart on the tree before and after read alike, and Watery Lift,
## which lays no height, is unchanged.
##
## **Taken again for a change**, which takes a point of the path only a
## step on from the last and reads the field along the path's heading over the
## tip's radius rather than along each segment, so a texel at the side of the S
## reads the field a little further along or back than it did, and every
## preset's holes sit a little elsewhere, on purpose a fifth time.
##
## **Grain Round's line taken again for a change**, and no other. Grain
## Round's recipe ships its tip at a softness of 0.8, so its round falls off
## from four fifths of its radius where it was the hard disc, which is
## the look wanted: "I don't like the strict round mask". The S here is painted
## upright, so the lean that no longer turns a tip moves no other line,
## and the other seven hashes were read back as they were.
##
## **Bristle Flat's and Thick Impasto's lines taken again for a change**,
## the two presets whose field is the bristle, and no other. Each bristle now
## takes a reach, the pressure map on its streak's middle, so the light ends of
## the S lay fewer streaks and more come in as it presses, which is
## the look wanted: "add more bristles when pressure rises". Bristle Flat's recipe
## moved as well, its height read from the bristle's own channel at a Relief of
## a half and a Thickness of 0.2 mm, so its streaks lie flat and low. The other
## six hashes were read back as they were.
##
## **Five lines added with the Look page's rows**, the flat tip style presets'.
## The ten before them read back as they were, which is the rows' rests
## painting as the brush did before the rows came.
##
## **Six lines taken again for a change**, Broken Chalk's, Canvas
## Scumble's, Grain Round's, Living Colour's, Thick Impasto's and Watery Lift's.
## A round tip's update now paints the body to the newest point taken a half
## width or more behind the pen and the next update lays the rest, so the stroke
## is cut into updates at other points, and a texel by a cut finds its nearest
## segment, and the height the stroke pushes ahead of itself is measured, in
## another update than before. Five of the six move by a handful of texels, nine
## at most in Grain Round's height, and Watery Lift, whose colour thins towards
## its ends, by 39 texels of colour, the most. The S turns nowhere sharply
## enough to be drawn round a pivot: with the pivots taken out the hashes read
## the same, so it is the hold that moved them. Bristle Flat's and Dry Brush's
## lines were read back as they were.
##
## **Not taken again for a change**, which takes the warp out of Broken
## Chalk's recipe, since the swept kernel had stopped reading it and every stroke
## paints as it did. The card is no longer waited on between events: the race
## that made the Broken Chalk paint one of two strokes went with the swept kernel, and a
## probe painted it 192 times of 192 alike without the wait.
##
## **Taken again for a change**, which gives Grain Round and
## Bristle Flat a radius that follows the pen's pressure, so the S, pressed
## below one, paints those two narrower on purpose. The other six read their
## hashes as before, and only those two lines of the fixture moved.
##
## **Taken again for a change**, which thins a stroke's grain
## towards its rim below a Hardness of one, so the six presets whose Hardness
## is under one lay a thinner edge on purpose. Dry Brush and Thick Impasto, at
## a Hardness of one, read their hashes as before.
##
## **Taken again for a change**, which ships Grain Round, Bristle
## Flat, Canvas Scumble and Dry Brush at a `thickness` of 0, the one
## painters set on nearly every stroke of theirs, so those four lay
## no height and no relief on purpose, and adds Wood Grain, a ninth. The other
## four read their hashes as before.
##
## **Taken again for a change**, which gives Wood Grain a cut of
## its own, a Strength of 0.2 off the pressure and a Hardness of 0.6, so its
## full press keeps the grain on purpose. Only its line of the fixture moved,
## and the other eight read their hashes as before.
##
## **Taken again for a change**, which ships Broken Chalk at a
## `thickness` of 0 and a grain scale of 1.2, as a chalk figure set it,
## so its line moves on purpose, and adds Wet Into Wet, a tenth. Its seed is
## held now as well, which this suite's own seed already did. The other eight
## read their hashes as before.
##
## **Taken again when a stroke's first points came to answer at the first
## speed the smoother measures**, rather than at nought, so the options that
## read the speed, the thickness and the field's drift above all, lay the
## stroke's start as they lay its body, on purpose. Bristle Flat's, Living
## Colour's, Thick Impasto's, Watery Lift's and Wet Into Wet's lines moved, and
## the other five read their hashes as before.
##
## **Taken again when Broken Chalk and Wet Into Wet came to ship as a painter's
## own files hold them**, field by field, so those two lines
## moved on purpose and the other eight read their hashes as before.
##
## **Taken again when the bristle field came to fill most of a stroke's body
## at a working press**, its streaks wider with a skirt and its gaps short of
## the full press, and Thick Impasto and Wood Grain took a Strength that keeps
## their looks under it. Bristle Flat's, Thick Impasto's and Wood Grain's lines
## moved on purpose, and the other seven read their hashes as before.
##
## **Taken again when a Grain or a Picture came to be read at a texel's place on
## the canvas** rather than at its stroke coordinates, so the picture's curve
## reads the grain unbent. Broken Chalk's, Dry Brush's, Firm Fill's, Grain
## Round's, Graphite Pencil's, Living Colour's, Sea Sponge's and Watery Lift's
## lines moved on purpose, and the seven whose field is a Bristle or rides with
## the pen on the Drift row read their hashes as before.
##
## **Taken again when a Bristle's strands came to be cells of the Size row's
## width** rather than of the dab's own, so a dab narrower than a full press
## holds fewer strands of the same width. The S presses below full, so Bristle
## Flat's, Wood Grain's and Ribbon Pen's lines moved on purpose, and Thick
## Impasto and Smeary Flat, whose radius does not follow the pen, read their
## hashes as before.
##
## **Taken again when Graphite Pencil's grain came down to a pencil's**, so
## its line alone moved on purpose.
##
## **Taken again when Texture Tone came to lay its field's lightness in stops
## over the field's own range**, so the five presets that lay a tone carry
## their numbers onto the new range and keep their lightness spread to a few
## thousandths rather than bit for bit. Firm Fill's, Graphite Pencil's, Ribbon
## Pen's, Sea Sponge's and Smeary Flat's lines moved, and the other ten, every
## Bristle at Strand Softness's new rest among them, read their hashes as before.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseDabListScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd")

## The hashes of the tree before the change, and the adapter they were taken on.
const FIXTURE: String = "res://modules/sara-noise-brush-engine/tests/fixtures/paint.json"
## Set to anything to write the fixture from this run instead of reading it.
const WRITE_ENV: String = "SARA_WRITE_D13_PAINT"

## The canvas a preset's picture is painted on, so every dab is the size the
## pictures paint it at.
const CANVAS := Vector2i(512, 256)
## The samples of the stroke, the picture's forty, and the time between two,
## the sixty a second the shipped speed curves were drawn at.
const SAMPLES: int = 40
const FRAME_MS: float = 1000.0 / 60.0
const INK := Color(0.08, 0.08, 0.1, 1.0)

var _surface: SaSurface = null


## The route before the change: each dab sent as a list of its own the moment
## it is laid, its dirty rectangles committed with it.
class AloneList:
    extends "res://modules/sara-noise-brush-engine/dab_list/noise_dab_list.gd"

    func lay(paint: SaPaintContext, compute: SaCompute, dispatcher: Callable) -> void:
        super.lay(paint, compute, dispatcher)
        send()


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
        _surface = null


## Where the S is at *t*, the picture's own path across the canvas.
static func point_at(t: float) -> Vector2:
    var inset := float(CANVAS.y) * 0.28
    var x := inset + t * (float(CANVAS.x) - 2.0 * inset)
    var y := float(CANVAS.y) * 0.5 - sin(t * TAU) * (float(CANVAS.y) * 0.5 - inset)
    return Vector2(x, y)


## A fresh surface and a brush of *settings* on it.
func _brush(settings: Resource) -> StateNoiseBrushScript:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 1
    settings.color = INK
    brush.settings = settings
    return brush


## The S with the pressure up and back down, a pen's press held for the first
## sample, and every sample at its own time. The card is not waited on between
## two, since the race that asked for it is gone: a Broken Chalk stroke painted
## one of two results unless the card was waited on, and does not now.
func _stroke(brush: StateNoiseBrushScript) -> void:
    brush.begin_stroke(point_at(0.0), 0.0, Vector2.ZERO, 0.0, true)
    for i in range(1, SAMPLES + 1):
        var t := float(i) / float(SAMPLES)
        brush.add_sample(point_at(t), sin(t * PI), Vector2.ZERO, i * FRAME_MS)
    brush.end_stroke()


## Every chunk's colour and height on the active layer, as the bytes the card
## holds, by grid position and field. Bytes rather than an image, since the
## height is half floats.
func _texels() -> Dictionary:
    var layer := _surface.easel.document.active_layer
    var rd := GlobalShaderCompiler.get_rd()
    var out := {}
    for grid: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid] as SaChunk
        out["%s albedo" % grid] = rd.texture_get_data(chunk.albedo().rid, 0)
        if chunk.has_field(SaFieldSpec.HEIGHT):
            out["%s height" % grid] = rd.texture_get_data(chunk.field(SaFieldSpec.HEIGHT).rid, 0)
    return out


static func _hash(texels: Dictionary) -> String:
    var keys := texels.keys()
    keys.sort()
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    for key: String in keys:
        context.update(key.to_utf8_buffer())
        context.update(texels[key])
    return context.finish().hex_encode()


func _presets() -> Dictionary:
    var out := {}
    for entry: Dictionary in NoisePresetsScript.entries():
        out[entry["name"]] = entry
    return out


## The card and the system, since the same card paints the noise presets to
## other hashes under Windows than under Linux, its driver
## rounding the kernel's sums another way.
func _adapter() -> String:
    return "%s under %s" % [RenderingServer.get_video_adapter_name(), OS.get_name()]


func _read_fixture() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    return parsed if parsed is Dictionary else {}


func test_every_noise_preset_paints_what_it_painted_before_the_change() -> void:
    var presets := _presets()
    assert_eq(presets.size(), 15, "the fifteen shipped presets were read")
    var painted := {}
    for preset_name: String in presets:
        var brush := _brush(NoisePresetsScript.build(NoiseBrushSettingsScript, presets[preset_name]))
        _stroke(brush)
        var texels := _texels()
        assert_false(texels.is_empty(), "%s painted" % preset_name)
        painted[preset_name] = _hash(texels)

    if not OS.get_environment(WRITE_ENV).is_empty():
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE.get_base_dir()))
        var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
        file.store_string(JSON.stringify({"adapter": _adapter(), "strokes": painted}, "  ", true) + "\n")
        file = null
        print("wrote %d strokes to %s" % [painted.size(), FIXTURE])

    var recorded := _read_fixture()
    var strokes: Dictionary = recorded.get("strokes", {})
    assert_eq(strokes.size(), painted.size(), "the fixture holds every preset")
    if String(recorded.get("adapter", "")) != _adapter():
        skip("the fixture was taken on %s and this is %s" % [recorded.get("adapter", ""), _adapter()])
        return
    for preset_name: String in painted:
        assert_eq(painted[preset_name], strokes.get(preset_name, ""), "%s paints the stroke it painted before" % preset_name)


func test_every_noise_preset_paints_what_a_list_a_dab_paints() -> void:
    var presets := _presets()
    for preset_name: String in presets:
        var brush := _brush(NoisePresetsScript.build(NoiseBrushSettingsScript, presets[preset_name]))
        _stroke(brush)
        var listed := _texels()
        brush = _brush(NoisePresetsScript.build(NoiseBrushSettingsScript, presets[preset_name]))
        brush.dab_list = AloneList.new(StateNoiseBrushScript.KERNEL)
        _stroke(brush)
        var alone := _texels()
        assert_eq(listed.keys().size(), alone.keys().size(), "%s paints the same chunks either way" % preset_name)
        var differ := PackedStringArray()
        for key: String in alone:
            if listed.get(key, PackedByteArray()) != alone[key]:
                differ.append(key)
        assert_eq(differ, PackedStringArray(), "%s paints the same texels as a list a dab" % preset_name)


func test_a_frame_s_motions_at_full_pressure_are_one_list() -> void:
    var entry: Dictionary = {}
    for one: Dictionary in NoisePresetsScript.entries():
        if one["name"] == "Grain Round":
            entry = one
    var brush := _brush(NoisePresetsScript.build(NoiseBrushSettingsScript, entry))
    brush.begin_stroke(point_at(0.0), 1.0, Vector2.ZERO, 0.0, true)
    # The curve holds a sample back, so the third motion is the first whose
    # points reach as far as the motion before it.
    brush.add_sample(point_at(0.025), 1.0, Vector2.ZERO, FRAME_MS)
    brush.add_sample(point_at(0.05), 1.0, Vector2.ZERO, 2.0 * FRAME_MS)
    var before := _tally()
    for i in range(3, 6):
        brush.gather_sample(point_at(0.025 * i), 1.0, Vector2.ZERO, i * FRAME_MS / 3.0 + 2.0 * FRAME_MS)
    var gathered := _tally()
    brush.lay_frame()
    var after := _tally()
    brush.end_stroke()
    assert_eq(gathered.x - before.x, 0, "the frame's motions waited for the frame")
    assert_eq(after.x - before.x, 1, "the frame's three motions went to the card as one list")
    assert_true(after.y - before.y >= 1, "and the list held their stretch's dispatches, %d" % (after.y - before.y))
    assert_eq(after.z - before.z, 0, "and none went as a list of its own")


## The lists sent under the list's label, the kernel's dispatches, and the
## lists the kernel was sent in under its own names, which are the shader's
## and its kernel's.
static func _tally() -> Vector3i:
    var table := SaCompute.kernel_counters()
    var out := Vector3i(int(table.get(NoiseDabListScript.LIST_LABEL, {}).get("lists", 0)), 0, 0)
    for key: String in table:
        if key != NoiseDabListScript.LIST_LABEL and key.begins_with(StateNoiseBrushScript.KERNEL):
            out.y += int(table[key].get("dispatches", 0))
            out.z += int(table[key].get("lists", 0))
    return out
