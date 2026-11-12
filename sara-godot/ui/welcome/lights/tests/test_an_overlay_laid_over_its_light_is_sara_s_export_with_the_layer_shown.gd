## An overlay of the Welcome picture laid over its light gives back Sara's own
## export of that light with the layer shown, so an opening with the stars or a
## flock drawn is the shipped painting and not a sticker on it.
##
## `scripts/export_welcome_lights.py` exported summer's dusk, the light with the
## stars, every flock and the screen layers that make the solve hardest, with
## each layer shown, and kept each export cut to its overlay's box in
## `exports/` beside a `.gdignore`, with the boxes in `boxes.json`. This lays the
## shipped overlay over the shipped dusk the way the band's texture over a
## texture does, in the eight bit sRGB the pictures are, at full opacity, and
## reads every texel of the box against the export.
##
## The stars are laid under the clouds, which drift over them, so
## their over is the dusk composed from its parts with no drift and the stars
## drawn whole beneath the clouds, read outside the band where the clouds'
## strip fades into itself, since there the clouds are not the frame's by
## design (`test_...`).
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"
const EXPORTS := "res://ui/welcome/lights/tests/exports/"

## The most a texel of the over may differ from the export, in levels of 255
## on any channel: the rounding of the overlay's colour and alpha to eight bits
## each, half a level apiece, and a level for the over's own rounding.
const TOLERANCE: float = 2.0 / 255.0

## The same for the stars, which pass through the three parts' blends as well
## and, under a thin cloud, through the dusk's gradient map, which grades a
## mixed texel otherwise than its parts: 71 texels of the 24,192 read come to
## 3 to 6 levels. `test_...` holds a composed light to 8.
const STARS_TOLERANCE: float = 8.0 / 255.0


func _image(path: String) -> Image:
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    image.convert(Image.FORMAT_RGBAF)
    return image


func test_each_overlay_over_the_dusk_is_the_dusk_exported_with_its_layer_shown() -> void:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPORTS + "boxes.json"))
    assert_true(said is Dictionary, "the boxes are read")
    var light := "%s-%s" % [said["season"], said["light"]]
    var under := _image("%s0.18-%s.png" % [SHIPPED, light])
    var boxes: Dictionary = said["boxes"]
    assert_eq(boxes.keys().size(), 4, "the stars and three flocks")
    for stem: String in boxes:
        var box: Array = boxes[stem]
        var over := _image("%s0.18-%s-%s.png" % [SHIPPED, light, stem])
        var shown := _image("%s%s-%s-shown.png" % [EXPORTS, stem, said["light"]])
        assert_eq(shown.get_size(), Vector2i(int(box[2]), int(box[3])), "%s's export is its box" % stem)
        var parts: PictureParts = null
        var composed: Image = null
        if stem == "stars":
            var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
            parts = PictureParts.listed_in(sidecar, SHIPPED)["0.18-%s.png" % light]
            var drawn := PictureOverlays.Overlay.new("%s0.18-%s-%s.png" % [SHIPPED, light, stem], 1.0)
            drawn.roll(0.0, 1.0)
            composed = parts.compose_from_sources(0.0, [drawn])
            composed.convert(Image.FORMAT_RGBAF)
        var worst := 0.0
        var covered := 0
        for y in int(box[3]):
            for x in int(box[2]):
                var at := Vector2i(int(box[0]) + x, int(box[1]) + y)
                var top := over.get_pixelv(at)
                var laid := under.get_pixelv(at).lerp(top, top.a)
                if composed != null:
                    var from_seam := posmod(at.x - parts.origin, composed.get_width())
                    if mini(from_seam, composed.get_width() - from_seam) <= parts.seam:
                        continue
                    laid = composed.get_pixelv(at)
                var wanted := shown.get_pixel(x, y)
                worst = maxf(worst, maxf(absf(laid.r - wanted.r), maxf(absf(laid.g - wanted.g), absf(laid.b - wanted.b))))
                if top.a > 0.0:
                    covered += 1
        assert_true(covered > 0, "%s covers something of its box" % stem)
        var within := STARS_TOLERANCE if composed != null else TOLERANCE
        assert_true(
            worst <= within,
            "%s over the %s is its export within %.0f levels: %.1f" % [stem, light, within * 255.0, worst * 255.0]
        )


func test_an_overlay_is_naught_outside_its_box() -> void:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPORTS + "boxes.json"))
    var light := "%s-%s" % [said["season"], said["light"]]
    for stem: String in said["boxes"]:
        var box: Array = said["boxes"][stem]
        var over := _image("%s0.18-%s-%s.png" % [SHIPPED, light, stem])
        var used := over.get_used_rect()
        assert_eq(used, Rect2i(int(box[0]), int(box[1]), int(box[2]), int(box[3])), "%s draws nothing past its box" % stem)
