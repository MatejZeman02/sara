## The dockers grow with their text: what a docker does when the Font size
## preference moves.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A docker grows on a font change within three limits: never below what the
## painter left, only as far as its content asks, and inside its host. What the
## content asks is two floors, the column's own minimum and the width that shows
## whole every name the change cut, and floors because the layout store's fit
## after the bar's resize keeps a docker's `min_size` and nothing else. A name
## counts when it read whole at the old size in the old layout, so one too long
## for any docker never widens one.
##
## Beside the layout store, because `ui/dockers` stands at its 2500 lines and
## the file map's top page has no room for a folder, `docker_pin.gd`'s reason.
class_name SaDockerFontGrowth
extends RefCounted

## The rectangle a font change started from and the one it left, kept on the
## window the way `SaDockerMaximise` keeps its own.
const BEFORE_META := &"sa_font_growth_before"
const GROWN_META := &"sa_font_growth_grown"

## The width the names the font cut need, the second floor.
const FLOOR_META := &"sa_font_growth_floor"

## The Font size preference the docker was last laid out at, 100 % before any
## change has reached it.
const FONT_META := &"sa_font_growth_font_scale"

## Which change a pending growth belongs to, so a second change leaves only its
## own rounds running.
const PASS_META := &"sa_font_growth_pass"

## Frames a docker lays out in before it is measured. A container sorts on a
## deferred call, so one frame reads half a layout.
const SETTLE_FRAMES: int = 2

## Rounds per change. A name sharing its row with another expanding control
## gets only part of each widening.
const ROUNDS: int = 5


## Follows one font change for *docker*: [method begin] at once, the rounds
## once the new size has laid out, then [method end]. Called after the theme
## pass and before any frame. The suite drives the three by hand.
static func follow(docker: DockerWindow) -> void:
    if not docker.is_inside_tree():
        return
    var pass_id := int(docker.get_meta(PASS_META, 0)) + 1
    docker.set_meta(PASS_META, pass_id)
    _grow_when_laid_out(docker, pass_id, begin(docker))


## Before any frame: reads which names are whole in the layout the old size
## left, gives back what the last change grew, and keeps the rectangle this one
## starts from. Answers the names.
static func begin(docker: DockerWindow) -> Dictionary:
    var was_at := float(docker.get_meta(FONT_META, 1.0))
    docker.set_meta(FONT_META, SaUI.user_font_scale)
    var counted := whole_names(docker, was_at)
    give_back(docker)
    docker.set_meta(BEFORE_META, Rect2i(docker.position, docker.size))
    return counted


## Keeps what the change left as what it grew, whatever grew it, since the
## column's own floor and the store's fit widen a docker between the rounds too.
static func end(docker: DockerWindow) -> void:
    docker.set_meta(GROWN_META, Rect2i(docker.position, docker.size))


## Every name in *window* that reads whole at the preference *font_scale* in the
## width it has now, as a set of the names. Each is measured at the size its
## control drew at *font_scale*, rounded, because a control draws at whole
## pixels. Names rather than controls, because Tool Options builds its rows
## again when a setting moves.
static func whole_names(window: Window, font_scale: float) -> Dictionary:
    var out: Dictionary = {}
    var factor := font_scale / maxf(SaUI.user_font_scale, 0.01)
    for entry: Dictionary in _names(window, false):
        var control: Control = entry["control"]
        var then := maxi(1, roundi(_font_px(control) * factor))
        if float(entry["frame"]) + _text_width(control, entry["text"], then) <= control.size.x + 0.5:
            out[entry["text"]] = true
    return out


