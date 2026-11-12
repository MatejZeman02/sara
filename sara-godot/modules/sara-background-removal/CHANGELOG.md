# Changelog

What changed in background removal, by version. Each release reads the section of the
version the `manifest.cfg` carries, and refuses a release with no such section.

## 1.0.0-alpha.1

A `manifest.cfg` says what the module is, its version and that it needs the base modules at 1.0.0-alpha.1 or newer, which Sara reads before any of its code, and the versions move with each release from here on.
The module extends `SaModule`, the base class's new name.
A weights download whose line stalls no longer freezes Sara when it is cancelled or times out, because the request runs without a thread of its own.

## 0.19.1

Select Subject and Object Selection as Sara 0.19.1 shipped them.
