## Preferences > Performance's Memory budget row lowers the
## budget `SaMemoryBudget` reads, and the reading follows.
##
## Beside the page rather than with the accounting's suite in `core/perf`,
## because a suite under core names no ui.
extends "res://tests/test_framework.gd"

## The stood-in card, eight GiB.
const CARD := 8 << 30

var _share_before := 0.0


func before_each() -> void:
    _share_before = SaSettings.card_memory_share
    SaSettings.card_memory_share = SaSettings.MAX_CARD_MEMORY_SHARE
    SaCardMemory.stand_in(CARD)


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    SaSettings.card_memory_share = _share_before


func test_the_row_lowers_the_budget_and_the_reading_follows() -> void:
    var page := SaPerformancePage.new()
    var row := page.page.row(&"card_memory_share")
    assert_not_null(row, "the Performance page has the row")
    assert_eq(float(row.reads()), 60.0, "reading sixty per cent")
    assert_eq(SaMemoryBudget.budget(), roundi(CARD * 0.6), "and the budget six tenths of the card")
    row.drive(30.0)
    assert_almost_eq(SaSettings.card_memory_share, 0.3, 1e-6, "the row lowers the share")
    assert_eq(SaMemoryBudget.budget(), roundi(CARD * 0.3), "and the budget follows")
    row.drive(90.0)
    assert_almost_eq(SaSettings.card_memory_share, SaSettings.MAX_CARD_MEMORY_SHARE, 1e-6, "never past the default")
    page.free()


func test_the_rows_tooltip_names_the_budget() -> void:
    var said := SaInfoSection.budget_tip(1 << 30, 4 << 30)
    assert_eq(said, "1.0 GiB of the 4.0 GiB budget Sara keeps to on the graphics card, set in Preferences > Performance.", said)
    assert_eq(SaInfoSection.budget_tip(1 << 30, 0), "", "and says nothing with no budget")
