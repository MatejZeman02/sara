## How the toolbox's buttons are arranged, and the two Preferences options that
## decide it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside `toolbox_docker.gd` rather than in it, because the arithmetic here is the one part of the docker that can be graded
## without a window: it is a count, a rectangle and two settings in, and a
## column count out.
##
## **Preferences may set an orientation and a cap on the rows or columns**, and
## the docker's own rectangle is the default, `FOLLOW_SHAPE`, so a painter who
## never opens Preferences sees the shape they dragged.
##
## **Following the shape is a row or a column, never a grid**, rather than the
## count re-spread over the rows the width needs, which turns a resize into a
## grid. Setting
## Orientation to Horizontal or Vertical with the cap above one still draws one.
class_name SaToolBoxGrid
extends RefCounted

## The Preferences category the toolbox's page is drawn from, and the two keys
## under it.
const CATEGORY: String = SaDockerIds.TOOLBOX
const ORIENTATION := "orientation"
const MAX_LINES := "max_lines"

## What `ORIENTATION` can be. Stored as these keys rather than as an index, so a
## fourth one added later does not change what a stored profile means.
const FOLLOW_SHAPE := "shape"
const HORIZONTAL := "horizontal"
const VERTICAL := "vertical"

## The padding the grid sits inside, in logical units: the margin container on
## each side plus the scrolling pane's own bar allowance.
##
## Only the row test reads it, and there it stays, because a row the toolbox
## turns into has to leave the bar its room should the row ever scroll.
const PADDING := 10.0

## The most rows or columns a painter can ask for. Twelve, which is over the
## number of category buttons there are, so the cap can never be the thing
## stopping a layout the toolbox could otherwise draw.
const MAX_LINES_CEILING := 12


## Gives the toolbox its two Preferences rows, once, and a view of each tool
## another docker can hold. Idempotent, because
## `SaSettings.register_docker_option` refuses a key it already holds and a
## second view replaces the first, and a docker rebuilt after a module load calls
## this again. The views are here because this is where the docker registers
## what it offers Preferences, with no line of its own in `toolbox_docker.gd`.
static func register_options() -> void:
    SaToolBoxViews.register()
    (
        SaSettings
        . register_docker_option(
            CATEGORY,
            ORIENTATION,
            {
                "title": "Orientation",
                "hint": "Which way the tool buttons run. Follow the shape uses the rectangle the docker is dragged into.",
                "kind": SaSettingsLayout.OPTION_CHOICE,
                "values": [FOLLOW_SHAPE, HORIZONTAL, VERTICAL],
                "labels": ["Follow the shape", "Horizontal", "Vertical"],
                "default": FOLLOW_SHAPE,
            }
        )
    )
    (
        SaSettings
        . register_docker_option(
            CATEGORY,
            MAX_LINES,
            {
                "title": "Maximum rows or columns",
                "hint": "How many rows a horizontal toolbox wraps into, or columns a vertical one does.",
                "kind": SaSettingsLayout.OPTION_COUNT,
                "min": 1,
                "max": MAX_LINES_CEILING,
                "default": 1,
                # Dimmed and disabled while the docker follows its own rectangle,
                # because a shape that answers the question itself has no cap to
                # obey, and a dimmed control is a disabled one.
                "disabled_when": {"key": ORIENTATION, "value": FOLLOW_SHAPE},
            }
        )
    )


## Which orientation the toolbox is set to, as one of the three keys above.
static func orientation() -> String:
    var stored: Variant = SaSettings.get_docker_option(CATEGORY, ORIENTATION)
    return String(stored) if stored != null else FOLLOW_SHAPE


## How many lines the painter capped the wrap at, at least one.
static func max_lines() -> int:
    var stored: Variant = SaSettings.get_docker_option(CATEGORY, MAX_LINES)
    return clampi(int(stored) if stored != null else 1, 1, MAX_LINES_CEILING)


