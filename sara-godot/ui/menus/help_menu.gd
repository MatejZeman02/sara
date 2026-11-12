## The Help menu: the two ways of learning first, the Manual and the lessons
## under one heading, then Welcome, the colour spaces, where to report and the
## note mode, then the three Preferences pages a painter looks for from a menu
## under a heading of their own, and About.
##
## A list of commands, whose handlers open the dialogs through the event bus
## the way Preferences and New do, so `MainDialogs` owns them and a capture
## scenario can open them by name. The report target is the issue tracker of
## the repository on GitHub.
##
## **Nothing here is for a developer.** Documentation, the developers' pages,
## and Local Server, the port a notebook or a script paints through, are in
## the Develop section of the Modules menu, because a painter opens Help to find
## help and would read past both every time. Their ids here, 502 and 507, are
## not used again, since an id is a row of the menu it was minted in.
class_name SaHelpMenu
extends SaMenu

const ID_ABOUT := 500
const ID_SHORTCUTS := 501
const ID_REPORT := 503
const ID_NOTE := 504
## Help opens the welcome window again, the one the boot shows and a painter may
## have turned off in it. 505 was free, so the ids above keep the numbers a
## profile's stored order already holds.
const ID_WELCOME := 505
## The painter's manual, in a window of Sara's own. 506 was free.
const ID_MANUAL := 506
## The Display and Tablet pages of Preferences, here rather than in a Settings
## menu of their own, which would only take space on the bar. Keyboard
## Shortcuts has the one row in Help. The ids are this menu's own, because an
## id is a row of the menu it was minted in.
const ID_DISPLAY := 508
const ID_TABLET := 509
## The colour space browser, here rather than in Preferences because it is
## something to read beside the manual and holds no setting. 510 was free.
const ID_COLOR_SPACES := 510

## Where the rows of a module's commands that asked for Help begin, the
## Tutorials row first. A module's row is minted when the menu is built, so its
## id is counted from here in registration order.
const MODULE_ROW_BASE := 600

## The issue form a report opens on, `packaging/public-issue-form.yml` in the
## public copy.
const REPORT_URL := SaAboutDialog.REPOSITORY_URL + "/issues/new?template=problem.yml"


## [constant REPORT_URL] with the form's version and system fields filled in,
## so a report names the build and the machine without the painter looking
## either up. The painter reads both in the form before anything is sent.
static func report_url() -> String:
    var system := SaAboutDialog.machine_lines()
    system.append(SaAboutDialog.modules_line())
    return (
        REPORT_URL
        + "&version="
        + SaBuildInfo.version_line(SaBuildInfo.read()).uri_encode()
        + "&system="
        + "\n".join(system).uri_encode()
    )


## The two ways of learning stand first, Manual and the module's Tutorials
## under one heading, then the rest of the help, then the pages of Preferences
## under a heading of their own, and About last. The order is the menu's own,
## and each row keeps its id and its chord whatever its place.
func _add_items() -> void:
    add_heading(tr("Learn to paint"))
    add_commands([[ID_MANUAL, &"help_manual"]])
    _add_module_rows()
    add_commands(
        [
            LINE,
            [ID_WELCOME, &"help_welcome"],
            [ID_COLOR_SPACES, &"help_color_spaces"],
            [ID_REPORT, &"help_report"],
            [ID_NOTE, &"ui_take_note"],
        ]
    )
    if _descriptor(&"help_display") != null:
        add_separator()
        add_heading(tr("Settings"))
    add_commands(
        [
            [ID_DISPLAY, &"help_display"],
            [ID_TABLET, &"help_tablet"],
            [ID_SHORTCUTS, &"help_shortcuts"],
            LINE,
            [ID_ABOUT, &"help_about"],
        ]
    )
    # The note mode installs itself under Main from here, deferred, so the
    # chord works before the menu has ever been opened. A detached bar, which
    # is what a test builds, has no Main above it and nothing happens.
    SaNoteMode.ensure_from(popup)


## A row for every command a module asked to have in Help, under the Manual in
## the heading of the ways to learn. A command whose module is not loaded was
## never registered, so a Sara without the tutorials module has no Tutorials
## row. A row reads the command's own label, so a module says where to start
## in its own words.
func _add_module_rows() -> void:
    if commands == null:
        return
    var next_id := MODULE_ROW_BASE
    for descriptor: SaCommandDescriptor in commands.list_help_commands():
        add_command(next_id, descriptor.id)
        next_id += 1
