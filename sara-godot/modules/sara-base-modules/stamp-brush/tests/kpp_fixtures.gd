## Writes the Krita preset fixtures the reader's test and the committed files
## under `fixtures/` are made from.
##
## **Written by hand, from the format, rather than taken from a
## painter's data.** A fixture is committed, and a painter's presets are the
## painter's work. So the two presets here are Sara's own: a generated round tip and a
## four by four PNG tip, with an option tree small enough to read in a test and
## shaped like the real thing, the sensor params as `<params id="pressure"/>`
## text, the curves as `x,y;` lists, the tip embedded base64 in a `resource`
## element with an md5sum the brush definition repeats.
##
## **The text chunk is written the way Krita's writer writes it.** The first
## preset goes into a `zTXt`, the second into a compressed `iTXt`, because its
## name carries a letter Latin-1 has not got, and the `version` key is a plain
## `tEXt`, which is what real presets look like. A fixture
## that stored the XML as `tEXt` would prove a reader that reads none of them.
##
## Not a suite: the name has no `test_` prefix, so the runner does not collect
## it, and `test_kpp_reader.gd` preloads it.
extends RefCounted

const ROUND_NAME: String = "Sara fixture round"
const PNG_NAME: String = "Sara fixture png tip ž"
const PIPE_NAME: String = "Sara fixture pipe"
const PIPE_UNKNOWN_NAME: String = "Sara fixture pipe unknown"
const MASKING_NAME: String = "Sara fixture masking"
const MASKING_DYNAMICS_NAME: String = "Sara fixture masking dynamics"
const SOFT_NAME: String = "Sara fixture soft"
const COLOUR_NAME: String = "Sara fixture colour"
const SPACING_NAME: String = "Sara fixture spacing"
const GRADIENT_MAP_NAME: String = "Sara fixture gradient map"
const GRADIENT_SOURCE_NAME: String = "Sara fixture gradient source"
const TIP_FILE: String = "sara-fixture-tip.png"
const GRADIENT_TIP_FILE: String = "sara-fixture-gradient-tip.png"
const PATTERN_FILE: String = "sara-fixture-grain.png"
const PIPE_FILE: String = "sara-fixture-pipe.gih"
const PIPE_UNKNOWN_FILE: String = "sara-fixture-pipe-unknown.gih"
## The second tip a bundle of brushes carries, so a count in a test is not
## also the count of tips one preset embeds.
const SECOND_TIP_FILE: String = "sara-fixture-tip-two.png"
const BUNDLE_LICENCE: String = "CC0 1.0, written by Sara's own test"
const BUNDLE_AUTHOR: String = "Sara"

## The tip: four by four, white with a black two by two at the centre, so the
## loader's `(1 - red) * alpha` gives four texels of full coverage and twelve
## of none, and a test can name which.
const TIP_SIZE: int = 4

## The gradient map fixture's tip, 64 pixels a side, black over its top rows,
## a mid grey of 128 through its middle and white over its bottom, with short
## ramps between, so a level stroke reads the gradient's start along its top
## edge, its middle along its centre and its end along its foot. Each entry is
## the first row of a run.
const GRADIENT_TIP_SIDE: int = 64
const GRADIENT_TIP_RUNS: Array[int] = [0, 16, 24, 40, 48]
const GRADIENT_TIP_GREY: float = 128.0 / 255.0

## The falloff the soft fixture's mask generator carries, in Krita's own `x,y;`
## form. It holds full coverage well past the centre and then drops to nothing
## at the rim, which is neither Sara's default falloff nor the identity, so a
## stroke shows at a glance whether the curve was read.
const SOFT_CURVE: String = "0,1;0.55,0.98;0.75,0.55;1,0;"

## The curve the spacing fixture's sensor carries, in Krita's own `x,y;` form
## and off the diagonal, so a page that showed a fresh option would not pass.
const SPACING_CURVE: String = "0,0;0.4,0.9;1,1;"

## The colour fixture's five stems, under Krita's own ids, which for the three
## HSV options are one letter each: the Krita stem, the sensor it is driven by,
## the strength and the common curve. A different sensor on each, so an option
## that came from the wrong stem reads the wrong sensor in the test.
const COLOUR_STEM_SENSORS: Array = [
    ["h", "fuzzy", "0.35", "0,0;1,1;"],
    ["s", "pressure", "0.6", "0,0;1,1;"],
    ["v", "speed", "1", "0,0;1,1;"],
    ["Darken", "distance", "0.8", "0,0;1,1;"],
    ["Mix", "pressure", "1", "0,0;0.5,0.2;1,1;"],
]

