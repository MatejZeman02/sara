## Android's picker turns the `.sad` filter into
## `application/octet-stream`, so it neither shows nor adds the extension, and a
## Downloads address carries no name at all. Appending `.sad` to the address it
## answered named a document that did not exist, and the save failed with an
## empty file left behind. The address is kept as the picker made it, and a
## desktop path typed without the extension still gains it.
extends "res://tests/test_framework.gd"

const _SAD: PackedStringArray = ["*.sad ; Sara Document"]
const _BARE: String = "content://com.android.externalstorage.documents/document/primary%3APictures%2Fh3404-bare"
const _NAMED: String = "content://com.android.externalstorage.documents/document/primary%3APictures%2Fh3404.sad"
const _DOWNLOADS: String = "content://com.android.providers.downloads.documents/document/msf%3A1234"


func test_a_content_address_without_sad_is_answered_unchanged() -> void:
    var picker := SaFilePicker.new(null, SaFilePicker.Mode.SAVE_FILE, _SAD, Callable(), "", Callable())
    assert_eq(picker.with_extension(_BARE, 0), _BARE, "a bare name the picker made gains no .sad")
    assert_eq(picker.with_extension(_DOWNLOADS, 0), _DOWNLOADS, "a Downloads address with no name is kept")
    assert_eq(picker.with_extension(_BARE, 1), _BARE, "and All Files keeps it as well")


func test_a_content_address_with_sad_is_answered_unchanged() -> void:
    var picker := SaFilePicker.new(null, SaFilePicker.Mode.SAVE_FILE, _SAD, Callable(), "", Callable())
    assert_eq(picker.with_extension(_NAMED, 0), _NAMED, "an address ending in .sad is kept")


func test_a_content_address_is_kept_under_several_filters() -> void:
    var filters := PackedStringArray(["*.png ; PNG", "*.jpg, *.jpeg ; JPEG"])
    var picker := SaFilePicker.new(null, SaFilePicker.Mode.SAVE_FILE, filters, Callable(), "", Callable())
    assert_eq(picker.with_extension(_BARE, 0), _BARE, "All Recognized adds nothing to an address")
    assert_eq(picker.with_extension(_BARE, 2), _BARE, "nor does a filter chosen")


func test_a_desktop_path_without_sad_still_gains_it() -> void:
    var picker := SaFilePicker.new(null, SaFilePicker.Mode.SAVE_FILE, _SAD, Callable(), "", Callable())
    assert_eq(picker.with_extension("/home/painter/h3404-bare", 0), "/home/painter/h3404-bare.sad", "a plain path gains .sad")
    assert_eq(picker.with_extension("/home/painter/h3404.sad", 0), "/home/painter/h3404.sad", "and one that has it is kept")
