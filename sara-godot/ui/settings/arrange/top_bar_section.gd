## The top bar's section of Layouts and dockers: the two rows that place the
## window buttons, and the line that leads to the bar's element list.
##
## The bar is no docker, but what a painter changes about it is the same sort of
## thing as what they change about a docker, so it is a section of the page the
## dockers are on and has no sidebar entry.
##
## **The list is behind an Elements… button, not drawn here.** It is eighteen
## draggable rows deep, so the window buttons stand above it, and drawn in this
## section it would push Summoned dockers and every docker's line off the page.
## Behind the button it is a docker's part in every way, drawn in the page area
## with a Back row to this section's line, so there is one way to a list and the
## reorder, the capture steps and the search know no second place.
##
## The window buttons are declared here and nowhere else, since two controls on
## one setting is how the two come to disagree.
class_name SaTopBarSection
extends RefCounted

## The key of the first row, what a door that names the old page lands on.
const FIRST_ROW := &"window_button_position"

## Auto, Left, Right, in the order the setting stores them.
const WINDOW_BUTTON_POSITIONS := ["auto", "left", "right"]
const WINDOW_BUTTON_STYLES := ["auto", "lights", "icons"]

## The Elements… button on the bar's line, kept so the capture door presses the
## one a hand would.
var elements_button: Button = null


## The section: the position row, the style row, then the bar's line, whose
## Elements… button calls *ask* with the bar's category and the elements part.
##
## The words behind the button are the bar's controls and the overflow switch,
## so a search for "Overflow" or "Edit" still finds the section, which the page
## answered by being a page.
func declare(ui: SaPage, ask: Callable) -> void:
    var section := ui.section(tr("Top bar"))
    # Both rows are choices, the edge and the look, both Auto, because one
    # dropdown made Left mean the traffic lights. Automatic names what it picks
    # on the computer that is running, from the bar's own rule. The sentences
    # carry the words "Apple" and "macOS", since the search indexes a row by its
    # title and the sentence under it, and a search for mac would find nothing
    # (`scenarios/window-buttons-preference.json`).
    #
    # The row carries the stored word itself, so an entry's id is what its
    # setting stores and no handler is needed. The table beside it is only the
    # list of what is offered.
    var positions: Array = [
        {"id": WINDOW_BUTTON_POSITIONS[0], "label": automatic_position_label(OS.get_name())},
        {"id": WINDOW_BUTTON_POSITIONS[1], "label": tr("Left")},
        {"id": WINDOW_BUTTON_POSITIONS[2], "label": tr("Right")},
    ]
    var position_row := section.choice(tr("Window button position"), positions, SaSettings, ^"window_button_position")
    position_row.named(FIRST_ROW)
    position_row.node("WindowButtonPositionOpt").explain(
        tr(
            (
                "Where minimize, maximize and close sit on the bar. Automatic follows the platform: "
                + "the three sit at the left on macOS, as Apple's traffic lights do, and at the right elsewhere."
            )
        )
    )
    var styles: Array = [
        {"id": WINDOW_BUTTON_STYLES[0], "label": automatic_style_label(OS.get_name())},
        {"id": WINDOW_BUTTON_STYLES[1], "label": tr("Traffic lights")},
        {"id": WINDOW_BUTTON_STYLES[2], "label": tr("Icons")},
    ]
    var style_row := section.choice(tr("Window button style"), styles, SaSettings, ^"window_button_style")
    style_row.named(&"window_button_style")
    style_row.node("WindowButtonStyleOpt").explain(
        tr(
            (
                "What the three look like. Traffic lights are macOS's coloured dots, icons are the "
                + "Windows and GNOME glyphs. Automatic draws the lights on macOS and the icons elsewhere."
            )
        )
    )
    var buttons := SaMake.row(null, "DockerButtons_%s" % SaDockersPage.TOP_BAR, SaTheme.GAP)
    elements_button = SaMake.button(
        buttons,
        "Elements_%s" % SaDockersPage.TOP_BAR,
        tr("Customize..."),
        tr("Choose which controls the top bar shows, their order, and whether the overflow list holds the rest.")
    )
    elements_button.pressed.connect(ask.bind(SaDockersPage.TOP_BAR, SaLayoutPage.ELEMENTS))
    var line := section.custom(tr("Top bar"), buttons).named(SaDockersPage.line_key(SaDockersPage.TOP_BAR))
    line.explain(tr("Choose which menus and controls the top bar shows, and their order."))
    line.words(_words_behind())


## The titles of every control of the bar and of its overflow switch.
func _words_behind() -> String:
    var words := PackedStringArray([tr("Overflow")])
    for element: String in SaSettings.get_layout_order(SaDockersPage.TOP_BAR):
        words.append(SaSettings.element_title(SaDockersPage.TOP_BAR, element))
    return " ".join(words)


## The Automatic entry of the position row on *os_name*, naming the edge
## `TopMenuBar.window_button_side` picks there.
func automatic_position_label(os_name: String) -> String:
    var right := TopMenuBar.window_button_side(WINDOW_BUTTON_POSITIONS[0], os_name) == "right"
    return tr("Automatic (right on this computer)") if right else tr("Automatic (left on this computer)")


## The Automatic entry of the style row on *os_name*, naming the look
## `TopMenuBar.window_button_style` picks there.
func automatic_style_label(os_name: String) -> String:
    var icons := TopMenuBar.window_button_style(WINDOW_BUTTON_STYLES[0], os_name) == "icons"
    return tr("Automatic (icons on this computer)") if icons else tr("Automatic (traffic lights on this computer)")
