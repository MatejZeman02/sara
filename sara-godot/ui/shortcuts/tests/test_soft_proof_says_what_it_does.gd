## Soft Proof offers a target and shows its effect.
##
## Once on, nothing in the picture changed and there was nothing to choose, so
## a painter could not tell whether it worked.
## A new document is sRGB and the proof gamut defaults to sRGB, so the proof
## clipped nothing and said nothing about why. The proof now says when the
## document's gamut fits inside the proof's, through `SaGamut.contains`, from
## Ctrl+Y and from the View menu's row alike, and the Minimap's proof row
## carries the gamut beside the mode while a soft proof is on.
extends "res://tests/test_framework.gd"

var _registries: SaRegistries = null
## Held, because a Callable does not keep its object alive, and a command whose
## handler's object was freed does nothing.
var _commands: SaShortcutCommands = null
var _host: Node = null
var _embedded: bool = false
var _settings_before: Dictionary = {}
var _pending_before := PackedStringArray()
var _refusals_before := PackedStringArray()


func before_each() -> void:
    _settings_before = {
        "proof_profile": SaSettings.proof_profile,
        "canvas_proof_mode": SaSettings.canvas_proof_mode,
        "minimap_proof_mode": SaSettings.minimap_proof_mode,
    }
    SaSettings.proof_profile = "srgb"
    SaSettings.canvas_proof_mode = "soft_proof"
    SaSettings.minimap_proof_mode = "soft_proof"


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        # Freeing the host takes the problem dialog with it, which uninstalls
        # the notice and lets go of the sink.
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
        SaProblems.pending = _pending_before
        SaProblems.pending_refusals = _refusals_before
    _host = null
    _commands = null
    _registries = null
    for key: String in _settings_before:
        SaSettings.set(key, _settings_before[key])


## The built-in view transforms with the skeleton's commands registered against
## them, and the corner notice installed the way the main window installs it,
## under a host the Minimap can join. What `SaProblems` was keeping is set aside
## first, because installing hands every kept line to the new dialog.
func _build() -> SaNotice:
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    _registries.register_builtins()
    _commands = SaShortcutCommands.new(Callable(), Callable(), Callable(), _registries.view_transforms)
    _commands.register_into(_registries.commands)
    _pending_before = SaProblems.pending
    _refusals_before = SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Node.new()
    _host.name = "S43ProofHost"
    EventBus.add_child(_host)
    SaMessage.install(_host)
    return SaMessage.notice_widget()


## The Minimap under the same host, with the registry the commands act on.
func _minimap() -> MinimapDocker:
    var docker := MinimapDocker.new()
    docker.view_transforms = _registries.view_transforms
    _host.add_child(docker)
    docker.show()
    var body := Theme.new()
    body.default_font = SaFonts.regular()
    body.default_font_size = SaUI.get_font_size()
    docker._control_node.theme = SaUI.shared_theme if SaUI.shared_theme != null else body
    return docker


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## What *button* needs to show *words* whole beside its arrow, the measure the
## mode's own suite holds it to.
func _needed(button: Button, words: String) -> float:
    var font := button.get_theme_font(&"font")
    var font_size := button.get_theme_font_size(&"font_size")
    var arrow := 0.0
    if button.icon != null:
        arrow = float(button.icon.get_width())
        var cap := button.get_theme_constant(&"icon_max_width")
        if cap > 0:
            arrow = minf(arrow, float(cap))
        arrow += float(button.get_theme_constant(&"h_separation"))
    var words_width := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    return words_width + arrow + button.get_theme_stylebox(&"normal").get_minimum_size().x


func test_a_gamut_contains_itself_and_the_narrower_ones() -> void:
    var srgb := SaGamut.srgb()
    var p3 := SaGamut.display_p3()
    var rec2020 := SaGamut.rec2020()
    assert_true(srgb.contains(SaGamut.srgb()), "sRGB holds itself, every primary on its own corner")
    assert_true(p3.contains(srgb), "Display P3 holds sRGB, their shared blue on the edge")
    assert_false(srgb.contains(p3), "sRGB does not hold Display P3")
    assert_true(rec2020.contains(srgb), "Rec. 2020 holds sRGB")
    assert_false(p3.contains(rec2020), "Display P3 does not hold Rec. 2020")
    assert_false(srgb.contains(null), "Nothing is not held")