## Puts *docker* back at the size it had before the last change, in each axis
## that still has the size the change left, and forgets the change. An axis at
## a time, because the store's fit gives a docker a height of its own. The
## floor goes back to what the docker declared, or a larger size's would hold it
## wide through the store's fit.
static func give_back(docker: DockerWindow) -> void:
    if SaDockerMaximise.is_maximised(docker):
        return
    var before: Rect2i = docker.get_meta(BEFORE_META, Rect2i())
    var grown: Rect2i = docker.get_meta(GROWN_META, Rect2i())
    for meta: StringName in [BEFORE_META, GROWN_META, FLOOR_META]:
        docker.remove_meta(meta)
    docker.min_size = SaUI.window_size_for(docker, docker.logical_min_size)
    if before.size == Vector2i():
        return
    var back := docker.size
    if docker.size.x == grown.size.x:
        back.x = before.size.x
        if docker.position.x == grown.position.x:
            docker.position = Vector2i(before.position.x, docker.position.y)
    if docker.size.y == grown.size.y:
        back.y = before.size.y
    docker.size = back


## One round on a settled layout: grows *docker* for the names in *counted* cut
## now and floors it at its column. Answers whether anything moved.
##
## *progress* carries the last round's shortfall and widening. A name given a
## share of each widening, Layers' blend mode list half, is next asked the
## shortfall over that share. A widening that reached nothing stops the rounds.
static func step(docker: DockerWindow, counted: Dictionary, progress: Dictionary) -> bool:
    var short := widest_cut(docker, counted)
    var asked := short
    var last := int(progress.get("short", -1))
    var widened := int(progress.get("widened", 0))
    if short > 0 and last >= 0:
        var reached := last - short
        asked = 0 if reached <= 0 or widened <= 0 else int(ceil(float(short) * float(widened) / float(reached)))
    var was := docker.size.x
    var moved := grow(docker, asked)
    progress["short"] = short
    progress["widened"] = docker.size.x - was
    return moved


## Floors *docker* at its column and *short* wider for the names the font cut,
## grows it to the floor inside its host, and answers whether it moved. The
## widening stops at the width before the change times the font size over 100 %.
static func grow(docker: DockerWindow, short: int) -> bool:
    if SaDockerMaximise.is_maximised(docker):
        return false
    var reserved := 0
    if docker.resizer != null and docker.resizer.visible:
        reserved = int(docker.resizer.custom_minimum_size.y)
    var declared := SaUI.window_size_for(docker, docker.logical_min_size)
    var floor_size := Vector2i(maxi(declared.x, DockerWindow.column_min_width(docker)), declared.y + reserved)
    # The rule `grow_to_content` keeps: a docker that cannot scroll cannot crop,
    # so its content is its floor, up to the share of the screen it opens at.
    if not DockerWindow.column_has_scroll(docker):
        var content := DockerWindow.column_content_height(docker) + reserved
        floor_size.y = maxi(floor_size.y, mini(content, DockerWindow.content_height_cap(docker)))
    var base: Rect2i = docker.get_meta(BEFORE_META, Rect2i(docker.position, docker.size))
    var ratio := maxf(float(SaUI.get_font_size()) / float(SaUI.BASE_FONT_SIZE), 1.0)
    if short > 0:
        docker.set_meta(FLOOR_META, mini(docker.size.x + short, maxi(int(ceil(base.size.x * ratio)), docker.size.x)))
    floor_size.x = maxi(floor_size.x, int(docker.get_meta(FLOOR_META, 0)))
    var wanted := Vector2i(
        maxi(docker.size.x, floor_size.x),
        maxi(docker.size.y, maxi(floor_size.y, DockerWindow.column_min_height(docker) + reserved))
    )
    var host := host_rect(docker)
    var at := docker.position
    if host.size.x > 0 and host.size.y > 0:
        # Never past the host, and never smaller than the docker already is: a
        # docker the painter made larger than its host is theirs.
        wanted = Vector2i(
            maxi(docker.size.x, mini(wanted.x, host.size.x)), maxi(docker.size.y, mini(wanted.y, host.end.y - at.y))
        )
        at.x = clampi(at.x, host.position.x, maxi(host.end.x - wanted.x, host.position.x))
    var moved := wanted != docker.size or at != docker.position
    docker.min_size = Vector2i(mini(floor_size.x, wanted.x), mini(floor_size.y, wanted.y))
    if not moved:
        return false
    docker.position = at
    docker.size = wanted
    docker.set_meta(GROWN_META, Rect2i(docker.position, docker.size))
    return true


