## The News pane of the welcome window: the release notes the build carries that
## a painter has not read yet, newest first, in a column that scrolls.
##
## **What it shows is the feedback request's rule.** The sections newer than the version the
## painter last saw, and when there are none, the running version's own section
## with a line saying it is what is already installed, because an empty column
## under a heading reads as a fault rather than as "nothing has changed".
##
## **Where the notes come from, and why there are two answers.** `SaChangelog.read()`
## says which of a build's packed copy and an editor run's checkout copy
## answered, and `source` in the report carries its word.
##
## **The version is written when the pane has been seen and the window closes**,
## not when it opens, so a painter who shuts the window at once gets the news
## next time. Seen means this pane was on screen, which is its tab of the window
## being current.
##
## **The feedback request above the file is for testers.** A tester's notes are
## written by the recorder, so the paragraph names the
## recorder, where its Export button puts the zip and where to send it, with a
## button that opens the same address Help's own Report row opens. It is pinned
## above the scroll rather than drawn as a section, because a painter must meet
## it whatever version the file says was last seen.
##
## **Everything it says is read again when the language changes.** The boot
## builds the welcome window before the modules register their
## catalogues, so a paragraph joined from `tr()` once in `_init` stayed English
## under Czech while the title and the button, whose text a control translates
## by itself, read Czech. `rebuild` writes the paragraph, the headings and the
## notes again, and a change of language or of catalogues calls it through
## `refresh`. The notes are a language module's where it carries them,
## `SaChangelog.notes_path()`.
##
## **In the welcome window the rows are built once, when the pane is first in
## front**. A fresh profile has every section of the file
## unread, and building them inside the window took 115 ms of the 496 ms frame
## the window's first open held, three builds where one is seen: at the
## pane's construction, when the catalogues are handed in, and when the window
## entered the tree. A pane built with *lazy* builds its sections the first
## time its tab is in front, and again only when what they were read for has
## changed: the language, the catalogues, or the version last seen. A pane built
## on its own, as a suite builds one, builds them at once.
@tool
class_name WelcomeNewsPane
extends VBoxContainer

## The feedback request block, its paragraph, its button row and the button itself, so a test
## or a walker finds them by name rather than by where they sit in the pane.
const ASK_BLOCK: String = "NewsAsk"
const ASK_PARAGRAPH: String = "NewsAskText"
const ASK_BUTTON: String = "NewsReportButton"

## The call the feedback request's button makes, `OS.shell_open` in everything but a suite.
##
## A `Callable` rather than the engine call named at the press site so the suite
## can press the button and read the address it opened: a real press on the
## machine running the gate would put a browser on the desktop of whoever runs it.
## Test seam. A suite that replaces it puts `OS.shell_open` back.
static var opener: Callable = OS.shell_open

## The column the sections are drawn in.
var _sections: VBoxContainer

## The feedback request: the paragraph, and the button beside it.
var _ask_label: Label
var _report_button: Button

## The catalogues the boot registers, handed in by `follow_catalogues`, which
## say where a language module keeps its notes. `null` reads English notes.
var _catalogues: SaTranslationRegistry = null

## This pane was shown at some point since the host window last closed.
##
## Cleared when the write happens rather than when the window opens, because the
## order a `Window` and its children are told they are visible is not this pane's
## to rely on.
var _seen: bool = false

## Whether the sections wait for the pane to be in front, the welcome window's.
var _lazy: bool = false

## What the sections on screen were read for, the version last seen and the
## language, empty before the first build. A show reads them again when either
## moved.
var _built_for: Array[String] = []