## P3's red lies outside Rec. 2020's red to green edge by about a thousandth,
## which is the one pair a reader would guess wrong, so it is held here.
func test_rec_2020_does_not_quite_hold_display_p3() -> void:
    assert_false(SaGamut.rec2020().contains(SaGamut.display_p3()), "P3 reaches a sliver past Rec. 2020")
    assert_true(SaGamut.ap1().contains(SaGamut.rec2020()), "while ACES AP1 holds Rec. 2020")


func test_the_test_does_not_care_which_way_round_the_primaries_are_listed() -> void:
    var p3 := SaGamut.display_p3()
    var backwards := SaGamut.create(
        &"backwards", "Backwards P3", PackedVector2Array([p3.primaries[2], p3.primaries[1], p3.primaries[0]])
    )
    assert_true(backwards.contains(SaGamut.srgb()), "A clockwise triangle holds what the anticlockwise one holds")
    assert_false(backwards.contains(SaGamut.rec2020()), "and refuses what it refuses")


func test_a_proof_into_a_gamut_that_holds_the_document_says_nothing_is_clipped() -> void:
    var line := SaGamut.display_p3().proof_line("Soft Proof", SaGamut.display_p3(), SaSettings.DISPLAY_PROFILES)
    assert_true(line.begins_with("Soft Proof: Display P3 shown as Display P3"), "Both gamuts are named: %s" % line)
    assert_true(line.contains("nothing inside the document's gamut is clipped"), "and nothing clips: %s" % line)
    assert_true(line.contains("Pick a narrower proof gamut in Preferences > Canvas and colour."), "with where to go: %s" % line)


func test_an_srgb_document_is_told_no_narrower_gamut_is_offered() -> void:
    var line := SaGamut.srgb().proof_line("Soft Proof", SaGamut.srgb(), SaSettings.DISPLAY_PROFILES)
    assert_true(line.contains("nothing inside the document's gamut is clipped"), "Nothing clips: %s" % line)
    assert_false(line.contains("Pick a narrower"), "and no narrower gamut is promised: %s" % line)
    assert_true(line.contains("Preferences > Canvas and colour offers no narrower proof gamut."), "it says none is: %s" % line)


func test_a_wider_document_is_told_what_clips() -> void:
    var line := SaGamut.srgb().proof_line("Soft Proof", SaGamut.display_p3(), SaSettings.DISPLAY_PROFILES)
    assert_true(line.contains("colours outside sRGB / Rec. 709 are clipped"), "What clips is named: %s" % line)
    assert_false(line.contains("nothing"), "and nothing is not claimed: %s" % line)


func test_ctrl_y_on_a_default_document_says_nothing_is_clipped() -> void:
    var notice := _build()
    _registries.commands.execute(&"view_soft_proof")
    assert_eq(_registries.view_transforms.mode, &"soft_proof", "The chord puts the soft proof on")
    assert_true(notice.showing(), "and a line is up in the corner")
    assert_true(notice.label.text.contains("nothing inside the document's gamut is clipped"), notice.label.text)
    notice.label.text = ""
    _registries.commands.execute(&"view_soft_proof")
    assert_eq(notice.label.text, "Soft Proof off", "The second press says the proof is off")


func test_the_view_menus_row_says_the_same_line() -> void:
    var notice := _build()
    var bar := TopMenuBar.new()
    bar._ready()
    var menu: SaViewMenu = bar.menu("View")
    menu.view_transforms = _registries.view_transforms
    var rows := {}
    for item_id: int in menu._transform_ids:
        rows[menu._transform_ids[item_id]] = item_id
    assert_true(rows.has(&"soft_proof"), "The View menu has a Soft Proof row")
    if not rows.has(&"soft_proof"):
        bar.free()
        return
    # Read off the label rather than off a signal, because a line nobody can
    # see in the corner is the failure this guards.
    notice.label.text = ""
    menu.on_id_pressed(rows[&"soft_proof"])
    assert_eq(_registries.view_transforms.mode, &"soft_proof", "The row puts the soft proof on")
    assert_true(notice.showing(), "and a line is up in the corner")
    assert_true(notice.label.text.begins_with("Soft Proof: sRGB / Rec. 709 shown as sRGB / Rec. 709"), notice.label.text)
    assert_true(notice.label.text.contains("nothing inside the document's gamut is clipped"), notice.label.text)

    notice.label.text = ""
    menu.on_id_pressed(SaViewMenu.ID_NORMAL_VIEW)
    assert_eq(notice.label.text, "", "Leaving it from the menu adds nothing")
    menu.on_id_pressed(rows[&"lightness_check"])
    assert_eq(_registries.view_transforms.mode, &"lightness_check", "Another mode from the menu goes on")
    assert_eq(notice.label.text, "", "and keeps the silence it had")
    bar.free()


