## The profile on disk: where it is, what version it is, reading it, writing it,
## and putting it back to defaults.
##
## The one door to the settings file. `SaSettingsValues` holds the preferences
## and knows nothing about storage, this holds the storage and knows the values
## only through [constant SaSettingsValues.KEYS], and the migrations run behind
## this door on their way in. The same job was once a three-deep inheritance
## chain with two bags of statics that took the settings node back as an
## argument, and the section and key of every preference were written out four
## times over.
##
## **It holds no layout, no node and no values**. The values are handed to the
## call that reads into them or resets them, and a moved preference is handed to
## [method write] by the autoload. It announces a read and a reset on its own two
## signals, and `SaSettingsLayout` hears them and reads or empties its own three
## sections of [member config]. It needs no node to translate, because
## `TranslationServer.translate` answers without one. The statics that say where
## the profile is are this class's too, because the one place they are named is
## the door to the file.
##
## **A write follows the value rather than leading it.** The values object says
## which preference moved and this writes it, rather than every setter calling
## `config.set_value` and `save_settings` itself, so a preference that clamps or
## refuses a change writes nothing and no setter has to remember the file exists.
##
## `@tool` because the autoload that holds it is.
@tool
class_name SaSettingsFile
extends RefCounted

## A profile was read, after its migrations and after every preference: the
## reorderable layout reads its own sections of [member config] on this.
signal read

## The profile went back to defaults, on a first launch or a reset: the
## layout empties its dictionaries and its sections of [member config].
signal cleared

const SETTINGS_FILE := "settings.cfg"

## Bumped when a stored value changes meaning, so a load can migrate it. Lives
## on the migrations, which are the only thing that reads a stored version, and
## is aliased here and on `SaSettings` under the name callers already type.
const SETTINGS_VERSION: int = SaSettingsMigrations.SETTINGS_VERSION

## The ladder's siblings of the profile, the previous version and the one that
## failed to parse, here under the names callers already type.
const BACKUP_SUFFIX := SaConfigLadder.BACKUP_SUFFIX
const BROKEN_SUFFIX := SaConfigLadder.BROKEN_SUFFIX
## What every module's own section is called before its id:
## `module.sara-base-modules`. A prefix no skeleton section starts with, so a
## reset can find every module's section without a list of the modules.
const MODULE_SECTION_PREFIX := "module."

## The folder name under the platform's configuration directory, and the
## pointer file a folder chosen in Preferences is recorded in. The flag that
## overrides both is read by `SaDataRoot`, because it moves the painter's data
## folder as well, and a run with it keeps the pointer file in
## the flag's folder, see [method pointer_path].
const DIR_NAME := "sara"
const LOCATION_FILE := "location.cfg"

## The parsed profile. Read by `SaSettingsLayout` for the three layout sections
## and by the suites, which is why it is not private.
var config := ConfigFile.new()

## Where the profile is. Written from outside exactly once, by the test runner,
## which points every suite at a scratch file rather than the painter's own.
var settings_path: String

## True while [method load_from_disk] is walking the keys. Every key it reads is
## written back into `config`, because a migration writes a value through the
## values object and the read a few lines later has to find it, but the disk is
## touched once at the end rather than once per key, which would save the whole
## profile once for every key it reads.
var _loading := false


## Where the settings file and the docker layout live: the flag first, then
## the folder a pointer names, then the platform default.
static func directory() -> String:
    var from_flag := SaDataRoot.flag()
    if not from_flag.is_empty():
        return from_flag
    var chosen := read_pointer()
    if not chosen.is_empty():
        return chosen
    return platform_default()


## Where the pointer file is: inside the flag's folder in a run with
## `--settings-dir`, and in the platform default folder in a run without.
## **The flag is never followed to the painter's own pointer.** A scenario that
## moves the Files page's folder row once wrote its test folder into the
## painter's `location.cfg`, and the installed Sara read its settings from that
## folder at its defaults from the next launch on. So a run with the flag keeps
## its pointer beside its own settings, where the row still takes effect for
## whoever reads it back, and a pointer is a thing written per run and never per
## machine. `flag_dir` is the run's flag, handed in only by the suite, which has
## to reach the no-flag path from a process that carries one.
static func pointer_path(flag_dir: String = SaDataRoot.flag()) -> String:
    if flag_dir.is_empty():
        return platform_default().path_join(LOCATION_FILE)
    return flag_dir.path_join(LOCATION_FILE)


