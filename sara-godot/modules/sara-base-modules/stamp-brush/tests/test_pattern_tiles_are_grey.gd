## Every pattern tile is grey, whichever loader made it.
##
## On the Brush Editor's Texture page the three GIMP patterns of a Krita import
## must not be drawn as red tiles beside the shipped Canvas Weave and Dot Screen
## in grey. A pattern is one value per texel,
## and the two loaders answered in two one-channel formats: a generated one came
## back `FORMAT_L8` because `SaPatternKernel.picture` converted, and a loaded
## picture came back `FORMAT_RF`, which the engine draws as red with nothing in
## green or blue.
##
## So the assertion is red equal to green equal to blue on a tile of each kind,
## and it is written against the chooser rather than against either loader,
## because the chooser is the one place a pattern becomes a tile and the bug was
## exactly that the rule lived in one of the two paths.
extends "res://tests/test_framework.gd"

## The chooser builds a texture per cell, and a generated pattern is a dispatch.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d37_patterns")
const PNG_NAME := "d37_scanned.png"

## The shipped one this reads, which is a kernel and takes the generated path.
const GENERATED := "Dot Screen"
## The ones the module ships, so the written one is whichever name is not one of
## them. Asked of the store rather than spelled out, because `name_for` runs the
## stem through `String.capitalize()` and a test that guesses what that does to a
## file name is testing the engine.
const SHIPPED: Array[String] = ["Canvas Scumble", "Canvas Weave", "Dot Screen", "Lit Grain", "Paper Grain"]


func after_each() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    var dir := DirAccess.open(scratch_dir)
    for file in dir.get_files():
        dir.remove(file)
    DirAccess.remove_absolute(scratch_dir)


## A greyscale PNG of four texels, white through black, which is the shape of an
## imported GIMP pattern: a picture with no colour in it.
func _write_png() -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
    image.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
    image.set_pixel(1, 0, Color(0.0, 0.0, 0.0, 1.0))
    image.set_pixel(0, 1, Color(0.5, 0.5, 0.5, 1.0))
    image.set_pixel(1, 1, Color(0.25, 0.25, 0.25, 1.0))
    image.save_png(scratch_dir.path_join(PNG_NAME))


func _chooser() -> SaPatternChooser:
    _write_png()
    return SaPatternChooser.new(SaPatternStore.new([SaPatternStore.SHIPPED_DIR, scratch_dir]), 48)


## The name the store gave the written PNG.
func _loaded_name(chooser: SaPatternChooser) -> String:
    for pattern_name in chooser.visible_names():
        if not SHIPPED.has(pattern_name):
            return pattern_name
    return ""


## The tile *pattern_name*'s cell is drawing, as an image, or null when the cell
## has no icon. Walked out of the tree rather than read off the chooser's cells,
## because what the painter sees is the icon on the button.
func _tile(chooser: SaPatternChooser, pattern_name: String) -> Image:
    for box in chooser.find_children("*", "VBoxContainer", true, false):
        var label := box.get_node_or_null("Name") as Label
        if label == null or label.text != pattern_name:
            continue
        for child in box.get_children():
            var button := child as Button
            if button != null and button.icon != null:
                return button.icon.get_image()
    return null


## The regression. A loaded picture's tile has no colour in it, which is what a
## one-channel `FORMAT_RF` texture drawn by the engine could never say.
func test_a_loaded_patterns_tile_is_grey() -> void:
    var chooser := _chooser()
    var tile := _tile(chooser, _loaded_name(chooser))
    assert_not_null(tile, "the written pattern has a tile at all")
    if tile == null:
        chooser.free()
        return
    var coloured := 0
    for y in tile.get_height():
        for x in tile.get_width():
            var texel := tile.get_pixel(x, y)
            if absf(texel.r - texel.g) > 1.0 / 255.0 or absf(texel.r - texel.b) > 1.0 / 255.0:
                coloured += 1
    assert_eq(coloured, 0, "no texel of it has a channel out of step with the others")
    chooser.free()


## The other half, and the half that was already right, so a fix that moved the
## convert to the wrong side of the fork fails here rather than on screen.
func test_a_generated_patterns_tile_is_grey_too() -> void:
    var chooser := _chooser()
    var tile := _tile(chooser, GENERATED)
    assert_not_null(tile, "the shipped kernel has a tile")
    if tile == null:
        chooser.free()
        return
    var coloured := 0
    for y in tile.get_height():
        for x in tile.get_width():
            var texel := tile.get_pixel(x, y)
            if absf(texel.r - texel.g) > 1.0 / 255.0 or absf(texel.r - texel.b) > 1.0 / 255.0:
                coloured += 1
    assert_eq(coloured, 0, "and it is grey as it always was")
    chooser.free()


## Both tiles are the same format, which is the sentence the fix is really about:
## one place makes a tile, so there is one kind of tile.
func test_the_two_loaders_answer_one_kind_of_tile() -> void:
    var chooser := _chooser()
    var loaded := _tile(chooser, _loaded_name(chooser))
    var generated := _tile(chooser, GENERATED)
    assert_not_null(loaded, "a loaded tile")
    assert_not_null(generated, "and a generated one")
    if loaded == null or generated == null:
        chooser.free()
        return
    assert_eq(loaded.get_format(), Image.FORMAT_L8, "the loaded one is the grey format")
    assert_eq(generated.get_format(), Image.FORMAT_L8, "and so is the generated one")
    chooser.free()


## The tile still carries the pattern rather than a flat field, so a convert that
## threw the values away would fail here. The PNG's four texels are white, black,
## a half and a quarter, and the tile is those scaled up.
func test_the_grey_tile_still_carries_the_pattern() -> void:
    var chooser := _chooser()
    var tile := _tile(chooser, _loaded_name(chooser))
    assert_not_null(tile, "a tile to read")
    if tile == null:
        chooser.free()
        return
    var low := 1.0
    var high := 0.0
    for y in tile.get_height():
        for x in tile.get_width():
            var value := tile.get_pixel(x, y).r
            low = minf(low, value)
            high = maxf(high, value)
    assert_true(high - low > 0.5, "the tile runs from dark to light, %.3f to %.3f" % [low, high])
    chooser.free()