static func _grow_when_laid_out(docker: DockerWindow, pass_id: int, counted: Dictionary) -> void:
    var tree := docker.get_tree()
    var progress: Dictionary = {}
    for _round in ROUNDS:
        for _frame in SETTLE_FRAMES:
            await tree.process_frame
            if not is_instance_valid(docker) or not docker.is_inside_tree():
                return
            if int(docker.get_meta(PASS_META, 0)) != pass_id:
                return
        if not step(docker, counted, progress):
            break
    end(docker)


## The space *docker* has to be inside, its host viewport above the status line
## when embedded and its screen's usable part when not, in the units its `position` is in.
static func host_rect(docker: Window) -> Rect2i:
    if docker.is_embedded():
        var line := SaDockerLayoutRefit.status_rows_in(SaUI.window_scale(docker))
        return Rect2i(Vector2i.ZERO, DockerDragHandle.host_size_of(docker) - Vector2i(0, line))
    return DisplayServer.screen_get_usable_rect(docker.current_screen)


## How much wider *docker* has to be for every name in *counted* to read whole,
## and 0 when none is cut.
static func widest_cut(docker: Window, counted: Dictionary) -> int:
    var widest := 0.0
    for word: Dictionary in cut_words(docker):
        if counted.has(word["text"]):
            widest = maxf(widest, float(word["whole"]) - float(word["has"]))
    return int(ceil(widest))


## Every name *window* shows cut, as `{"text", "has", "whole"}`: the name, its
## control's width and the width that shows it whole. The state dump's docker
## grips carry it, which says which docker a shot's "Backgro…" is in.
static func cut_words(window: Window) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry: Dictionary in _names(window, true):
        var control: Control = entry["control"]
        var whole := float(entry["frame"]) + _text_width(control, entry["text"])
        if whole > control.size.x + 0.5:
            out.append({"text": entry["text"], "has": control.size.x, "whole": whole})
    return out


## Every label and button in *window* that can cut its name, as `{"control",
## "frame", "text"}`, the frame being its width without the text.
##
## One that trims or clips and does not wrap leaves its text out of its minimum.
## Measured on Godot 4.7, a button's is its frame, icon and gap, and a label's
## one unit and its frame. A wrapping label moves its name to a second line
## rather than losing letters, and a list that fits its longest item holds that
## item in its minimum, so neither cuts.
static func _names(window: Window, visible_only: bool) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for node: Node in window.find_children("*", "Control", true, false):
        var control := node as Control
        if visible_only and not control.is_visible_in_tree():
            continue
        var label := control as Label
        var button := control as Button
        var list := control as OptionButton
        var frame := -1.0
        var text := ""
        if label != null and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
            if label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
                frame = label.get_minimum_size().x - 1.0
                text = label.text
        elif button != null and button.autowrap_mode == TextServer.AUTOWRAP_OFF:
            if button.clip_text or button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
                frame = -1.0 if list != null and list.fit_to_longest_item else button.get_minimum_size().x
                text = button.text
        if frame >= 0.0 and not text.is_empty():
            out.append({"control": control, "frame": frame, "text": text})
    return out


## *text* in the font *control* draws it in, at *px* or at the size it draws at
## now.
static func _text_width(control: Control, text: String, px: int = 0) -> float:
    var font := control.get_theme_font(&"font")
    var label := control as Label
    if label != null and label.label_settings != null and label.label_settings.font != null:
        font = label.label_settings.font
    if font == null:
        return 0.0
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px if px > 0 else _font_px(control)).x


static func _font_px(control: Control) -> int:
    var label := control as Label
    if label != null and label.label_settings != null:
        return label.label_settings.font_size
    return control.get_theme_font_size(&"font_size")
