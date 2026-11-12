## Three View toggles change nothing on screen in a fresh document at 0 stops
## with no proof on and no height, and a painter who ticks one to see what it
## does would take it for broken. Each is
## greyed with the reason it shows nothing, keeps its tick, and comes back
## the moment the state it waits for arrives.
##
## The bar is built detached, the way `test_view_transforms.gd` builds it, over
## registries whose context answers a real easel, because two of the three
## reasons are questions about the document and the view.
extends "res://tests/test_framework.gd"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _menu: SaViewMenu = null
var _popup: SaChoicePopup = null

var _kept_stops: float = 0.0
var _kept_exposure_on: bool = false
var _kept_strength: float = 0.0
var _kept_relief: bool = false


func before_each() -> void:
    _kept_stops = SaSettings.display_exposure_stops
    _kept_exposure_on = SaSettings.display_exposure_enabled
    _kept_strength = SaSettings.relief_strength
    _kept_relief = SaSettings.show_relief
    # The sweep's state: the stops at their default of 0, the relief ticked and
    # at its default strength, and the ordinary view.
    SaSettings.display_exposure_stops = 0.0
    SaSettings.display_exposure_enabled = false
    SaSettings.relief_strength = 2.0
    SaSettings.show_relief = true
    _surface = SaTestFixtures.make_surface()
    _registries = SaTestFixtures.make_registries(_surface)
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("View")
    _menu.view_transforms = _registries.view_transforms
    # Every toggle is a row of the Display submenu, and the list
    # is made once and filled again on every build.
    _popup = SaMenu.group_list(_menu.popup, SaViewMenu.ID_DISPLAY_GROUP)


func after_each() -> void:
    _bar.free()
    _surface.easel.free()
    _bar = null
    _menu = null
    _popup = null
    _registries = null
    _surface = null
    SaSettings.display_exposure_stops = _kept_stops
    SaSettings.display_exposure_enabled = _kept_exposure_on
    SaSettings.relief_strength = _kept_strength
    SaSettings.show_relief = _kept_relief


## The popup row of the toggle labelled *label*, found by its words so the suite
## does not hold the menu's order as a second copy.
func _row(label: String) -> StringName:
    for id: StringName in _popup.row_ids():
        var button := _popup.label_button(id)
        if button != null and button.text == label:
            return id
    return &""


func _tip(label: String) -> String:
    return _popup.label_button(_row(label)).tooltip_text


func _document() -> SaDocument:
    return _surface.easel.document


func test_each_row_is_greyed_with_its_reason_in_the_state_the_sweep_met() -> void:
    var reasons := {
        "Display Exposure": "at 0 stops",
        "Gamut Warning": "outside Soft Proof",
        "Show Impasto": "nothing in sight has impasto",
    }
    for label: String in reasons:
        var id := _row(label)
        assert_false(id.is_empty(), "%s has a row on View" % label)
        assert_true(_popup.is_disabled(id), "%s is greyed while it would change nothing" % label)
        assert_true(_tip(label).begins_with("Changes nothing"), "and its hover leads with why: %s" % _tip(label))
        assert_true(_tip(label).contains(reasons[label]), "%s says %s" % [label, reasons[label]])
        assert_eq(_popup.check_box(id).tooltip_text, _tip(label), "and its box says the same, being the half still live")
    # The reason goes in front of the sentence rather than in its place, so a
    # greyed row still says what it would do.
    assert_true(_tip("Display Exposure").contains("Brighten or darken the view"), "The sentence follows the reason")
    for label: String in ["Tonemap Highlights", "Gamut Mapping"]:
        assert_false(_popup.is_disabled(_row(label)), "%s changes something already and is not greyed" % label)
        assert_false(_tip(label).begins_with("Changes nothing"), "and says only what it does")


func test_a_greyed_row_keeps_its_tick_and_its_box() -> void:
    var relief := _row("Show Impasto")
    assert_true(_popup.is_disabled(relief), "Show Impasto is greyed on a document with no height")
    assert_true(_popup.is_checked(relief), "and keeps the tick the setting gives it")

    var warning := _row("Gamut Warning")
    assert_false(_registries.view_transforms.is_enabled(&"gamut_warning"), "The warning starts off")
    assert_true(_popup.press_check(warning), "Its box still takes a press while the words are grey")
    assert_true(_registries.view_transforms.is_enabled(&"gamut_warning"), "so the warning is put on ahead of the proof")
    _menu.populate()
    assert_true(_popup.is_checked(_row("Gamut Warning")), "and the greyed row shows it ticked")
    assert_true(_popup.is_disabled(_row("Gamut Warning")), "still greyed, because there is still no proof")


