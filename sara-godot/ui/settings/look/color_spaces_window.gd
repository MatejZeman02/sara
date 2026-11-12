## Help > Colour Spaces: the colour space browser in a window of its own,
## opened on whatever the current document uses and following it.
##
## Not a page of Preferences, which holds settings and nothing else: the
## browser has no setting on it, so it sits in Help beside the manual, where a
## painter looks for something to read rather than something to change. The
## page is the class Preferences drew, held here, so the browser follows the
## document the way it always did.
##
## Never modal, like Preferences: a painter reads a gamut beside the painting
## and goes on painting.
@tool
class_name SaColorSpacesWindow
extends SaDialogWindow

## What the window is called, and what a driver finds it by.
const NODE_NAME := "ColorSpacesWindow"

## Room for the diagram and its two choosers at the default font, and the least
## a laptop at an interface scale of 2 can still read the choosers in. The page
## scrolls, so a shorter window costs the diagram's foot and never a control.
const OPENING_SIZE := Vector2i(960, 760)
const FLOOR := Vector2i(480, 320)

var page: SaColorSpacesPage


func _init() -> void:
    _init_dialog(NODE_NAME, tr("Colour Spaces"), OPENING_SIZE, FLOOR)
    exclusive = false
    var scroll := ScrollContainer.new()
    scroll.name = "Scroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.add_child(scroll)
    var margin := SaMake.margin(scroll, "Margin", SaTheme.PAD)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page = SaColorSpacesPage.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_child(page)
    # The page's one row has no title, and a measured column of nothing gives
    # the browser the whole width, where a dialog's fixed label column did not.
    SaSettingsRows.measure(margin)