## The Mix curve the gradient source fixture carries on pressure, in Krita's own
## `x,y;` form and well under the diagonal, so a low press reads near the curve's
## foot and a curve turned over on the way in, as a plain source's is, reads near
## its top instead.
const GRADIENT_SOURCE_MIX_CURVE: String = "0,0;0.5,0.2;1,1;"

static var _crc_table: PackedInt64Array = PackedInt64Array()


## The round preset's `.kpp` bytes.
static func round_kpp() -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    var xml := _preset_xml(ROUND_NAME, params, [])
    return _kpp(xml, "zTXt")


## The colour preset's `.kpp` bytes: an auto brush with the five colour stems
## Sara carries switched on, each on a sensor of its own so a test can tell
## which landed where, and `ColorSource/Type` plain.
##
## A third committed fixture rather than params added to the round one, for the reason
## the soft one is: `test_the_round_fixture_imports_onto_the_settings` asserts the
## round preset carries whole, and a colour stem on it would make a second unit's test
## say something about this one.
##
## Mix carries a curve that is not the identity, because Mix is the one stem
## whose curve is turned over on the way in, and an identity turned over is a
## line that would pass for the default a careless read leaves.
static func colour_kpp() -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    params["ColorSource/Type"] = ["string", "plain"]
    for entry: Array in COLOUR_STEM_SENSORS:
        var stem := String(entry[0])
        params["Pressure" + stem] = ["internal", "true"]
        params[stem + "UseCurve"] = ["internal", "true"]
        params[stem + "Value"] = ["internal", String(entry[2])]
        params[stem + "Sensor"] = ["string", '<!DOCTYPE params>\n<params id="%s"/>\n' % String(entry[1])]
        params[stem + "commonCurve"] = ["string", String(entry[3])]
    return _kpp(_preset_xml(COLOUR_NAME, params, []), "zTXt")


## The spacing preset's `.kpp` bytes: an auto brush whose Spacing option, the
## sensor Krita keeps under the stem `Spacing`, follows speed through a curve
## that is not the identity. A fourth fixture for the reason the colour one is a
## third: the round one is asserted whole, and a stem added to it would make
## another suite say something about it.
static func spacing_kpp() -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    params["PressureSpacing"] = ["internal", "true"]
    params["SpacingUseCurve"] = ["internal", "true"]
    params["SpacingValue"] = ["internal", "1"]
    params["SpacingSensor"] = ["string", '<!DOCTYPE params>\n<params id="speed"/>\n']
    params["SpacingcommonCurve"] = ["string", SPACING_CURVE]
    return _kpp(_preset_xml(SPACING_NAME, params, []), "zTXt")


## The PNG tip preset's `.kpp` bytes. The pattern resource beside the tip is
## there so a reader that takes the first resource it meets takes the wrong one.
##
## *application* is Krita's `brushApplication` number for the tip, 0 the plain
## mask, 2 lightness map and 3 gradient map.
static func png_kpp(application: int = 0) -> PackedByteArray:
    var tip := tip_png()
    var grain := _grain_png()
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush angle="0" spacing="0.25" filename="%s" ColorAsMask="1" type="png_brush" scale="1"' % TIP_FILE
            + ' AdjustmentMidPoint="127" BrushVersion="2" ContrastAdjustment="0" AdjustmentVersion="2"'
            + ' AutoAdjustMidPoint="1" useAutoSpacing="0" brushApplication="%d" md5sum="%s"' % [application, _md5(tip)]
            + ' autoSpacingCoeff="1" BrightnessAdjustment="0"/>'
        )
    ]
    params["Texture/Pattern/Enabled"] = ["internal", "true"]
    params["Texture/Pattern/PatternFileName"] = ["string", PATTERN_FILE]
    var resources := [
        {"name": PATTERN_FILE.get_basename(), "filename": PATTERN_FILE, "type": "patterns", "bytes": grain},
        {"name": TIP_FILE.get_basename(), "filename": TIP_FILE, "type": "brushes", "bytes": tip},
    ]
    var xml := _preset_xml(PNG_NAME, params, resources)
    return _kpp(xml, "iTXt")


