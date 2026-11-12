## The hashes a save in the background asks for before its walk, sent to the
## card a share a turn and read back once, so no frame of a Ctrl+S on a deep
## stack records every texture's hash. A large painting asks for 11599, and
## sending them in the frame of the key recorded and drew for 280 ms where a
## frame is to stay under a tenth of a second.
##
## The textures are listed by `SaSadSnapshot.hashed` in the frame of the key,
## [method send] dispatches [member a_turn] of them a turn into their own
## places of `SaSadHash`'s words, and after the last asks for the words, which
## [method read] turns into hashes in a turn of its own. Nothing here asks
## whether the document still stands: the save asks that before its walk, as
## it did when the hashes went out in one frame. An ask that zeroed the words
## between two shares, a save at once or an open, makes [method send] answer
## false, and the save asks again. An export's check of the rounding,
## `SaLiveRounding.InTurns`, sends `SaSadHash`'s other kernel the same way.
class_name SaSadHashShares
extends RefCounted

## The textures whose hashes a turn sends, lowered by a suite so that a small
## document's hashes go out in shares too. The card reads every texel of each,
## and 2000 a turn held the draw of the next frame for 115 to 166 ms on the
## large painting while the card ran them, where a frame is to stay under a
## tenth of a second.
static var a_turn := 500

## The hashes once read, by each texture's resource, empty until then and
## when the words did not hold one for each.
var said: Dictionary[RID, String] = {}
## Whether the words are in, and whether [method read] has read them.
var words_in := false
var is_read := false

var _textures: Array[SaTexture] = []
## The ask's number in `SaSadHash`, -1 when none was opened.
var _ask := -1
var _sent := 0
var _words := PackedByteArray()
## The kernel each share records, the hash unless the ask named another.
var _kernel := SaSadHash.SHADER


## Opens an ask for the hashes of *textures*, which are sent from the next
## turn on, by *kernel*, `SaSadHash`'s hash unless it names the other.
## [method is_open] says whether it could.
func _init(textures: Array[SaTexture], kernel := SaSadHash.SHADER) -> void:
    _textures = textures
    _kernel = kernel
    _ask = SaSadHash.open_shares(textures.size()) if not textures.is_empty() else -1


## Whether the ask was opened, false with no textures or no device.
func is_open() -> bool:
    return _ask >= 0


## Whether every share has gone to the card.
func all_sent() -> bool:
    return _sent >= _textures.size()


## Sends the next share and, after the last, asks for the words. False when
## another ask took the words meanwhile, or the device refused the read.
func send() -> bool:
    var to := mini(_sent + a_turn, _textures.size())
    if not SaSadHash.share(_textures, _sent, to, _ask, _kernel):
        return false
    _sent = to
    return not all_sent() or SaSadHash.ask_shared(_textures.size(), _ask, _words_back) == OK


## Whether another ask zeroed the words since this one opened, so words read
## back may be that ask's and are not trusted.
func superseded() -> bool:
    return _ask != SaSadHash._opened


## Reads the words into [member said] the first time it is called once they
## are in, and answers whether they were read on an earlier turn, so the
## reading has a turn of its own.
func read() -> bool:
    if is_read:
        return true
    if words_in:
        said = SaSadSnapshot.said_in(_textures, _words)
        _words = PackedByteArray()
        is_read = true
    return false


## The device's answer with the words, a method and never a lambda (the
## pitfall "Quitting with a read of the card still owed aborts the engine's
## teardown"). It sends the device nothing.
func _words_back(bytes: PackedByteArray) -> void:
    _words = bytes
    words_in = true
