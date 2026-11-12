## A docker shown under the pointer with a return address, the borrow.
##
## The store already forks a preset on a drag and saves
## the live layout on a hide, so the borrow is a docker shown somewhere with a
## note of where it goes back to. Nothing here binds a chord or reads the
## pointer, which is the summon's, and nothing here writes the file.
##
## Its own class rather than a part of `DockerLayoutStore`, because the address
## book is state the layout never reads. It sits beside the store's cache rather
## than in it, because the cache is the layout and a borrow is not:
## `stored_positions` and every save keep answering the painter's own rectangle
## while the docker is somewhere else, so a workspace preset never learns a
## position the painter did not choose. The store decides where a borrow lands
## and holds the window there through its settle loop, and this keeps where it
## is and where it goes back to. Not `SaDockerBorrow`, which is the summon's
## preferences under `ui/dockers`.
class_name SaBorrowedDockers
extends RefCounted

## Section -> the return address of a docker out on a borrow. Empty means
## nothing is borrowed.
##
## The address is where the docker was when the borrow began, its `position`,
## `size` and `visible`, the `node` it belongs to, `at`, where the borrow put
## it or the painter dragged it since, and `at_size` once the painter sized it
## while it was out. Read it through `any`, `sections`, `node_of`, `has` and `held`.
var _addresses: Dictionary = {}


## Shows *win*, the docker stored under *section*, at *at*, and remembers where
## it was. Lending a docker already out moves it and keeps the first address,
## because that is where the painter left it.
func lend(win: Window, section: String, at: Vector2i) -> void:
    if not _addresses.has(section):
        _addresses[section] = {"node": win, "position": win.position, "size": win.size, "visible": win.visible}
    _addresses[section]["at"] = at
    win.position = at
    win.visible = true


## Puts the docker borrowed under *section* back where the borrow found it,
## position, size and visibility, and forgets the address. A docker that was
## hidden goes back to hidden. Writes nothing, as the borrow wrote nothing.
func give_back(section: String) -> bool:
    if not _addresses.has(section):
        return false
    var address: Dictionary = _addresses[section]
    _addresses.erase(section)
    var win: Window = address["node"] as Window
    if not is_instance_valid(win):
        return true
    win.size = address["size"]
    win.position = address["position"]
    win.visible = address["visible"]
    return true


## Moves the borrow under *section* to where *win* is now, its position and
## its size, because the painter moved or sized the window while it was out.
##
## The settle loop and `reflow_to_host` hold a borrowed docker at `at`, so a
## title drag that did not move `at` was undone on the next settled frame and
## the docker went back under the pointer that summoned it.
## The return address is not touched, so `give_back` still sends the docker
## where the painter left it before the summon. A window at (0, 0) has not been
## placed yet and moves nothing, the rule the store's `save` keeps for the
## layout.
func follow(section: String, win: Window) -> void:
    if win.position != Vector2i():
        _addresses[section]["at"] = win.position
    _addresses[section]["at_size"] = win.size


## Whether the docker stored under *section* is out on a borrow.
func has(section: String) -> bool:
    return _addresses.has(section)


## Where the borrow holds the docker under *section*, *key* being `position` or
## `size`, or null when it holds none and the layout answers. The size is the
## one the docker had when it was summoned until the painter sizes it.
func held(section: String, key: String) -> Variant:
    var address: Dictionary = _addresses.get(section, {})
    if key == "position" and address.has("at"):
        return address["at"]
    if key == "size" and address.has("at_size"):
        return address["at_size"]
    if key == "size" and address.has("size"):
        return address["size"]
    return null


## Whether any docker is out on a borrow.
func any() -> bool:
    return not _addresses.is_empty()


## The sections of the dockers out on a borrow, a copy that stays whole while a
## caller gives them back one by one.
func sections() -> Array:
    return _addresses.keys()


## The docker out on a borrow under *section*, or null when none is or the
## window has gone.
func node_of(section: String) -> Window:
    var node: Variant = _addresses.get(section, {}).get("node")
    return node as Window if is_instance_valid(node) else null


## Forgets every address, for a layout applied whole, which puts every docker
## where it says, a borrowed one included, so no return address is left
## pointing at a layout that is gone.
func forget_all() -> void:
    _addresses.clear()
