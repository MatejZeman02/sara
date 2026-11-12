## An `.abr` reader lists a Photoshop collection's tips.
##
## Every collection here is one `abr_writer.gd` writes, the three under
## `fixtures/` among them. A version 2 and a version 6 file of three pictures
## each, one packed, are read for every tip's name, size and texels as written.
## A file cut short and a version Sara does not know each refuse with a
## sentence naming the file, and a computed brush is listed as refused.
extends "res://tests/test_framework.gd"

const AbrWriter = preload("res://core/api/abr/tests/abr_writer.gd")


func _fixture(name: String) -> SaAbrCollection:
    return SaAbrCollection.load_from(AbrWriter.FIXTURE_DIR.path_join(name))


## Every texel of *tip* against what *picture* wrote, the first that differs
## named, and the size and name beside them.
func _assert_as_written(tip: SaTipImage.Tip, picture: AbrWriter.Picture) -> void:
    assert_true(tip.ok(), "%s loaded, read error '%s'" % [picture.name, tip.error])
    assert_eq(tip.tip_name, picture.name, "The tip carries the name written")
    assert_eq(tip.size, picture.size, "%s is the size written" % picture.name)
    var count := picture.size.x * picture.size.y
    assert_eq(tip.mask.size(), count, "%s has a texel per pixel" % picture.name)
    assert_eq(tip.lightness.size(), count, "and a lightness per pixel")
    var differs := -1
    for i in mini(count, tip.mask.size()):
        if absf(tip.mask[i] - picture.coverage(i)) > 1e-6:
            differs = i
            break
    var shown := (
        "texel %d reads %f where %f was written" % [differs, tip.mask[differs], picture.coverage(differs)] if differs >= 0 else ""
    )
    assert_eq(differs, -1, "%s reads every texel as written, %s" % [picture.name, shown])
    assert_almost_eq(tip.spacing, picture.spacing / 100.0, 1e-6, "%s keeps its spacing" % picture.name)
    assert_false(tip.colourful, "A collection's tip is a grey mask")
    assert_almost_eq(tip.lightness_at(0, 0), SaTipImage.NEUTRAL_LIGHTNESS, 1e-6, "with the neutral lightness")


func test_the_fixtures_on_disk_are_the_ones_the_writer_writes() -> void:
    var files := AbrWriter.fixtures()
    for name in files:
        var held := FileAccess.get_file_as_bytes(AbrWriter.FIXTURE_DIR.path_join(name))
        assert_eq(held, files[name], "%s is what abr_writer.gd writes. Write it again with write_abr_fixtures.gd" % name)


func test_a_version_2_file_lists_its_three_tips_as_written() -> void:
    var collection := _fixture(AbrWriter.V2_NAME)
    assert_true(collection.ok(), "The version 2 fixture reads, read error '%s'" % collection.error)
    assert_eq(collection.version, 2, "and says version 2")
    var pictures := AbrWriter.v2_pictures()
    assert_eq(collection.tips.size(), 3, "Three tips are listed")
    assert_true(pictures[1].packed, "The second tip of the fixture is packed")
    for i in mini(collection.tips.size(), pictures.size()):
        _assert_as_written(collection.tips[i], pictures[i])


func test_a_version_6_file_lists_its_three_tips_by_the_descriptor_s_names() -> void:
    var collection := _fixture(AbrWriter.V6_NAME)
    assert_true(collection.ok(), "The version 6 fixture reads, read error '%s'" % collection.error)
    assert_eq([collection.version, collection.subversion], [6, 2], "and says version 6, subversion 2")
    var pictures := AbrWriter.v6_pictures()
    assert_eq(collection.tips.size(), 3, "Three tips are listed")
    assert_true(pictures[1].packed, "The second tip of the fixture is packed")
    assert_eq(pictures[2].depth, 16, "and the third is sixteen bits a texel")
    for i in mini(collection.tips.size(), pictures.size()):
        _assert_as_written(collection.tips[i], pictures[i])
    assert_eq(collection.pictures().size(), 3, "and all three can be painted")


func test_a_computed_brush_is_listed_as_refused_and_the_picture_beside_it_loads() -> void:
    var collection := _fixture(AbrWriter.V1_NAME)
    assert_true(collection.ok(), "The version 1 fixture reads, read error '%s'" % collection.error)
    assert_eq(collection.tips.size(), 2, "Both brushes are listed")
    var computed := collection.tips[0]
    assert_false(computed.ok(), "The computed brush does not load as a picture")
    assert_eq(computed.tip_name, "a-computed-brush-and-a-picture-v1 1", "and keeps a name, the file's and its place")
    assert_true(computed.error.contains("computed brush"), "Its sentence says what it is, read '%s'" % computed.error)
    assert_true(computed.error.contains(computed.tip_name), "and names it, read '%s'" % computed.error)
    assert_true(computed.error.contains("pictures only"), "and why it is not loaded, read '%s'" % computed.error)
    var sentence := (
        "a-computed-brush-and-a-picture-v1 1 is a computed brush, a shape Photoshop draws from a diameter"
        + " and a hardness rather than a picture, and Sara loads pictures only."
    )
    assert_eq(computed.error, sentence, "The whole sentence")
    assert_true(computed.mask.is_empty(), "with no picture behind it")
    var picture := AbrWriter.Picture.new(
        "a-computed-brush-and-a-picture-v1 2", Vector2i(8, 8), 8, false, AbrWriter.checker(8, 8), 30
    )
    _assert_as_written(collection.tips[1], picture)
    assert_eq(collection.pictures().size(), 1, "One brush of the two can be painted")