## How many columns *count* buttons should be laid out in.
##
## *logical_width* and *logical_height* are the docker's rectangle in logical
## units and *button_width* one button's, all three of which only the shape
## branch reads. Static and taking its world as arguments, so a test grades the
## arithmetic without a window.
##
## **A forced orientation reads the host instead of the docker.** *room* is the
## longest the grid may run in each axis, in logical units and past the docker's
## margins and drag bar, and *gap* the space the grid leaves between two
## buttons. Rather than the cap alone, which would put the end of a long row
## past the docker's edge with nothing to scroll, a cap that would draw a line
## longer than *room* wraps into one more column or row instead, and so draws more lines
## than the painter's cap, because a tool cut off the end is worse than a
## second row. `Vector2.INF`, the default, says there is no limit, which is
## every caller that grades the cap alone. The buttons are square, so
## *button_width* is the height too.
static func columns_for(
    count: int,
    logical_width: float,
    logical_height: float,
    button_width: float,
    room: Vector2 = Vector2.INF,
    gap: Vector2 = Vector2.ZERO
) -> int:
    var buttons := maxi(1, count)
    var mode := orientation()
    if mode == VERTICAL:
        # The cap is the columns, and a toolbox never draws more columns than it
        # has buttons, or the last column of the row is empty.
        var columns := mini(max_lines(), buttons)
        var rows_that_fit := lines_that_fit(room.y, button_width, gap.y, buttons)
        if int(ceil(float(buttons) / float(columns))) > rows_that_fit:
            columns = int(ceil(float(buttons) / float(rows_that_fit)))
        return columns
    if mode == HORIZONTAL:
        # The cap is the rows, and the buttons are spread evenly over them.
        var wanted := mini(max_lines(), buttons)
        var across := int(ceil(float(buttons) / float(wanted)))
        return mini(across, lines_that_fit(room.x, button_width, gap.x, buttons))
    # Follow the shape, which is one of two answers and never a third: this
    # branch reads the rectangle for a single row or a single column and stops
    # there, because a resize that turns into a grid is not wanted. The grid is
    # reachable by setting Orientation to Horizontal or Vertical and the cap
    # above one, and is never what a drag does on its own.
    #
    # A row wants both halves of the rectangle to agree to it: wider than it is
    # tall, so the shape the painter dragged is a row, and wide enough to hold
    # every button, because the toolbox scrolls down and not across and a row it
    # cannot afford would put its last tools past the right edge with no way to
    # reach them. Anything else is the column, which always fits.
    var usable := logical_width - PADDING
    var fits := maxi(1, int(floor(usable / button_width)))
    if logical_width > logical_height and fits >= buttons:
        return buttons
    return 1


## How many buttons of *button* units, *gap* apart, run along *room* units, at
## least one and never more than *count*. Infinite *room* is every button.
static func lines_that_fit(room: float, button: float, gap: float, count: int) -> int:
    if is_inf(room):
        return count
    return clampi(int(floor((room + gap) / (button + gap))), 1, count)


## Shows *scroll*'s bar only where *width*, in the scroll's units, has room for
## it beside what it scrolls, and a width of 0 is the narrowest the docker can be.
##
## A `ScrollContainer` adds its bar's width to its own minimum whenever the bar
## shows, so a toolbox one button wide that scrolled was floored eight units
## wider than its buttons, and the strip was the bar's. With no room the bar is
## not shown, and the column still scrolls under the wheel and a dragging finger,
## which is the same answer `docker_column_scroll.gd` gives the sideways axis.
## The theme's panel keeps the bar clear of the docker's grip by a gap on its
## right, and with the bar folded away that gap was the strip, so it goes too.
static func fit_scroll_bar(scroll: ScrollContainer, width: float) -> void:
    if scroll == null or scroll.get_child_count() == 0:
        return
    var held := scroll.get_child(0) as Control
    if held == null:
        return
    var bar := scroll.get_v_scroll_bar()
    var edge := float(SaUI.px(SaThemeDefaults.SCROLLBAR_EDGE_GAP))
    var needs := held.get_combined_minimum_size().x + edge + (bar.get_combined_minimum_size().x if bar != null else 0.0)
    var mode := ScrollContainer.SCROLL_MODE_AUTO if width > needs else ScrollContainer.SCROLL_MODE_SHOW_NEVER
    if scroll.vertical_scroll_mode == mode:
        return
    scroll.vertical_scroll_mode = mode
    if mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER:
        scroll.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
    else:
        scroll.remove_theme_stylebox_override(&"panel")


