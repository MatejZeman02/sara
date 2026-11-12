## The base a Preferences page extends to be declared rather than built, the
## `extends SaSettingsPage` of the declarative page API's worked example.
##
## A page overrides [method build] and appends rows to the `SaPage` it is
## handed, and this class does the rest: it declares and realizes in `_init`,
## so the page is whole the moment `new()` returns, and it re-reads every
## binding in `_ready`, which is the re-read on open that declared pages need. The
## first half is not a preference. The search builds every page off the tree
## and frees it (`settings_search.gd`), and `ui/settings/tests/test_settings_pages.gd`
## walks a page the window built with no tree, so a page that waited for
## `_ready` to draw would answer both with nothing.
##
## Two rules follow from how GDScript runs a constructor, probed on 4.7.stable:
##
## - **A page with an `_init` of its own sets its fields and then calls
##   `super()`.** A child that writes an `_init` and never calls `super()` does
##   not run this one at all, so the page is never drawn, and a child that
##   calls `super()` first has its fields still unset while `build` reads them.
## - **A page with a `_ready` of its own calls `super()` in it**, or the page
##   stops re-reading its bindings when it opens.
##
## The page is held in a plain member and never through a bound `Callable`.
## `SaPage` is `RefCounted`, so a callable the page keeps that carries the page
## as a bound argument, `page.declare = f.bind(page)` for one, is a page that
## holds itself and is never collected, a few hundred objects left behind for
## every few dozen pages opened. The declaration is the one `Callable` the page
## keeps, and it points at this node with nothing bound, which counts no
## reference. A signal connected to this node with the page bound is not the
## same trap, because freeing the node drops the connection.
class_name SaSettingsPage
extends VBoxContainer

## What the dump's `pages` block keys this page by. Every settings page answers
## the same name, because only one is open at a time and a scenario has to be
## able to write the key down before the page exists.
const NODE_NAME := &"SettingsPage"

## The declared page, written once by this class in `_init`.
var page: SaPage = null


func _init() -> void:
    name = NODE_NAME
    page = SaPage.new(build)
    page.declare_rows()
    page.realize(self)


func _ready() -> void:
    page.refresh()


## What a page overrides: its sections and rows, appended to *_ui*. Runs once in
## `_init`, and again only when the page asks for `page.rebuild()`.
func build(_ui: SaPage) -> void:
    pass
