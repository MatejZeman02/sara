## When the picture's own Tonemap forms what the screen shows,
## the View menu's Tonemap Highlights row goes unticked and dimmed, with a
## tooltip saying the picture's Tonemap does the work.
##
## The row is read out of a real View menu built detached over a real surface,
## so the reason comes from the descriptor the skeleton module registered and
## not from a copy the suite wrote. Three things are the point: the tick and the
## dimming follow the document, the painter's own setting is never written, and
## a document without such a filter is untouched by another document's.
extends "res://tests/test_framework.gd"

const OWNER: StringName = &"sara-base-modules"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _menu: SaViewMenu = null
var _popup: SaChoicePopup = null
var _kept_highlights: bool = false


## A filter that is not the picture, the negative the row is read against. It
## forms nothing, so the view keeps its own roll-off.
class PlainFilter:
    extends SaFilter

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _kept_highlights = SaSettings.tonemap_highlights
    SaSettings.tonemap_highlights = true
    _surface = SaTestFixtures.make_surface()
    _registries = SaTestFixtures.make_registries(_surface)
    # The chain the canvas asks `covers_the_picture` of. Its registry is null
    # until a host binds one, and a null one answers no filter at all.
    _surface.easel.compositor.filter_chain.registry = _registries.filters
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("View")
    _menu.view_transforms = _registries.view_transforms
    # Tonemap Highlights is a row of the Display submenu.
    _popup = SaMenu.group_list(_menu.popup, SaViewMenu.ID_DISPLAY_GROUP)


func after_each() -> void:
    _bar.free()
    _surface.easel.free()
    _bar = null
    _menu = null
    _popup = null
    _registries = null
    _surface = null
    SaSettings.tonemap_highlights = _kept_highlights


func _document() -> SaDocument:
    return _surface.easel.document


## A record on the picture's root for *filter*, registered under the key its
## own module and id make.
func _attach(filter: SaFilter) -> SaAttachedFilter:
    _registries.filters.register(filter, OWNER)
    var record := SaAttachedFilter.new(SaFilterRegistry.key_for(OWNER, filter))
    _document().root_filters.append(record)
    return record


func _row() -> StringName:
    for id: StringName in _popup.row_ids():
        var button := _popup.label_button(id)
        if button != null and button.text == "Tonemap Highlights":
            return id
    return &""


func _tip() -> String:
    return _popup.label_button(_row()).tooltip_text


func test_the_row_is_live_and_ticked_while_the_view_does_the_work() -> void:
    assert_false(_row().is_empty(), "View has a Tonemap Highlights row")
    assert_false(_popup.is_disabled(_row()), "which is live on a document with no filter over it")
    assert_true(_popup.is_checked(_row()), "and shows the painter's own setting, which is on")


func test_the_row_goes_unticked_and_dimmed_when_the_picture_carries_its_tonemap() -> void:
    _attach(SaTonemapFilter.new())
    _menu.populate()
    assert_true(_popup.is_disabled(_row()), "A Tonemap over the picture greys the view's own row")
    assert_false(_popup.is_checked(_row()), "and leaves it unticked, since a second one would form a different picture")
    assert_true(
        _tip().contains("A Tonemap filter forms the picture"),
        "and the tooltip says the picture's own Tonemap does the work: %s" % _tip()
    )
    assert_true(_tip().contains("Compress values above 1.0"), "with the row's own sentence still behind the reason")
    assert_true(SaSettings.tonemap_highlights, "The painter's setting is not written by the standing aside")


func test_a_filter_that_forms_no_picture_leaves_the_row_alone() -> void:
    _attach(PlainFilter.new())
    _menu.populate()
    assert_false(_popup.is_disabled(_row()), "A filter that forms nothing leaves the view's own roll-off in place")
    assert_true(_popup.is_checked(_row()), "and the tick with it")


func test_a_record_switched_off_gives_the_view_back() -> void:
    var record := _attach(SaTonemapFilter.new())
    _menu.populate()
    assert_true(_popup.is_disabled(_row()), "On, the filter carries the picture")
    record.enabled = false
    _menu.populate()
    assert_false(_popup.is_disabled(_row()), "and off, the view has its own roll-off back")
    assert_true(_popup.is_checked(_row()), "ticked from the setting, which was never written")


func test_taking_the_filter_off_the_picture_gives_the_view_back() -> void:
    var record := _attach(SaTonemapFilter.new())
    _menu.populate()
    assert_true(_popup.is_disabled(_row()), "The filter is over the picture")
    _document().root_filters.erase(record)
    _menu.populate()
    assert_false(_popup.is_disabled(_row()), "and taken off, the row is live again")
    assert_true(_popup.is_checked(_row()), "with the tick the setting still holds")


## The reason is asked of the context's own easel, so one document's filter is
## no answer about another's.
func test_another_document_is_unaffected() -> void:
    _attach(SaTonemapFilter.new())
    var descriptor := _registries.view_transforms.get_descriptor(&"highlight_rolloff")
    assert_not_null(descriptor, "The skeleton module registered the roll-off")
    assert_false(String(descriptor.idle_reason.call()).is_empty(), "The document with the filter carries its tonemap")
    var other := SaTestFixtures.make_surface()
    var elsewhere := SaTestFixtures.make_registries(other)
    var other_descriptor := elsewhere.view_transforms.get_descriptor(&"highlight_rolloff")
    assert_true(
        String(other_descriptor.idle_reason.call()).is_empty(),
        "A second document with no filter over it has the view's roll-off of its own"
    )
    other.easel.free()
