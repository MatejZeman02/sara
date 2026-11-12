## The top bar's element list: the menu titles and the tool controls in the order
## the bar draws them, each with a switch, then the overflow switch and what each
## row of the bar has spent. Opened by the Elements… button of the top bar's
## section on Layouts and dockers, with a Back row to that section.
##
## The widths come from the live bar's minimum sizes, so they are right before
## anything is dragged, which is the point: a row that does not fit is the
## failure the phase exists to prevent. The second row's own switch is the
## sentinel row's, in the list itself, not a separate control up here. The
## overflow's switch is under the list, beside the readout it changes.
##
## The readout says what a painter gets, whether everything fits and how many
## controls the overflow list holds, and not the pixels each row spent of its
## budget, a figure a painter cannot act on. The figures are in [method
## describe_rows] for a dump.
##
## **The window buttons are not here.** The two rows that place them sit in the
## top bar's section of Layouts and dockers, [SaTopBarSection], above the way to
## this list, because the list is eighteen draggable rows deep and a row under
## it opens off the bottom of the page. They are the one pair of controls that
## write `window_button_position` and `window_button_style`, since two controls
## on one setting is how the two come to disagree.
class_name SaTopBarPage
extends SaLayoutPage

var _readout: Label


func _init(back: Callable = Callable()) -> void:
    super("TopMenuBar", ELEMENTS, back)
    # The note is a label the layer built, so it is read back off its row once
    # the page is realized, which `super` has just done.
    _readout = page.row(&"readout").line as Label
    # Deferred, because the switch this reports on writes the setting and the
    # bar re-lays out on the same signal. Read inline and the sentence describes
    # the layout before the change rather than after it.
    var refresh := func() -> void: _refresh_row_readout.bind(_readout).call_deferred()
    SaSettings.profile_changed.connect(refresh)
    _readout.tree_exiting.connect(func() -> void: SaSettings.profile_changed.disconnect(refresh))


## The overflow switch, then the readout. The switch is one of the bar's
## per-docker options, bound through a binding over the registry the way
## `SaLayoutDockerOptions` binds a docker's, and it reads as on when nothing has
## registered it yet, which is a page opened before any bar was built.
func _declare_below(section: SaPageSection) -> void:
    var option := TopMenuBar.OVERFLOW_OPTION
    var binding := SaPageBinding.new(
        func(_key: StringName) -> Variant: return SaSettings.get_docker_option("TopMenuBar", option) != false,
        func(_key: StringName, value: Variant) -> void: SaSettings.set_docker_option("TopMenuBar", option, bool(value))
    )
    section.toggle(tr("Overflow"), binding, ^"overflow").named(&"overflow").node("OverflowCheck").explain(
        tr(
            (
                "Controls that do not fit on their row go into the overflow list, which the button at the end "
                + "of the top bar opens and a pen reaches with one tap. When off, a row scrolls instead."
            )
        )
    )
    section.note(tr("")).named(&"readout").node("RowWidthReadout")


## The bar is only reachable through the tree, so the first reading waits for
## one, and a page built off the tree says so instead.
##
## The bar refits on a window resize as well as on a setting, so the readout
## follows its `refitted` too. Read only on a setting, it said one control was in
## the overflow list at 1280 while ten were, the count of the width the page
## was opened at.
func _ready() -> void:
    super()
    _refresh_row_readout(_readout)
    var bar := _top_bar()
    if bar != null and not bar.rows.refitted.is_connected(_on_bar_refitted):
        bar.rows.refitted.connect(_on_bar_refitted)


func _exit_tree() -> void:
    var bar := _top_bar()
    if bar != null and bar.rows.refitted.is_connected(_on_bar_refitted):
        bar.rows.refitted.disconnect(_on_bar_refitted)


func _on_bar_refitted() -> void:
    _refresh_row_readout.bind(_readout).call_deferred()


