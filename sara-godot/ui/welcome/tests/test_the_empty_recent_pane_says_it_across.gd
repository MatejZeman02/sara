## The welcome window's empty Recent pane says so across the
## whole pane. The line sat in a cell of the cards' grid, inside a grid of four
## in the pane whose three empty columns each took a share of the width, so the
## one sentence wrapped a word or two to a row in the top left quarter.
##
## The pane is laid out in the tree under a host, one sorting pass at a time,
## the way `test_the_presets_docker_reads_at_factory_settings.gd` does it, since
## a suite cannot await the frame the engine would sort in. What the welcome
## window shows on the running app is
## `scenarios/the-welcome-windows-empty-pane-says-it-across-the-pane.json`.
extends "res://tests/test_framework.gd"

## The empty area measured on the Recent pane, in logical units.
const PANE := Vector2(700.0, 350.0)

static var scratch_recent: String = SaDataRoot.path("n111-a-recent-document.sad")

var _saved_recent: Array = []


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))


func after_each() -> void:
    SaSettings.remove_recent_file(scratch_recent)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))


## A pane at *PANE*, in the tree so its labels measure with the theme's font.
func _laid_out_pane() -> WelcomeRecentPane:
    var pane := WelcomeRecentPane.new()
    EventBus.add_child(pane)
    pane.size = PANE
    _sort(pane)
    return pane


## One layout pass from *node* down, three times over, because a wrapped
## label's height follows the width the pass before gave it.
func _sort(node: Node) -> void:
    for _pass in 3:
        _sort_once(node)


func _sort_once(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort_once(child)


func _cards_of(pane: WelcomeRecentPane) -> WelcomeRecentGrid:
    return pane.find_child("RecentCards", true, false) as WelcomeRecentGrid


func test_with_nothing_recent_the_line_is_beside_the_cards_and_as_wide_as_the_pane() -> void:
    var pane := _laid_out_pane()
    var cards := _cards_of(pane)
    assert_not_null(cards, "the pane holds its grid of cards")
    if cards != null:
        var line := cards.empty_line
        assert_not_null(line, "and the grid knows the block the pane laid beside it")
        assert_false(cards.is_ancestor_of(line), "the block is not a child of the cards' grid, nor of its scroll")
        assert_eq(line.get_parent(), cards.get_parent(), "it sits beside the grid in the same parent")
        assert_true(line.visible, "an empty list shows the block")
        assert_false(cards.visible, "and hides the grid, which has nothing to show")
        assert_eq(line.size.x, pane.size.x, "the block is as wide as the pane")
        assert_eq(line.size.y, pane.recent_grid.size.y, "over the whole height the cards would have had")
        var hint := line.find_child("RecentEmptyHint", true, false) as Label
        assert_eq(hint.size.x, pane.size.x, "its sentence is as wide as the pane")
        assert_eq(hint.get_line_count(), 1, "so it reads on one line at the width measured")
        assert_eq(hint.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "centred across the pane")
        var action := line.find_child("OpenAFile", true, false) as Button
        var middle := action.get_global_rect().get_center().x - pane.get_global_rect().position.x
        assert_almost_eq(middle, pane.size.x / 2.0, 1.0, "and the Open a file action above it stands in the middle")
    pane.free()


## The same grid of four gave the cards' scroll a quarter of the pane. Four
## cards are wider than that, so a full list hid it, and one card did not.
func test_one_recent_document_hides_the_line_and_its_card_has_the_pane() -> void:
    SaSettings.add_recent_file(scratch_recent)
    var pane := _laid_out_pane()
    var cards := _cards_of(pane)
    assert_eq(cards.cards.size(), 1, "one recent path draws one card")
    assert_true(cards.visible, "the grid shows")
    assert_false(cards.empty_line.visible, "and the line is gone")
    assert_eq(cards.size.x, pane.size.x, "the cards' scroll is as wide as the pane")
    assert_eq(cards.grids[0].columns, 4, "with the cards four to a row")
    pane.free()


## A grid hidden by its own empty list, in a window that is hidden too, draws
## its card at once when a path arrives. The show of the window reaches no
## child hidden itself, so a grid that waited for it would wait for good and
## the pane would go on saying nothing was opened.
##
## The list is moved with the settings' signal held and the draw asked for
## by hand, since the signal also asks for a readback two frames later and a
## suite frees the grid before those frames come.
func test_a_hidden_empty_grid_draws_a_path_that_arrives_at_once() -> void:
    var pane := _laid_out_pane()
    var cards := _cards_of(pane)
    pane.hide()
    SaSettings.set_block_signals(true)
    SaSettings.add_recent_file(scratch_recent)
    SaSettings.set_block_signals(false)
    cards._draw_cards()
    assert_eq(cards.cards.size(), 1, "the card is drawn while the window is away")
    assert_true(cards.visible, "and the grid is back for the next show")
    assert_false(cards.empty_line.visible, "with the line gone")

    SaSettings.set_block_signals(true)
    SaSettings.remove_recent_file(scratch_recent)
    SaSettings.set_block_signals(false)
    cards._draw_cards()
    assert_eq(cards.cards.size(), 1, "a grid on show in a hidden window still waits to be shown")
    pane.show()
    assert_eq(cards.cards.size(), 0, "and the show draws the empty list")
    assert_false(cards.visible, "which hides the grid")
    assert_true(cards.empty_line.visible, "and shows the line in its place")
    pane.free()