func test_a_computed_preset_in_a_version_6_descriptor_is_listed_as_refused() -> void:
    var bytes := AbrWriter.sectioned(6, 2, AbrWriter.v6_pictures(), true, PackedStringArray(["Hard Round 30"]))
    var collection := SaAbrCollection.read(bytes, "rounds.abr")
    assert_true(collection.ok(), "It reads, read error '%s'" % collection.error)
    assert_eq(collection.tips.size(), 4, "The three pictures and the computed preset are listed")
    var computed := collection.tips[3]
    assert_eq(computed.tip_name, "Hard Round 30", "by the descriptor's name")
    assert_true(computed.error.contains("computed brush"), "as refused, read '%s'" % computed.error)


func test_a_file_cut_short_refuses_with_a_sentence_naming_it() -> void:
    var whole := AbrWriter.v6_fixture()
    var cut := SaAbrCollection.read(whole.slice(0, 800), "cut.abr")
    assert_false(cut.ok(), "A version 6 file cut inside its second picture refuses")
    assert_true(cut.error.contains("cut.abr"), "naming the file, read '%s'" % cut.error)
    assert_true(cut.error.contains("cut short"), "and saying it is cut short, read '%s'" % cut.error)
    assert_true(cut.error.contains("800"), "where it ends, read '%s'" % cut.error)
    assert_true(cut.tips.is_empty(), "and lists nothing")
    assert_eq(
        cut.error, "cut.abr is cut short: its samp section runs to byte 1628 and the file ends at byte 800.", "The whole sentence"
    )

    var old := SaAbrCollection.read(AbrWriter.v2_fixture().slice(0, 120), "old-cut.abr")
    assert_false(old.ok(), "A version 2 file cut inside its second brush refuses")
    assert_true(old.error.contains("old-cut.abr") and old.error.contains("cut short"), "the same way, read '%s'" % old.error)
    assert_true(old.error.contains("brush 2"), "naming the brush it stopped in, read '%s'" % old.error)
    assert_eq(
        old.error, "old-cut.abr is cut short: its brush 2 runs to byte 178 and the file ends at byte 120.", "The whole sentence"
    )

    var stub := SaAbrCollection.read(PackedByteArray([0, 6]), "stub.abr")
    assert_true(stub.error.contains("stub.abr") and stub.error.contains("too short"), "Two bytes refuse, read '%s'" % stub.error)


func test_an_unknown_version_refuses_with_a_sentence_naming_it() -> void:
    var bytes := AbrWriter.v2_fixture()
    bytes[1] = 3
    var unknown := SaAbrCollection.read(bytes, "odd.abr")
    assert_false(unknown.ok(), "Version 3 refuses")
    assert_true(unknown.error.contains("odd.abr"), "naming the file, read '%s'" % unknown.error)
    assert_true(unknown.error.contains("version 3"), "and its version, read '%s'" % unknown.error)
    assert_true(unknown.error.contains("1, 2, 6, 7 and 10"), "and the ones Sara reads, read '%s'" % unknown.error)
    assert_eq(unknown.error, "odd.abr is ABR version 3, and Sara reads versions 1, 2, 6, 7 and 10.", "The whole sentence")

    var later := AbrWriter.v6_fixture()
    later[3] = 3
    var sub := SaAbrCollection.read(later, "later.abr")
    assert_false(sub.ok(), "Version 6 with subversion 3 refuses")
    assert_true(sub.error.contains("later.abr") and sub.error.contains("subversion 3"), "by name, read '%s'" % sub.error)
    assert_eq(
        sub.error, "later.abr is ABR version 6 with subversion 3, and Sara reads subversions 1 and 2.", "The whole sentence"
    )


func test_subversion_1_and_version_10_read_alike() -> void:
    var pictures := AbrWriter.v6_pictures()
    for layout: Array in [[6, 1], [7, 2], [10, 1]]:
        var collection := SaAbrCollection.read(AbrWriter.sectioned(layout[0], layout[1], pictures, true), "x.abr")
        assert_true(collection.ok(), "Version %d.%d reads, read error '%s'" % [layout[0], layout[1], collection.error])
        assert_eq(collection.tips.size(), 3, "Version %d.%d lists three tips" % [layout[0], layout[1]])
        for i in mini(collection.tips.size(), 3):
            _assert_as_written(collection.tips[i], pictures[i])