## *lazy* is the welcome window's, which builds the sections when the pane
## first comes to the front rather than now.
func _init(lazy: bool = false) -> void:
    _lazy = lazy
    name = "News"
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP))
    SaMake.label(self, "PaneTitle", tr("News"))

    # Above the scroll rather than in it, so the feedback request stays on screen whatever
    # the file says was last seen and the oldest release note does not carry it
    # away.
    add_child(_build_ask())

    # The sections are taller than the pane at any window a welcome window is,
    # so the column scrolls and a long set of notes cannot push the window's
    # buttons off its bottom edge.
    var scroll := SaMake.scroll(self, "NewsScroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _sections = SaMake.column(scroll, "NewsSections")
    _sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    refresh()


func _ready() -> void:
    var host := get_window()
    if host != null:
        host.visibility_changed.connect(_on_host_visibility)


## The pane came on screen, which is `_seen`, and it is redrawn because the
## setting behind it is the one the window it belongs to was built for. A
## change of language redraws it as well, since nothing in it but the title
## and the button translates by itself.
func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED and showing():
        _seen = true
        if _built_for != _reading():
            rebuild()
    elif what == NOTIFICATION_TRANSLATION_CHANGED and _sections != null:
        refresh()


## Reads the notes of the language in force from *registry*'s modules from
## now on, and redraws whenever a catalogue comes or goes. The welcome window
## hands it in with the Quick settings pane's.
func follow_catalogues(registry: SaTranslationRegistry) -> void:
    if _catalogues != null and _catalogues.changed.is_connected(refresh):
        _catalogues.changed.disconnect(refresh)
    _catalogues = registry
    if _catalogues != null:
        _catalogues.changed.connect(refresh)
    refresh()


## Whether the pane is on screen: shown, and the tab in front when it is in
## a tab container.
func showing() -> bool:
    if not is_visible_in_tree():
        return false
    var tab := SaWelcomeWindow.tab_of(self)
    var tabs := tab.get_parent() as TabContainer
    return tabs == null or tabs.get_current_tab_control() == tab


## Writes the feedback request's paragraph again, and the sections now or, in a lazy pane
## that is not on screen, the next time it is.
func refresh() -> void:
    if _lazy and not showing():
        _ask_label.text = _ask_text()
        _built_for = []
        return
    rebuild()


## What the sections are read for now, which `_built_for` holds of the last build.
func _reading() -> Array[String]:
    return [SaSettings.last_version_seen, TranslationServer.get_locale()]


## The changelog as the language in force reads it.
func _read() -> Dictionary[String, Variant]:
    return SaChangelog.read(SaChangelog.PATH, SaChangelog.notes_path(_catalogues, TranslationServer.get_locale()))


## The host window is the only thing that announces its own close, and the pane
## is hidden with it. A close without the pane having been shown writes nothing.
func _on_host_visibility() -> void:
    var host := get_window()
    if host == null or host.visible or not _seen:
        return
    _seen = false
    SaSettings.last_version_seen = SaBuildInfo.version()


## The feedback request: the paragraph a tester reads, and the button that opens the same
## issue tracker the Help menu's own Report row does.
##
## The address is `SaHelpMenu.REPORT_URL` read from the constant rather than
## typed out here, so the page and the menu cannot come to name two places, and
## the paragraph is the words a painter needs: what the recorder is, which row
## opens it, where the zip lands and where to send it.
func _build_ask() -> VBoxContainer:
    var block := SaMake.column(null, ASK_BLOCK, 6)
    _ask_label = SaSettingsRows.note(block, _ask_text())
    _ask_label.name = ASK_PARAGRAPH

    var row := SaMake.row(block, "NewsAskRow")
    var report_tip := tr("Opens the issue tracker of Sara's repository in your browser.")
    _report_button = SaMake.button(row, ASK_BUTTON, tr("Report a Problem"), report_tip)
    _report_button.pressed.connect(_on_report_pressed)

    # So the button keeps its own width rather than being stretched across the
    # pane, which is wider than a button drawn for it alone should be.
    var spacer := Control.new()
    spacer.name = "NewsAskSpacer"
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spacer)
    return block


## The feedback request's words, with the menu's own address in them.
##
## One sentence per `tr()`, joined at the end: the formatter's 130 columns hold
## no whole paragraph in one literal, and a wrapped string constant would put
## its newlines on screen where the label's own wrapping should decide.
##
## Not static, because `tr()` cannot be called from a static function, and a
## sentence each is what lets the one naming the address stay a `tr()` as well.
func _ask_text() -> String:
    var sentences: Array[String] = [
        tr("Take a Note, under Help, opens the note recorder over the canvas."),
        tr("Its Export button writes this session's notes and pictures into a zip and tells you the path."),
        tr("The zip also holds Sara's own log of this session and the one before it, which is what shows a crash."),
        tr("Send that zip to %s so what you found reaches the people who read it.") % SaHelpMenu.REPORT_URL,
    ]
    return " ".join(sentences)


## The one call that leaves Sara, through the seam so a suite can make it.
func _on_report_pressed() -> void:
    opener.call(SaHelpMenu.REPORT_URL)


## What the pane is showing, as a dictionary a dump, a proof or a test reads.
##
## Keys: `source` (`build`, `checkout` or `none`), `notes` (the language
## module's notes file, or `""`), `running`, `last_seen`,
## `sections` (the versions on screen, newest first) and `already_installed`,
## which is true when the running version's own section stands in for there
## being nothing newer.
func report() -> Dictionary:
    var found := _read()
    var shown := report_for(found["sections"], SaBuildInfo.version(), SaSettings.last_version_seen)
    shown["source"] = found["source"]
    shown["notes"] = found["notes"]
    shown["running"] = SaBuildInfo.version()
    shown["last_seen"] = SaSettings.last_version_seen
    return shown