## A preset on Krita's colour source *source*, `ColorSource/Type`, with Mix on
## pressure through [constant GRADIENT_SOURCE_MIX_CURVE] at *mix_strength*. A hard
## round auto brush whose size and opacity follow nothing, so a dab paints whole
## at any pressure and Mix is the one thing a press moves. Committed under
## `fixtures/` as `sara-gradient-source.kpp` with the defaults, because a scenario
## imports it, and Krita's ids for its other sources are `uniform_random`,
## `total_random`, `pattern` and `lockedpattern`.
static func gradient_source_kpp(source: String = "gradient", mix_strength: String = "1") -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="1" id="default" spikes="2" antialiasEdges="1" hfade="1"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    params["PressureOpacity"] = ["internal", "false"]
    params["PressureSize"] = ["internal", "false"]
    params["ColorSource/Type"] = ["string", source]
    params["PressureMix"] = ["internal", "true"]
    params["MixUseCurve"] = ["internal", "true"]
    params["MixValue"] = ["internal", mix_strength]
    params["MixSensor"] = ["string", '<!DOCTYPE params>\n<params id="pressure"/>\n']
    params["MixcommonCurve"] = ["string", GRADIENT_SOURCE_MIX_CURVE]
    var name := GRADIENT_SOURCE_NAME if source == "gradient" else "Sara fixture %s source" % source
    return _kpp(_preset_xml(name, params, []), "zTXt")


## A preset whose picture tip is in Krita's gradient map mode, `brushApplication`
## 3, as Krita writes one for a colour tip. Committed under `fixtures/` as
## `sara-gradient-map.kpp`, because a scenario imports it, and written here so
## the committed file and this writer cannot drift. Like every `.kpp` it holds
## no gradient, Krita painting through the canvas's current one.
static func gradient_map_kpp() -> PackedByteArray:
    var tip := gradient_tip_png()
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush angle="0" spacing="0.1" filename="%s" ColorAsMask="1" type="png_brush" scale="1"' % GRADIENT_TIP_FILE
            + ' AdjustmentMidPoint="127" BrushVersion="2" ContrastAdjustment="0" AdjustmentVersion="2"'
            + ' AutoAdjustMidPoint="1" useAutoSpacing="0" brushApplication="3" md5sum="%s"' % _md5(tip)
            + ' autoSpacingCoeff="1" BrightnessAdjustment="0"/>'
        )
    ]
    var resources := [{"name": GRADIENT_TIP_FILE.get_basename(), "filename": GRADIENT_TIP_FILE, "type": "brushes", "bytes": tip}]
    return _kpp(_preset_xml(GRADIENT_MAP_NAME, params, resources), "zTXt")


## The gradient map fixture's picture as PNG bytes, the rows of
## [constant GRADIENT_TIP_RUNS] and opaque throughout but for one corner texel.
## That one is transparent and red, because `SaTipImage` reads a picture whose
## every texel is grey as a mask of mid lightness, and the corner is what makes
## this a picture carrying colour, the only kind Krita gives a gradient map.
static func gradient_tip_png() -> PackedByteArray:
    var image := Image.create_empty(GRADIENT_TIP_SIDE, GRADIENT_TIP_SIDE, false, Image.FORMAT_RGBA8)
    for y in GRADIENT_TIP_SIDE:
        var grey := gradient_tip_grey(y)
        image.fill_rect(Rect2i(0, y, GRADIENT_TIP_SIDE, 1), Color(grey, grey, grey, 1.0))
    image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 0.0))
    return image.save_png_to_buffer()


## The grey of the gradient map fixture's row *y*, as the PNG stores it.
static func gradient_tip_grey(y: int) -> float:
    var runs := GRADIENT_TIP_RUNS
    if y >= runs[4]:
        return 1.0
    if y >= runs[3]:
        return lerpf(GRADIENT_TIP_GREY, 1.0, float(y - runs[3] + 1) / float(runs[4] - runs[3] + 1))
    if y >= runs[2]:
        return GRADIENT_TIP_GREY
    if y >= runs[1]:
        return lerpf(0.0, GRADIENT_TIP_GREY, float(y - runs[1] + 1) / float(runs[2] - runs[1] + 1))
    return 0.0