func test_a_version_6_file_without_a_descriptor_names_its_pictures_after_the_file() -> void:
    var collection := SaAbrCollection.read(AbrWriter.sectioned(6, 2, AbrWriter.v6_pictures(), false), "plain.abr")
    assert_true(collection.ok(), "It reads, read error '%s'" % collection.error)
    var names := []
    for tip in collection.tips:
        names.append(tip.tip_name)
    assert_eq(names, ["plain 1", "plain 2", "plain 3"], "Each picture is named after the file and its place")
    assert_almost_eq(collection.tips[0].spacing, SaTipImage.SPACING_WHEN_UNSTATED, 1e-6, "at the default spacing")


func test_a_descriptor_the_walk_cannot_read_costs_the_names_and_not_the_pictures() -> void:
    var bytes := AbrWriter.v6_fixture()
    var desc := _find(bytes, "8BIMdesc".to_ascii_buffer())
    assert_true(desc > 0, "The fixture has a desc section")
    # The list's type, `VlLs`, made a reference, a type the walk gives up on.
    var list := _find(bytes, "VlLs".to_ascii_buffer())
    bytes[list] = "o".unicode_at(0)
    bytes[list + 1] = "b".unicode_at(0)
    bytes[list + 2] = "j".unicode_at(0)
    bytes[list + 3] = " ".unicode_at(0)
    var collection := SaAbrCollection.read(bytes, "odd-desc.abr")
    assert_true(collection.ok(), "It still reads, read error '%s'" % collection.error)
    assert_eq(collection.pictures().size(), 3, "with its three pictures")
    assert_eq(collection.tips[1].tip_name, "odd-desc 2", "named after the file")


func test_a_hand_packed_row_unpacks_as_packbits_says() -> void:
    # Written by hand rather than by the writer, so the format is pinned by
    # something other than the code under test's twin: four of 0x80 as a run,
    # a no-op, then two literals.
    var row := PackedByteArray([0xFD, 0x80, 0x80, 0x01, 0x10, 0x20])
    var body := AbrWriter.u32(0) + AbrWriter.u16(25)
    body.append(1)
    body.append_array(AbrWriter.u16(0) + AbrWriter.u16(0) + AbrWriter.u16(1) + AbrWriter.u16(6))
    body.append_array(AbrWriter.u32(0) + AbrWriter.u32(0) + AbrWriter.u32(1) + AbrWriter.u32(6))
    body.append_array(AbrWriter.u16(8))
    body.append(1)
    body.append_array(AbrWriter.u16(row.size()) + row)
    var bytes := AbrWriter.u16(1) + AbrWriter.u16(1) + AbrWriter.u16(2) + AbrWriter.u32(body.size()) + body
    var collection := SaAbrCollection.read(bytes, "hand.abr")
    assert_true(collection.ok() and collection.tips.size() == 1, "It reads, read error '%s'" % collection.error)
    var tip := collection.tips[0]
    assert_true(tip.ok(), "The packed tip loads, read '%s'" % tip.error)
    var read := []
    for x in tip.size.x:
        read.append(roundi(tip.at(x, 0) * 255.0))
    assert_eq(read, [128, 128, 128, 128, 16, 32], "The row unpacks to four runs of 128 and two literals")


func test_a_packed_row_that_does_not_unpack_to_its_width_is_refused_and_the_rest_listed() -> void:
    var pictures := AbrWriter.v2_pictures()
    var bytes := AbrWriter.old_layout(2, pictures)
    # The second picture's first packed row: its header byte, a run of 255,
    # made a run one longer than the row.
    var name_at := _find(bytes, AbrWriter.utf16("Wide Flat"))
    var first_row := name_at + AbrWriter.utf16("Wide Flat").size() + 1 + 8 + 16 + 2 + 1 + 2 * 4
    assert_eq(bytes[first_row], 257 - 5, "The fixture's packed row starts with a run of five")
    bytes[first_row] = 257 - 6
    var collection := SaAbrCollection.read(bytes, "bad-row.abr")
    assert_true(collection.ok(), "The file reads, read error '%s'" % collection.error)
    assert_eq(collection.tips.size(), 3, "and lists all three")
    var bad := collection.tips[1]
    assert_false(bad.ok(), "The broken tip is refused")
    assert_true(bad.error.contains("Wide Flat") and bad.error.contains("packed"), "by name, read '%s'" % bad.error)
    assert_true(collection.tips[0].ok() and collection.tips[2].ok(), "and the two beside it load")


## Where *needle* first starts in *haystack*, or -1.
func _find(haystack: PackedByteArray, needle: PackedByteArray) -> int:
    for at in haystack.size() - needle.size() + 1:
        if haystack.slice(at, at + needle.size()) == needle:
            return at
    return -1