## The folder a painter chose through Preferences, or "" when none was.
static func read_pointer(flag_dir: String = SaDataRoot.flag()) -> String:
    var pointer_file := pointer_path(flag_dir)
    if not FileAccess.file_exists(pointer_file):
        return ""
    var file := FileAccess.open(pointer_file, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text().strip_edges()


## Writes or clears the pointer [method directory] reads. Never moves the
## previous folder's contents: Preferences says a restart is needed because
## this process has already loaded its settings from the old one. See
## [method pointer_path] for which file this is in a run with the flag.
static func set_pointer(path: String, flag_dir: String = SaDataRoot.flag()) -> void:
    var pointer_file := pointer_path(flag_dir)
    if path.is_empty():
        if FileAccess.file_exists(pointer_file):
            DirAccess.remove_absolute(pointer_file)
        return
    var folder := pointer_file.get_base_dir()
    if not DirAccess.dir_exists_absolute(folder):
        DirAccess.make_dir_recursive_absolute(folder)
    var file := FileAccess.open(pointer_file, FileAccess.WRITE)
    file.store_string(path)


## The platform-specific settings directory before any pointer or flag.
static func platform_default() -> String:
    match OS.get_name():
        "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
            var xdg := OS.get_environment("XDG_CONFIG_HOME")
            if xdg.is_empty():
                var home := OS.get_environment("HOME")
                if home.is_empty():
                    return OS.get_user_data_dir()
                xdg = home.path_join(".config")
            return xdg.path_join(DIR_NAME)
        "Windows":
            var appdata := OS.get_environment("APPDATA")
            if appdata.is_empty():
                return OS.get_user_data_dir()
            return appdata.path_join(DIR_NAME)
        "macOS":
            var home := OS.get_environment("HOME")
            if home.is_empty():
                return OS.get_user_data_dir()
            return home.path_join("Library/Application Support").path_join(DIR_NAME)
        _:
            return OS.get_user_data_dir()


## Reads the profile, migrating it first when it was written by an older build.
##
## **The migrations run before any key is read**, which is the one thing about
## the order that matters: they rewrite the config and nothing else, so a value
## a migration carries over is simply what the read a moment later finds, and no
## step has to say which side of the read it is on.
func load_from_disk(values: SaSettingsValues) -> void:
    var dir := DirAccess.open(directory())
    if dir == null:
        DirAccess.make_dir_recursive_absolute(directory())

    if _load_profile() != OK:
        _write_first_launch_defaults(values)
        return

    _loading = true
    var stored_version: int = config.get_value("meta", "version", 1)
    if stored_version < SETTINGS_VERSION:
        SaSettingsMigrations.apply(config, stored_version)
    var fresh := SaSettingsValues.new()
    for property: String in SaSettingsValues.KEYS:
        var place: Array = SaSettingsValues.KEYS[property]
        var section: String = place[0]
        var key: String = place[1]
        values.set(property, config.get_value(section, key, fresh.stored(property)))
    fresh.free()
    read.emit()
    _loading = false
    save()


## A first launch: no profile, or one that could not be recovered, so the file
## is written from the defaults every property already holds.
func _write_first_launch_defaults(values: SaSettingsValues) -> void:
    _loading = true
    values.restore_defaults()
    cleared.emit()
    _stamp_version()
    _loading = false
    save()


## Marks a profile as written by this build, which is what a first launch and a
## reset both write.
##
## Without it a first launch wrote a file with no `meta` section at all, so the
## launch after it read `stored_version` 1 and ran every migration, and the
## version-2 step exists to reset `ui/scale` because that key changed meaning.
## A painter set the interface to 125 per cent, quit, and came back to 100 with
## the file still saying 1.25. The launch after that was right again, the
## migration having stamped the file on its way out, so it read as Sara
## forgetting a setting once rather than as a bug.
##
## Not in [method save], which is where it looks as though it belongs: a stamp
## there would mark an old profile current partway through the load it is being
## migrated by, and a process that died in between would never migrate it.
func _stamp_version() -> void:
    config.set_value("meta", "version", SETTINGS_VERSION)


## Loads the profile, or the backup when the profile is unreadable, or nothing.
##
## `ConfigFile.load` fails identically for a missing file and a truncated one,
## and writing defaults straight over both before the window appears would lose
## a profile a repair could have saved. So a profile that exists but does not
## parse is first moved aside as `settings.cfg.broken`, then the backup the last
## save kept is tried, and either way the painter is told rather than shown a
## fresh profile with no explanation.
##
## A fresh object first, because `ConfigFile.load` merges into what it holds
## and the save at the end of a load then writes the union. A suite that
## pointed the path at its own file and back handed its own sections to the
## run's shared profile that way, for every suite after it to read.
func _load_profile() -> Error:
    var ladder := SaConfigLadder.new(settings_path)
    config = ladder.config
    match ladder.outcome:
        SaConfigLadder.Outcome.READ:
            return OK
        SaConfigLadder.Outcome.MISSING:
            return ERR_FILE_NOT_FOUND
        SaConfigLadder.Outcome.RESTORED:
            # Written back at once, or the next launch finds no profile and
            # writes defaults over the version that was just recovered.
            save()
            SaProblems.report(
                "SaSettings",
                (
                    TranslationServer.translate(
                        "Preferences could not be read (%s). The previous version was restored, the unreadable file is at %s."
                    )
                    % [error_string(ladder.error), ladder.broken_path]
                )
            )
            return OK
    SaProblems.report(
        "SaSettings",
        (
            TranslationServer.translate("Preferences could not be read (%s). Defaults are in use, the unreadable file is at %s.")
            % [error_string(ladder.error), ladder.broken_path]
        )
    )
    return ladder.error


## Writes the profile, keeping the previous file as the backup.
##
## Written to a sibling first and renamed over the destination, so a save that
## fails part way leaves the profile that was there rather than half of a new
## one, which is the file [method _load_profile] would then have to refuse.
func save() -> void:
    var err: Error = SaConfigLadder.write(config, settings_path)
    if err != OK:
        SaProblems.report("SaSettings", TranslationServer.translate("Preferences could not be saved (%s).") % error_string(err))


## Puts every preference back to its default and empties the stored layout.
func reset(values: SaSettingsValues) -> void:
    _loading = true
    values.restore_defaults()
    values.recent_file_paths = []
    values.store_recent_files()
    cleared.emit()
    # A module's preferences are the profile's as much as the skeleton's are,
    # so a reset forgets them too.
    for section: String in config.get_sections():
        if section.begins_with(MODULE_SECTION_PREFIX):
            config.erase_section(section)

    _stamp_version()
    _loading = false
    save()
    values.profile_changed.emit()


## One preference moved to *value*, what the values object stores for it, so
## its key is written and the profile saved.
func write(property: StringName, value: Variant) -> void:
    var place := SaSettingsValues.place_of(property)
    if place.is_empty():
        return
    var section: String = place[0]
    var key: String = place[1]
    config.set_value(section, key, value)
    if not _loading:
        save()


## The section *module_id*'s preferences are kept under.
static func module_section(module_id: StringName) -> String:
    return MODULE_SECTION_PREFIX + String(module_id)


## A module's stored preference, or *default* when the profile holds none.
##
## *formerly*, `[section, key]`, is where the skeleton kept the value before a
## module took it over. A value still there is moved under the module's
## section, unless the module already holds one, and the old key is erased and
## the profile saved, so it is read there once. Nothing else drops a key the
## skeleton does not list: a load reads the whole file into [member config]
## and a save writes it back, so the old key waits for the module.
func module_value(module_id: StringName, key: StringName, default: Variant = null, formerly: Array = []) -> Variant:
    var section := module_section(module_id)
    var old_section: String = str(formerly[0]) if formerly.size() == 2 else ""
    var old_key: String = str(formerly[1]) if formerly.size() == 2 else ""
    if formerly.size() == 2 and config.has_section_key(old_section, old_key):
        if not config.has_section_key(section, String(key)):
            config.set_value(section, String(key), config.get_value(old_section, old_key))
        config.erase_section_key(old_section, old_key)
        if not _loading:
            save()
    return config.get_value(section, String(key), default)


## Stores a module's preference and saves the profile, unless the value is the
## one already stored. A null forgets the key. True when it wrote.
##
## Beside the values rather than among them, because a module's key is not a
## property the skeleton declares: it clamps nothing and knows no default, so
## the module that reads the value is the one that decides what it may be.
func set_module_value(module_id: StringName, key: StringName, value: Variant) -> bool:
    var section := module_section(module_id)
    var name := String(key)
    var held := config.has_section_key(section, name)
    if value == null:
        # A null is how a module forgets a key. `set_value` would erase it too,
        # and asking first keeps a key that was never written from being an
        # error rather than a no-op.
        if not held:
            return false
        config.erase_section_key(section, name)
    else:
        var stored: Variant = config.get_value(section, name) if held else null
        if held and typeof(stored) == typeof(value) and stored == value:
            return false
        config.set_value(section, name, value)
    if not _loading:
        save()
    return true