## Only the buttons a painter can see count towards the column cap. A tool
## hidden from Preferences > ToolBox is still a child of the grid, and counting
## it left a column of the row empty.
static func visible_button_count(grid: GridContainer) -> int:
    var count := 0
    if grid == null:
        return count
    for child in grid.get_children():
        if child is Control and (child as Control).visible:
            count += 1
    return count


## The word a person would use for a grid of *columns* holding *count* buttons.
static func shape_of(columns: int, count: int) -> String:
    if columns >= count and count > 1:
        return "row"
    return "grid" if columns > 1 else "column"


## Whether the buttons divide the docker's width between them.
##
## A row and a grid do, and should: a scenario's third shot is five buttons
## sharing a 400-wide docker and that is what a row looks like. **A column did
## too, and should not.** The grid and every button in it are `SIZE_EXPAND_FILL`
## from `_init`, which nothing noticed while a middle width still laid out a
## grid, so a dump of a 150 by 110 docker reads five buttons drawn 138 by 40: an
## icon in the middle of three and a half button widths of nothing. The same
## dump at 60 wide reads 48 by 40, so the stretch has always been there and only
## the amount was small.
static func buttons_fill_width(columns: int, count: int) -> bool:
    return shape_of(columns, count) != "column"


## Sets *buttons* to fill *grid*'s width or to keep their own, by the shape
## *columns* and *count* lay out, and narrows the grid with them.
##
## Here rather than on the docker because the decision above is here. Takes its
## world as arguments the way `columns_for` does, so a test grades it over a
## `GridContainer` it built itself rather than over a window.
##
## **The grid only narrows when there is a button to narrow to.** The empty
## state is one autowrapping [Label], and an autowrapping label's minimum width
## is a single pixel, so a shrunk grid would draw "No tools" as a one-pixel
## sliver instead of the wrapped line the docker shows when no modules are installed.
static func apply_button_width(grid: GridContainer, buttons: Dictionary, columns: int, count: int) -> void:
    var fills := buttons_fill_width(columns, count)
    var flag := Control.SIZE_EXPAND_FILL if fills else Control.SIZE_SHRINK_CENTER
    for category: Variant in buttons:
        var btn := buttons[category] as Button
        if btn != null and is_instance_valid(btn):
            btn.size_flags_horizontal = flag
    if grid != null:
        var grid_flag := Control.SIZE_EXPAND_FILL
        if not fills and not buttons.is_empty():
            grid_flag = Control.SIZE_SHRINK_CENTER
        grid.size_flags_horizontal = grid_flag


# --- Which layout row a tool sits under ---------------------------------------
#
# Layout files store display strings and a tool is an id, so the mapping has to
# be derived. Here rather than on the docker because it reads nothing off a
# window, and because the docker was at 705 lines with it.


## The layout entry for *descriptor*, out of the order the settings hold, so a
## visibility switch and the button it governs are the same row.
##
## Derived rather than matched. The entries and the ids disagree in two
## different directions: "Bucket Fill Tool" is the id `bucket_fill` and the
## label "Fill", and "Magic Wand Tool" is the id `wand` and the label "Magic
## Wand". The id alone would leave **hiding the magic wand in Preferences doing
## nothing**, silently, since the entry would resolve to no button and the loop
## that reads visibility only walks entries it resolved.
static func layout_entry_for(descriptor: SaToolDescriptor) -> String:
    for element: String in SaSettings.get_layout_order(CATEGORY):
        if entry_matches(element, descriptor):
            return element
    return "%s Tool" % String(descriptor.id).replace("_", " ").capitalize()


## Whether the stored layout string *element* names *descriptor*, by its id or
## by its label. Both, because the two lists were written at different times.
static func entry_matches(element: String, descriptor: SaToolDescriptor) -> bool:
    var wanted := element.trim_suffix(" Tool").to_lower()
    if wanted == String(descriptor.id).replace("_", " ").to_lower():
        return true
    return wanted == descriptor.display_name.to_lower()


## "Brush Tool" -> `paint`, the category whose button draws that tool. *members*
## is the docker's category -> descriptors table, handed over rather than reached
## for, so this stays a function of its arguments.
static func category_for_layout_entry(members: Dictionary, element: String) -> StringName:
    for category: StringName in members:
        for descriptor: SaToolDescriptor in members[category]:
            if entry_matches(element, descriptor):
                return category
    return &""
