## The start-up block's Display row names the display's refresh rate, and says
## so when the driver answers -1.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A primitive prints and GDScript cannot capture stdout, so what is read here
## is the row's own value, which is what `SaConsole.field` is handed and what
## the machine mode prints after the colour is out. The block itself in a run's
## log is the proof the row reaches the screen.
extends "res://tests/test_framework.gd"


## The row names the rate the window's screen refreshes at, to the hertz, so a
## painter reading the log knows what the line's budget was judged against.
func test_the_display_row_names_the_refresh_rate() -> void:
    var row := SaConsole.plain(SaBootHeader.display_row("Wayland", Vector2i(2560, 1440), 1.5, 60.0))
    assert_true(row.contains("Wayland"), "The server is named: %s" % row)
    assert_true(row.contains("2560×1440"), "and the size")
    assert_true(row.contains("1.50×"), "and the scale")
    assert_true(row.contains("60 Hz"), "and the refresh rate")
    assert_eq(SaBootHeader.rate_text(59.94), "60 Hz", "A rate is read to the nearest hertz")
    assert_eq(SaBootHeader.rate_text(144.0), "144 Hz", "whatever the panel answers")


## A driver that answers -1 says so rather than reading as a rate of nought, and
## the row names no hertz at all.
func test_the_display_row_says_so_when_the_driver_will_not_answer() -> void:
    var row := SaConsole.plain(SaBootHeader.display_row("Wayland", Vector2i(2560, 1440), 1.0, -1.0))
    assert_true(row.contains("refresh rate unknown"), "The row says the rate is not there: %s" % row)
    assert_false(row.contains("Hz"), "and names no hertz")
    assert_eq(SaBootHeader.rate_text(-1.0), "refresh rate unknown", "which is what the block's own words are")
    assert_eq(SaBootHeader.rate_text(0.0), "refresh rate unknown", "and a rate of nought is no rate")


## The row is built from the screen the window is on, which is the rate the
## ledger's budget follows.
func test_the_screen_s_rate_is_the_one_the_row_reads() -> void:
    var hertz := SaBootHeader.screen_hz()
    var row := SaConsole.plain(SaBootHeader.display_row("Wayland", Vector2i(1920, 1080), 1.0, hertz))
    assert_eq(row.contains("refresh rate unknown"), hertz <= 0.0, "The row reads whatever the server answered: %s" % row)
