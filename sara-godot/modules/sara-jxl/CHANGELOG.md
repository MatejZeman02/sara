# Changelog

What changed in the JPEG XL module, by version. Each release reads the section of the
version the `manifest.cfg` carries, and refuses a release with no such section.

## 1.0.0-alpha.1

A `manifest.cfg` says what the module is and its version, which Sara reads before any of its code, and the versions move with each release from here on.
The module extends `SaModule`, the base class's new name.

## 0.19.1

File > Save as JPEG XL as Sara 0.19.1 shipped it, each field of each chunk a lossless JPEG XL codestream.