func test_the_minimaps_gamut_shows_beside_a_soft_proof_and_writes_the_setting() -> void:
    var notice := _build()
    var docker := _minimap()
    var gamut := docker.find_child("ProofGamut", true, false) as SaChoiceButton
    assert_not_null(gamut, "The proof row has a gamut choice")
    if gamut == null:
        return
    var row := gamut.get_parent() as Control
    var proof_row := docker.find_child("ProofRow", true, false)
    assert_eq(String(row.name), "GamutRow", "in a row of its own")
    assert_eq(row.get_parent(), proof_row.get_parent(), "beside the proof row")
    assert_eq(row.get_index(), proof_row.get_index() + 1, "and straight under it")
    assert_eq(
        gamut.choice_values(),
        ["srgb", "display_p3", "rec2020", SaSettingsValues.PROOF_PROFILE_FILE, SaColorSpaceRow.ASK_ID],
        "offering the three RGB gamuts, the proof's profile file and Custom..., which opens the colour space picker"
    )
    docker._sync_proof_option()
    assert_false(row.visible, "Hidden while the proof is off")

    notice.label.text = ""
    docker.toggle_proof()
    assert_true(row.visible, "Switching the proof on with Soft Proof shows it")
    assert_eq(gamut.selected_value(), "srgb", "on the setting's gamut")
    assert_true(notice.label.text.contains("nothing inside the document's gamut is clipped"), notice.label.text)

    notice.label.text = ""
    assert_true(docker.choose_proof_gamut("display_p3"), "Display P3 can be chosen on it")
    assert_eq(SaSettings.proof_profile, "display_p3", "which writes the setting Preferences and Ctrl+Y read")
    assert_true(notice.label.text.contains("shown as Display P3"), "and says what it does: %s" % notice.label.text)

    SaSettings.minimap_proof_mode = "lightness_check"
    docker._sync_proof_option()
    assert_false(row.visible, "A mode that is not a proof has no gamut")
    assert_false(docker.choose_proof_gamut("srgb"), "and a hidden choice cannot be made")
    assert_eq(SaSettings.proof_profile, "display_p3", "so the setting stays")

    SaSettings.minimap_proof_mode = "soft_proof"
    SaSettings.proof_profile = "rec2020"
    docker._sync_proof_option()
    assert_true(row.visible, "Back on Soft Proof the gamut shows again")
    assert_eq(gamut.selected_value(), "rec2020", "following a gamut chosen in Preferences")


func test_the_mode_and_the_gamut_read_whole_at_the_default_width() -> void:
    _build()
    var docker := _minimap()
    docker.size = MinimapDocker.DEFAULT_SIZE
    docker.toggle_proof()
    var column := docker._control_node.get_node("VBoxContainer") as Control
    var mode := docker.find_child("ProofMode", true, false) as SaChoiceButton
    var gamut := docker.find_child("ProofGamut", true, false) as SaChoiceButton
    for profile_id: String in SaSettings.DISPLAY_PROFILES:
        SaSettings.proof_profile = profile_id
        docker._sync_proof_option()
        _sort(column)
        _sort(column)
        for pair: Array in [[mode, "Soft Proof"], [gamut, SaColorSpace.display_name(StringName(profile_id))]]:
            var button := pair[0] as SaChoiceButton
            var words := String(pair[1])
            assert_eq(button.text, words, "The choice shows %s" % words)
            var needed := _needed(button, words)
            var cut := "At %d the choice is %.1f of the %.1f '%s' needs" % [docker.size.x, button.size.x, needed, words]
            assert_true(button.size.x + 0.5 >= needed, cut)
            var right := button.position.x + button.size.x
            assert_true(right <= button.get_parent_control().size.x + 0.5, "and it ends inside its row for %s" % words)
