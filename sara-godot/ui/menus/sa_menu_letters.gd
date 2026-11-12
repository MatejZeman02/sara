## Which letter of each menu row is underlined, picked by a rule over the row's
## own words, so that no row carries a letter written for it by hand.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A row's underlined letter runs its action when pressed. Blender's menus are
## the model,
## read from its behaviour and its manual and not its code: a menu row's letter
## is the first letter of one of its words where that letter is still free, and
## only when no word's first letter is free any letter of the row is taken. The
## rule here is that one with three choices of Sara's own.
##
## **Words first, letters after, over the whole menu.** Every row tries the
## first letters of its words before any row falls back to a letter inside a
## word, so a late row's initial is not taken by an early row's inner letter.
## That is Blender's order, and the reason is the one a painter reads: a letter
## at the start of a word is the one an eye finds.
##
## **A small word goes after the others.** "New Layer" is underlined at L and
## not at N, a guess at what Blender does: a word a run of rows
## begins with, or a word that carries no meaning of its own, says nothing about
## which row it is. The word is not dropped, so a row named "New" alone, or one
## whose other initials are taken, still has it.
##
## **The menu's own rows before what arrives while Sara runs.** A row a menu
## lists in its source is lettered first, and then the rest, a module's action,
## a docker, a recent file, a filter. Without the two tiers a recent file named
## "sketch" took S from Save on the next open, and a module that added an action
## moved the letters of the Develop rows under it. With them, a row that arrives
## takes a letter nobody holds and every other row keeps its own.
class_name SaMenuLetters
extends RefCounted

## The words that give their letter only after every other word of the row has
## been tried. English, because they are the words of Sara's own labels: under
## another language none of them is found and every word counts the same, which
## is the rule still working rather than a wrong letter.
const SMALL_WORDS: Array[String] = [
    "a",
    "an",
    "and",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "into",
    "new",
    "of",
    "on",
    "or",
    "the",
    "to",
    "with",
]


## The letter of each row, as row id -> index into its label, or no entry for a
## row no free letter is left for.
##
## *rows* is `[row id, label, first]` per row, in the order the menu draws them,
## where *first* marks a row of the menu's own list. A letter is compared folded,
## so `A` and `a` are one letter, and a row is never given a letter another row
## of the same *rows* holds.
static func pick(rows: Array) -> Dictionary:
    var given: Dictionary = {}
    var taken: Dictionary = {}
    for tier: bool in [true, false]:
        var tier_rows := rows.filter(func(row: Array) -> bool: return bool(row[2]) == tier)
        for pass_of: Callable in [_plain_initials, _small_initials, _any_letter]:
            for row: Array in tier_rows:
                if given.has(row[0]):
                    continue
                for at: int in pass_of.call(String(row[1])):
                    var letter := String(row[1])[at].to_lower()
                    if not taken.has(letter):
                        taken[letter] = true
                        given[row[0]] = at
                        break
    return given


## The words of *label* as `[start, word]`, a word being a run of letters and
## digits. What follows an open bracket is a chord written into the label, such
## as "Cut (Ctrl+X)", and is not a word of the row's.
static func words(label: String) -> Array:
    var out: Array = []
    var start := -1
    for at in label.length() + 1:
        var inside := at < label.length() and _is_word_char(label[at])
        if inside and start < 0:
            start = at
        elif not inside and start >= 0:
            out.append([start, label.substr(start, at - start)])
            start = -1
        if at < label.length() and label[at] == "(":
            break
    return out


## The starts of the words that are not small, in order.
static func _plain_initials(label: String) -> Array:
    var plain := words(label).filter(func(word: Array) -> bool: return not _small(word[1]))
    return plain.map(func(word: Array) -> int: return word[0])


## The starts of the small words, in order.
static func _small_initials(label: String) -> Array:
    return words(label).filter(func(word: Array) -> bool: return _small(word[1])).map(func(word: Array) -> int: return word[0])


## Every letter of every word, in order, the last thing tried.
static func _any_letter(label: String) -> Array:
    var out: Array = []
    for word: Array in words(label):
        for offset in String(word[1]).length():
            out.append(int(word[0]) + offset)
    return out


static func _small(word: String) -> bool:
    return SMALL_WORDS.has(word.to_lower())


## Whether *character* can be a row's letter: a letter or a digit, which a key
## types, and not a mark or a space, which no painter reads as one.
static func _is_word_char(character: String) -> bool:
    return character.to_lower() != character.to_upper() or character.is_valid_int()