func test_the_exposure_row_comes_back_with_its_stops() -> void:
    SaSettings.display_exposure_stops = 1.5
    _menu.populate()
    assert_false(_popup.is_disabled(_row("Display Exposure")), "The stops set, the row is live")
    assert_true(_tip("Display Exposure").begins_with("Brighten or darken the view"), "and says only what it does")
    assert_eq(_popup.check_box(_row("Display Exposure")).tooltip_text, "", "with nothing left on its box")
    SaSettings.display_exposure_stops = 0.0
    _menu.populate()
    assert_true(_popup.is_disabled(_row("Display Exposure")), "and back to 0, greyed again")


func test_the_warning_row_comes_back_with_the_proof() -> void:
    assert_true(_registries.view_transforms.set_mode(&"soft_proof"), "Soft Proof is put on")
    # No populate here: the registry's change signal rebuilds the menu, which
    # is what makes the row follow a mode picked from this very menu.
    assert_false(_popup.is_disabled(_row("Gamut Warning")), "and the warning row is live at once")
    _registries.view_transforms.set_mode(SaViewTransformRegistry.NORMAL)
    assert_true(_popup.is_disabled(_row("Gamut Warning")), "and greyed again once the proof is off")


func test_the_relief_row_comes_back_with_a_height() -> void:
    var paint := _document().active_layer
    assert_not_null(paint, "The fresh document has its paint layer active")
    assert_true(SaHeightOps.new(_document()).gain(paint), "which gains a height, as a height dab's first stroke does")
    _menu.populate()
    assert_false(_popup.is_disabled(_row("Show Impasto")), "The relief row is live once a layer has a height")
    paint.visible = false
    _menu.populate()
    assert_true(_popup.is_disabled(_row("Show Impasto")), "and greyed again once that layer is hidden")


func test_a_ground_with_a_tooth_is_a_height_too() -> void:
    var paper := _registries.context.create_layer(&"paper")
    assert_not_null(paper, "A Paper ground goes in")
    assert_true(SaGeneratedLayer.tooth_of(paper) > 0.0, "with a tooth of its own")
    assert_false(SaRelief.shows_height(_document()), "which the export's question does not count")
    _menu.populate()
    assert_false(_popup.is_disabled(_row("Show Impasto")), "and the view lights all the same, so the row is live")


## The strength is the document's own, so the reason reads
## the document's light, and Preferences' strength of 0 greys nothing.
func test_a_relief_strength_of_0_is_its_own_reason() -> void:
    _registries.context.create_layer(&"paper")
    SaSettings.relief_strength = 0.0
    _menu.populate()
    assert_false(_popup.is_disabled(_row("Show Impasto")), "Preferences' strength is where a new document starts")
    _document().relief_light.strength = 0.0
    _menu.populate()
    assert_true(_popup.is_disabled(_row("Show Impasto")), "With no strength the relief lights nothing, ground or not")
    assert_true(_tip("Show Impasto").contains("relief strength of 0"), "and says that is why")
    assert_true(_tip("Show Impasto").contains("Relief Light..."), "and where the document's is set")


## Rule 6: the reason is the descriptor's, so a module's toggle earns a greyed
## row by the same door, and one that says nothing is never greyed.
func test_a_modules_toggle_is_greyed_by_the_same_door() -> void:
    var quiet := SaViewTransformDescriptor.create(&"quiet", "Quiet Toggle", SaViewTransformDescriptor.Kind.TOGGLE)
    quiet.sort_order = 90
    var waiting := SaViewTransformDescriptor.create(&"waiting", "Waiting Toggle", SaViewTransformDescriptor.Kind.TOGGLE)
    waiting.sort_order = 91
    waiting.idle_reason = func() -> String: return "Changes nothing until the module has a target."
    var ctx := _registries.context.for_module(&"view-reason-test")
    assert_true(ctx.register_view_transform(quiet), "A module's toggle with no reason registers")
    assert_true(ctx.register_view_transform(waiting), "and so does one with a reason")
    assert_false(_popup.is_disabled(_row("Quiet Toggle")), "The one that never says is never greyed")
    assert_true(_popup.is_disabled(_row("Waiting Toggle")), "and the one that says is greyed")
    assert_eq(_tip("Waiting Toggle"), "Changes nothing until the module has a target.", "with its reason alone to say")
    ctx.remove_all_registrations()