## The versions a pane shows for a running version and a last-seen one, and
## whether the newest of them is the running version saying so.
##
## The pure half, so a test drives the three settings values without a file or a
## window to put one in. `all` is newest first, the order `SaChangelog` hands
## back, and the rule is the feedback request's: the sections newer than the one last seen,
## and when there are none, the running version's section alone.
static func report_for(all: Array, running: String, last_seen: String) -> Dictionary:
    var newer := SaChangelog.newer_than(all, last_seen)
    if not newer.is_empty():
        return {"sections": _versions(newer), "already_installed": false}
    var own := _own(all, running)
    return {"sections": _versions(own), "already_installed": not own.is_empty()}


## Draws the sections the report names, newest first, and writes the feedback request's
## paragraph again, both in the language in force.
##
## Every child is taken out at once and freed at the end of the frame, the way
## `WelcomeRecentGrid.rebuild` does it: the press that asked for this redraw may
## still be being handled by a control on one of them.
func rebuild() -> void:
    if _ask_label != null:
        _ask_label.text = _ask_text()
    _built_for = _reading()
    for child in _sections.get_children():
        _sections.remove_child(child)
        child.queue_free()

    var found := _read()
    var shown := report_for(found["sections"], SaBuildInfo.version(), SaSettings.last_version_seen)
    if shown["sections"].is_empty():
        SaSettingsRows.note(_sections, tr("This build carries no release notes."))
        return
    if shown["already_installed"]:
        SaSettingsRows.note(_sections, tr("This is the version already installed."))

    var by_version := {}
    for section: Dictionary in found["sections"]:
        by_version[str(section["version"])] = section
    for version: String in shown["sections"]:
        if not by_version.has(version):
            continue
        var rows := SaSettingsRows.section(_sections, heading(version))
        for line: Variant in (by_version[version] as Dictionary)["lines"]:
            SaSettingsRows.note(rows, String(line))


## A section's heading as the pane writes it: the version, or the open
## section's word in the painter's language, which the file writes in English.
func heading(version: String) -> String:
    return tr("Unreleased") if SaChangelog.is_open(version) else version


## Puts the pane in front, the way `WelcomeQuickSettingsPane.reveal` does: the
## shot a scenario takes has to have the pane in it rather than whichever tab
## was last looked at.
func reveal() -> void:
    var tab := SaWelcomeWindow.tab_of(self)
    var tabs := tab.get_parent() as TabContainer
    if tabs != null:
        tabs.current_tab = tabs.get_tab_idx_from_control(tab)


## Reads the news pane: the pane's door for a scenario, reached through the
## `{"news":...}` step.
##
## `{"news": {"tab": true}}` brings the pane to the front, which is also what
## marks it seen, and the report is printed either way, so a scenario can read
## the pane without a shot and take a shot without a report.
static func capture_pane(root: Node, spec: Dictionary) -> String:
    var pane := root.find_child("News", true, false)
    if pane == null or not pane.has_method("report"):
        return "SaCapture: the welcome window is not open"
    if bool(spec.get("tab", true)):
        pane.reveal()
    return pane.capture_line()


## The pane's own line for the console: which file answered, whose notes in
## which language, which version the painter is on, what the pane drew from it and what the feedback request above it says.
##
## A version list rather than a count, because the claim is which sections show
## and in which order, and a count is the same number for a wrong set.
func capture_line() -> String:
    var shown := report()
    return (
        "SaCapture: news pane source %s, notes %s, running %s, last seen %s, already installed %s, showing %s, ask %s, first %s"
        % [
            shown["source"],
            shown["notes"] if shown["notes"] != "" else "english",
            shown["running"],
            shown["last_seen"],
            shown["already_installed"],
            str(shown["sections"]),
            ask_line(),
            first_line(),
        ]
    )


## The newest section as it is drawn, its heading and its first line read off
## the labels on screen, so a run in another language shows in the log whether
## the notes and the open section's word followed it. `none` with no section.
func first_line() -> String:
    for block: Node in _sections.get_children():
        var title := block.find_child("Heading", true, false) as Label
        var rows := block.find_child("Rows", true, false)
        if title == null or rows == null or rows.get_child_count() == 0:
            continue
        return "%s: %s" % [title.text, (rows.get_child(0) as Label).text]
    return "none"


## The feedback request as the console reads it, quoted rather than summarised.
##
## The paragraph's whole text, because the claim a dump has to carry is which
## words are on screen: the two sentences naming Take a Note and Export, and
## the address the menu's own Report row opens. `none` for a pane built without
## the feedback request, which nothing in the app builds and a test could.
func ask_line() -> String:
    if _ask_label == null or _report_button == null:
        return "none"
    return "%s | %s" % [_ask_label.text, _report_button.text]


static func _versions(sections: Array) -> Array:
    var out: Array = []
    for section: Dictionary in sections:
        out.append(str(section["version"]))
    return out


## The running version's own section, or nothing when the build carries none.
static func _own(all: Array, running: String) -> Array:
    var out: Array = []
    for section: Dictionary in all:
        if str(section["version"]) == running:
            out.append(section)
    return out