## A preset whose auto brush is Krita's soft generator and carries a softness
## curve. Committed under `fixtures/` beside the other two, because a scenario
## paints with it, and written here as well so the committed file and this
## writer cannot drift.
static func soft_kpp() -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.08" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="1" id="softbrush" spikes="2" antialiasEdges="1" hfade="1"'
            + ' diameter="90" softness_curve="%s"/> </Brush>' % SOFT_CURVE
        )
    ]
    return _kpp(_preset_xml(SOFT_NAME, params, []), "zTXt")


## A preset whose tip is a GIMP pipe, which the import carries: the pipe's
## cells are written to the tips folder and the tip selected the way a `.gbr`
## is. Four cells of 4 by 4, each a flat coverage, advancing incrementally, so
## a stroke paints a different cell per dab.
static func pipe_kpp() -> PackedByteArray:
    var pipe := _pipe_gih()
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="gih_brush" filename="%s" md5sum="%s" spacing="0.2" angle="0" scale="10" BrushVersion="2"/>'
            % [PIPE_FILE, _md5(pipe)]
        )
    ]
    var resources := [{"name": PIPE_FILE.get_basename(), "filename": PIPE_FILE, "type": "brushes", "bytes": pipe}]
    return _kpp(_preset_xml(PIPE_NAME, params, resources), "zTXt")


## A preset whose pipe names a selection mode Sara's eight do not cover, which
## the import tags with the mode rather than with the whole tip.
static func pipe_unknown_kpp() -> PackedByteArray:
    var pipe := _pipe_gih("sel0:sideways")
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="gih_brush" filename="%s" md5sum="%s" spacing="0.2" angle="0" scale="10" BrushVersion="2"/>'
            % [PIPE_UNKNOWN_FILE, _md5(pipe)]
        )
    ]
    var resources := [{"name": PIPE_UNKNOWN_FILE.get_basename(), "filename": PIPE_UNKNOWN_FILE, "type": "brushes", "bytes": pipe}]
    return _kpp(_preset_xml(PIPE_UNKNOWN_NAME, params, resources), "zTXt")


## A preset named *preset_name* whose tip is the pipe *gih* under *file_name*,
## embedded when *embedded* and only named when not, which is a preset exported
## without its tip. One is built per cause a real pipe is refused
## for, each with the parameter line Krita's own file carries.
static func gih_kpp(preset_name: String, file_name: String, gih: PackedByteArray, embedded: bool) -> PackedByteArray:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="gih_brush" filename="%s" md5sum="%s" spacing="0.2" angle="0" scale="10" BrushVersion="2"/>'
            % [file_name, _md5(gih)]
        )
    ]
    var resources := []
    if embedded:
        resources.append({"name": file_name.get_basename(), "filename": file_name, "type": "brushes", "bytes": gih})
    return _kpp(_preset_xml(preset_name, params, resources), "zTXt")


## A pipe of *cells* 4 by 4 cells under the parameter *line*, each a flat
## coverage, with only the first *written* of them in the file, so a test can
## write a pipe that promises more tips than it holds.
static func gih_with(line: String, cells: int, written: int) -> PackedByteArray:
    var bytes := ("Sara pipe\n" + line + "\n").to_utf8_buffer()
    for index in mini(cells, written):
        bytes.append_array(_pipe_cell(64 + 48 * index))
    return bytes


## A GIMP pipe of four 4 by 4 cells, each a flat coverage so a test names which
## cell a dab picked, with *selection* as the parameter line's `sel0`.
static func _pipe_gih(selection: String = "sel0:incremental") -> PackedByteArray:
    var cells: Array = []
    for value: int in [64, 128, 192, 255]:
        cells.append(_pipe_cell(value))
    var line := "4 ncells:4 cellwidth:4 cellheight:4 step:20 dim:1 cols:1 rows:4 placement:constant rank0:4 " + selection
    var bytes := ("Sara pipe\n" + line + "\n").to_utf8_buffer()
    for cell: PackedByteArray in cells:
        bytes.append_array(cell)
    return bytes


## One version 2 GBR cell of a pipe, 4 by 4, filled with *coverage*.
static func _pipe_cell(coverage: int) -> PackedByteArray:
    var named := "cell".to_utf8_buffer()
    var body := PackedByteArray()
    body.resize(16)
    body.fill(coverage)
    var bytes := PackedByteArray()
    bytes.append_array(_be(28 + named.size() + 1))
    bytes.append_array(_be(2))
    bytes.append_array(_be(4))
    bytes.append_array(_be(4))
    bytes.append_array(_be(1))
    bytes.append_array(_be(0x47494D50))
    bytes.append_array(_be(20))
    bytes.append_array(named)
    bytes.append(0)
    bytes.append_array(body)
    return bytes