func _refresh_row_readout(readout: Label) -> void:
    var bar := _top_bar()
    if bar == null:
        readout.text = tr("While the top bar is open, this line says what does not fit on it.")
        return
    var held: int = (bar.rows.overflow.report()["held"] as Array).size()
    readout.text = fit_sentence(held, _rows_that_scroll(bar), forced_second_row_note(bar.rows._second_row_forced_by))


## The readout's words: the overflow list's count, each row that scrolls, and
## *forced*, the note on a second row kept against the switch. "Everything fits
## on the bar." when nothing is held and nothing scrolls. *scrolling* holds the
## rows by number, 1 for the first.
func fit_sentence(held: int, scrolling: Array[int], forced: String) -> String:
    var said := PackedStringArray()
    if held > 0:
        var overflow := tr_n(
            "%d control is in the overflow list, behind the button at the end of the bar.",
            "%d controls are in the overflow list, behind the button at the end of the bar.",
            held
        )
        said.append(overflow % held)
    for row: int in scrolling:
        if row == 1:
            said.append(tr("The first row does not fit, so it scrolls."))
        else:
            said.append(tr("The second row does not fit, so it scrolls."))
    if said.is_empty():
        said.append(tr("Everything fits on the top bar."))
    if not forced.is_empty():
        said.append(forced)
    return " ".join(said)


## The rows, by number, that hold more than they have room for, which a bar with
## its overflow off scrolls.
func _rows_that_scroll(bar: TopMenuBar) -> Array[int]:
    var out: Array[int] = []
    for row: int in [1, 2]:
        if bar.rows.row_spent(row) > bar.rows.row_budget(row):
            out.append(row)
    return out


## Each row's spent and budget in logical pixels, the figures the readout once
## showed, kept for the dump [method describe_rows] writes.
func _row_widths(bar: TopMenuBar) -> String:
    var lines := PackedStringArray()
    for row: int in [1, 2]:
        lines.append("row %d: %d of %d px" % [row, int(bar.rows.row_spent(row)), int(bar.rows.row_budget(row))])
    return ", ".join(lines)


## What to say when the second row is on and the switch says it is off.
##
## The bar keeps the second row when one row would not hold the controls, and it
## was keeping it silently: at 1920 the first row wants 1163 logical pixels of
## the 1030 it has, so a painter who turned the switch off got two rows anyway
## and nothing anywhere saying why. The state dump knew, reading
## `second_row_forced_by` 133, and the only surface with the switch on it did
## not. The number is the bar's own, so this is a sentence rather than any
## arithmetic.
##
## Empty when the switch is on, and empty when it is off and one row fits, which
## is the whole of what a painter needs the difference between.
##
## Takes the number rather than the bar, so the rule can be asserted without one
## and so the one place that reaches into `SaTopBarRows._second_row_forced_by` is
## the line that reads it.
func forced_second_row_note(over_by: float) -> String:
    if SaSettings.second_row:
        return ""
    var over := int(over_by)
    if over <= 0:
        return ""
    return (
        tr_n(
            "The window is %d pixel too narrow for one row, so the second row stays.",
            "The window is %d pixels too narrow for one row, so the second row stays.",
            over
        )
        % over
    )


## The rows, and the sentence under them.
##
## `SaLayoutPage.describe_rows` reports the list and nothing else, and what this
## page adds is not a row, so a capture could otherwise prove the switch was off
## and not that the page said why. The row widths follow, in pixels, which the
## readout does not show a painter.
func describe_rows(origin: Vector2) -> String:
    var described := super(origin)
    var text := _readout.text if _readout != null and is_instance_valid(_readout) else ""
    var bar := _top_bar()
    var widths := _row_widths(bar) if bar != null else "no bar"
    return "%s\n  readout: %s\n  widths: %s" % [described, text, widths]


func _top_bar() -> TopMenuBar:
    if not is_inside_tree():
        return null
    return get_tree().root.find_child("CustomTitleBar", true, false) as TopMenuBar
