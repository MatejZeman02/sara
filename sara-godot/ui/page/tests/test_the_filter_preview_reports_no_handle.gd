## The filter preview's report carries no device handle.
##
## `SaFilterPreview.describe` wrote the bound texture's RID into every dump taken
## with a filter dialog open. An RID's id is a handle the device hands out, a
## different number in every process, so two runs of one scenario never agreed on
## it, and a comparison through the door differed on that key and
## nothing else. Two previews in one suite, shown the same sequence of fresh
## textures, stand in for the two runs: their textures are different handles just
## as the two processes' were.
##
## Windowless, the way `test_filter_dialog.gd` holds a dialog. A texture needs a
## device.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func _declare(ui: SaDialog) -> void:
    ui.title("Preview")
    ui.preview()
    ui.apply_cancel()


func _texture() -> SaTexture:
    return SaTexture.new(Vector2i(8, 8), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)


## The report of a fresh preview shown *textures* in order.
func _preview_after(textures: Array) -> Dictionary:
    var host := VBoxContainer.new()
    var dialog := SaDialog.new(_declare)
    dialog.declare_rows()
    dialog.realize(host)
    for texture: SaTexture in textures:
        dialog.show_texture(texture, Rect2i(0, 0, 8, 8))
    var described: Dictionary = dialog.preview_control.describe()
    host.free()
    return described


func test_two_previews_of_the_same_story_report_alike() -> void:
    var first := _preview_after([_texture(), _texture()])
    var second := _preview_after([_texture(), _texture()])
    # The two textures in each list are fresh handles, just as two processes' are.
    assert_eq(first, second, "Two previews shown the same fresh textures report alike")


func test_the_report_says_a_texture_is_held_and_how_often_it_changed() -> void:
    var again := _texture()
    var described := _preview_after([again, again, _texture()])
    assert_true(bool(described["holds_texture"]), "A preview shown a texture holds one")
    assert_eq(int(described["textures_bound"]), 2, "the same texture shown twice binds once, and a second texture binds again")
    assert_eq(int(described["shows"]), 3, "while every show is counted")
    assert_false(described.has("texture_rid"), "and no key carries the device's handle")


func test_a_preview_shown_nothing_holds_nothing() -> void:
    var described := _preview_after([])
    assert_false(bool(described["holds_texture"]), "A fresh preview holds no texture")
    assert_eq(int(described["textures_bound"]), 0, "and has bound none")