## A preset carrying a masking brush, which is Krita's second brush over every
## dab, written the way Krita writes one: the mask's whole preset under
## `MaskingBrush/Preset/`, its own `brush_definition` among it.
##
## **The mask is a rectangle and the painted tip is a circle**, at a different
## ratio, a different spacing and a different pair of fades, so a test reading
## the second tip cannot be reading the first by accident.
##
## **It carries cleanly on purpose.** The composite op is `multiply`, which is
## the one Sara's mask has, and no `Pressure` switch is set under the mask's
## preset, so the import leaves no tag at all and the assertion that the
## `masking brush` phrase is gone is not standing on a second phrase taking its
## place. What each of the four phrases costs is the test's own to make out of
## an option tree by hand.
static func masking_kpp() -> PackedByteArray:
    return _kpp(_preset_xml(MASKING_NAME, _masking_params(), []), "zTXt")


## The masking fixture's params, shared by the fixture that adds the mask's own
## curves to them.
static func _masking_params() -> Dictionary:
    var params := _common_params()
    params["brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.1" angle="0">'
            + ' <MaskGenerator ratio="1" type="circle" vfade="0.5" id="default" spikes="2" antialiasEdges="1" hfade="0.5"'
            + ' diameter="40"/> </Brush>'
        )
    ]
    params["MaskingBrush/Enabled"] = ["internal", "true"]
    params["MaskingBrush/MaskingCompositeOp"] = ["string", "multiply"]
    params["MaskingBrush/UseMasterSize"] = ["internal", "true"]
    params["MaskingBrush/MasterSizeCoeff"] = ["internal", "0.75"]
    params["MaskingBrush/Preset/brush_definition"] = [
        "string",
        (
            '<Brush type="auto_brush" useAutoSpacing="0" randomness="0" density="1" autoSpacingCoeff="1" BrushVersion="2"'
            + ' spacing="0.3" angle="0">'
            + ' <MaskGenerator ratio="0.5" type="rect" vfade="0.4" id="gauss" spikes="2" antialiasEdges="1" hfade="0.4"'
            + ' diameter="24"/> </Brush>'
        )
    ]
    return params


## The masking fixture with its mask's own curves switched on, the way Krita
## writes them under `MaskingBrush/Preset/`: the mask turns with
## the pen's tilt, scatters on pressure along one axis, keeps a flow on
## pressure and flips on pressure. Ratio is on as well, the one stem here Sara's
## mask has no option for, so the import has exactly one tag to leave and the
## test can say which.
static func masking_dynamics_kpp() -> PackedByteArray:
    var params := _masking_params()
    var mask := "MaskingBrush/Preset/"
    for entry: Array in [
        ["Rotation", "tiltdirection"],
        ["Scatter", "pressure"],
        ["Flow", "pressure"],
        ["Mirror", "pressure"],
        ["Ratio", "pressure"]
    ]:
        var stem := String(entry[0])
        params[mask + "Pressure" + stem] = ["internal", "true"]
        params[mask + stem + "UseCurve"] = ["internal", "true"]
        params[mask + stem + "Sensor"] = ["string", '<!DOCTYPE params>\n<params id="%s"/>\n' % String(entry[1])]
    params[mask + "ScatterValue"] = ["internal", "2"]
    params[mask + "Scatter/AxisX"] = ["internal", "true"]
    params[mask + "Scatter/AxisY"] = ["internal", "false"]
    params[mask + "Mirror/HorizontalMirror"] = ["internal", "false"]
    params[mask + "Mirror/VerticalMirror"] = ["internal", "true"]
    return _kpp(_preset_xml(MASKING_DYNAMICS_NAME, params, []), "zTXt")


## A `.bundle` of the two committed presets, with the manifest tagging each
## and a `meta.xml` that states the licence both ways the format has.
static func bundle(round_bytes: PackedByteArray, png_bytes: PackedByteArray, path: String) -> Error:
    var packer := ZIPPacker.new()
    var err := packer.open(path)
    if err != OK:
        return err
    var entries := {
        "paintoppresets/sara-round.kpp": round_bytes,
        "paintoppresets/sara-png-tip.kpp": png_bytes,
    }
    _pack(packer, "mimetype", "application/x-krita-resourcebundle".to_utf8_buffer())
    _pack(packer, "META-INF/manifest.xml", _manifest(entries).to_utf8_buffer())
    _pack(packer, "meta.xml", _meta().to_utf8_buffer())
    for entry: String in entries:
        _pack(packer, entry, entries[entry])
    return packer.close()


## A `.bundle` of brush tips and no preset at all, which is what Krita writes
## when a painter exports a brushes folder: two tips the loader reads, a
## `.gih` collection it will not, and the bundle's own three files.
static func tips_bundle(path: String) -> Error:
    var packer := ZIPPacker.new()
    var err := packer.open(path)
    if err != OK:
        return err
    _pack(packer, "mimetype", "application/x-krita-resourcebundle".to_utf8_buffer())
    _pack(packer, "META-INF/manifest.xml", _manifest({}).to_utf8_buffer())
    _pack(packer, "meta.xml", _meta().to_utf8_buffer())
    _pack(packer, "brushes/" + TIP_FILE, tip_png())
    _pack(packer, "brushes/" + SECOND_TIP_FILE, tip_png())
    _pack(packer, "brushes/" + PIPE_FILE, "a pipe is a collection, not a tip".to_utf8_buffer())
    return packer.close()


## A `.bundle` of neither a preset nor a tip: the bundle's own three files and
## a preview beside them, which is what a real bundle of that kind
## holds and what the refusal has to describe.
static func empty_bundle(path: String) -> Error:
    var packer := ZIPPacker.new()
    var err := packer.open(path)
    if err != OK:
        return err
    _pack(packer, "mimetype", "application/x-krita-resourcebundle".to_utf8_buffer())
    _pack(packer, "META-INF/manifest.xml", _manifest({}).to_utf8_buffer())
    _pack(packer, "meta.xml", _meta().to_utf8_buffer())
    _pack(packer, "preview.png", tip_png())
    return packer.close()


## The tip image as PNG bytes, which the test decodes on its own to say what
## coverage the reader's tip has to carry.
static func tip_png() -> PackedByteArray:
    var image := Image.create_empty(TIP_SIZE, TIP_SIZE, false, Image.FORMAT_RGBA8)
    image.fill(Color.WHITE)
    for y in range(1, 3):
        for x in range(1, 3):
            image.set_pixel(x, y, Color.BLACK)
    return image.save_png_to_buffer()


static func _grain_png() -> PackedByteArray:
    var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.5, 0.5, 0.5, 1.0))
    return image.save_png_to_buffer()


## The options every fixture shares: a few of the rows a real preset carries,
## in the three shapes a value takes, an `internal` scalar, a `string` that is
## a curve, and a `string` that is a sensor's own XML.
static func _common_params() -> Dictionary:
    return {
        "CompositeOp": ["string", "normal"],
        "EraserMode": ["internal", "false"],
        "OpacityValue": ["internal", "1"],
        "PressureOpacity": ["internal", "true"],
        "OpacityUseCurve": ["internal", "true"],
        "OpacitySensor": ["string", '<!DOCTYPE params>\n<params id="pressure"/>\n'],
        "OpacitycommonCurve": ["string", "0,0;0.5,0.75;1,1;"],
        "OpacitycurveMode": ["internal", "0"],
        "PressureSize": ["internal", "true"],
        "SizeSensor": ["string", '<!DOCTYPE params>\n<params id="pressure"/>\n'],
        "SizecommonCurve": ["string", "0,0;1,1;"],
        "PaintOpAction": ["internal", "2"],
        "FlowValue": ["internal", "1"],
    }


static func _preset_xml(name: String, params: Dictionary, resources: Array) -> String:
    var out := '<Preset name="%s" embedded_resources="%d" paintopid="paintbrush">' % [name, resources.size()]
    if not resources.is_empty():
        out += " <resources>"
        for resource: Dictionary in resources:
            out += (
                ' <resource name="%s" md5sum="%s" filename="%s" type="%s"><![CDATA[%s]]></resource>'
                % [
                    resource["name"],
                    _md5(resource["bytes"]),
                    resource["filename"],
                    resource["type"],
                    Marshalls.raw_to_base64(resource["bytes"]),
                ]
            )
        out += " </resources>"
    var names := params.keys()
    names.sort()
    for param_name: String in names:
        var pair: Array = params[param_name]
        if pair[0] == "string":
            out += ' <param name="%s" type="string"><![CDATA[%s]]></param>' % [param_name, pair[1]]
        else:
            out += ' <param name="%s" type="%s">%s</param>' % [param_name, pair[0], pair[1]]
    out += " </Preset>"
    return out


static func _manifest(entries: Dictionary) -> String:
    var out := '<?xml version="1.0" encoding="UTF-8"?>\n'
    out += '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">\n'
    out += ' <manifest:file-entry manifest:media-type="application/x-krita-resourcebundle" manifest:full-path="/"/>\n'
    for entry: String in entries:
        out += (
            ' <manifest:file-entry manifest:media-type="paintoppresets" manifest:full-path="%s" manifest:md5sum="%s">\n'
            % [entry, _md5(entries[entry])]
        )
        out += (
            "  <manifest:tags>\n   <manifest:tag>Sara fixtures</manifest:tag>\n   <manifest:tag>%s</manifest:tag>\n"
            % ("Round" if entry.contains("round") else "Textured")
        )
        out += "  </manifest:tags>\n </manifest:file-entry>\n"
    out += "</manifest:manifest>\n"
    return out


static func _meta() -> String:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n<meta:meta>\n'
        + " <meta:generator>Sara test fixture</meta:generator>\n <meta:bundle-version>1</meta:bundle-version>\n"
        + " <dc:author>%s</dc:author>\n <dc:title>Sara fixtures</dc:title>\n" % BUNDLE_AUTHOR
        + " <dc:description>Two presets written by a test.</dc:description>\n"
        + " <meta:license>%s</meta:license>\n <meta:website></meta:website>\n" % BUNDLE_LICENCE
        + ' <meta:meta-userdefined meta:name="email" meta:value=""/>\n'
        + ' <meta:meta-userdefined meta:name="license" meta:value="%s"/>\n</meta:meta>\n' % BUNDLE_LICENCE
    )


static func _pack(packer: ZIPPacker, entry: String, bytes: PackedByteArray) -> void:
    packer.start_file(entry)
    packer.write_file(bytes)
    packer.close_file()


## A `.kpp`: a PNG thumbnail with the preset XML in a text chunk after IHDR.
## *chunk_kind* picks which of the two compressed forms the XML takes.
static func _kpp(xml: String, chunk_kind: String) -> PackedByteArray:
    var thumbnail := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
    thumbnail.fill(Color(0.9, 0.6, 0.2, 1.0))
    var png := thumbnail.save_png_to_buffer()
    # Signature, then IHDR, whose data is always thirteen bytes.
    var after_ihdr := 8 + 8 + 13 + 4
    var out := png.slice(0, after_ihdr)
    out.append_array(_chunk("tEXt", "version".to_ascii_buffer() + PackedByteArray([0]) + "5.0".to_ascii_buffer()))
    out.append_array(_chunk(chunk_kind, _text_body(chunk_kind, "preset", xml)))
    out.append_array(png.slice(after_ihdr))
    return out


static func _text_body(chunk_kind: String, key: String, text: String) -> PackedByteArray:
    var body := key.to_ascii_buffer()
    body.append(0)
    if chunk_kind == "zTXt":
        body.append(0)
        body.append_array(text.to_ascii_buffer().compress(FileAccess.COMPRESSION_DEFLATE))
    else:
        # Compressed, method zero, an empty language tag and an empty translated
        # keyword, each with its terminator.
        body.append_array(PackedByteArray([1, 0, 0, 0]))
        body.append_array(text.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE))
    return body


static func _chunk(kind: String, data: PackedByteArray) -> PackedByteArray:
    var out := _be(data.size())
    var typed := kind.to_ascii_buffer()
    typed.append_array(data)
    out.append_array(typed)
    out.append_array(_be(_crc32(typed)))
    return out


static func _be(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


## The CRC every PNG chunk ends with, over its type and data. The engine
## exposes no CRC32, so the table is built once here.
static func _crc32(bytes: PackedByteArray) -> int:
    if _crc_table.is_empty():
        _crc_table.resize(256)
        for n in 256:
            var c := n
            for _k in 8:
                c = (0xEDB88320 ^ (c >> 1)) if (c & 1) == 1 else (c >> 1)
            _crc_table[n] = c
    var crc := 0xFFFFFFFF
    for byte in bytes:
        crc = _crc_table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func _md5(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_MD5)
    context.update(bytes)
    return context.finish().hex_encode()
