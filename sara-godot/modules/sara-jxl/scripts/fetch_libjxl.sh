#!/bin/bash
# Fetches libjxl with the three libraries it bundles (skcms, highway
# and brotli) and applies every patch in `patches/`, ready for the module's
# CMakeLists.txt to build it statically into the module. Nothing is built
# here, so the same source serves Linux and Windows. Each patch but two is a
# speed-up that leaves every stream byte for byte libjxl's own
# (`results/jxl-speedups.md` on the main branch). `effort7-switches.patch`
# lets effort 8 take some of effort 7's choices back, and `lean-fixed.patch`
# fixes which ones when the build names them.
#
# Usage: fetch_libjxl.sh DIR  (the source goes to DIR, which must not exist)
set -eu

# The one place the libjxl release is named. The pin stays, because a build
# that follows a branch changes under the module without a commit saying so.
# To move it, set LIBJXL_TAG to a tag of LIBJXL_URL, run the script into an
# empty folder and read that every patch in `patches/` still applies, then
# build and run the module's suites, since a patch is made against one release.
LIBJXL_URL=https://github.com/libjxl/libjxl.git
LIBJXL_TAG=v0.12.0

dir=$1
here=$(dirname "$(realpath "$0")")
git -c advice.detachedHead=false clone -q --depth 1 --branch "$LIBJXL_TAG" "$LIBJXL_URL" "$dir"
git -C "$dir" submodule update -q --init --depth 1 third_party/skcms third_party/highway third_party/brotli
for p in "$here"/../patches/*.patch; do
    git -C "$dir" apply "$p"
done
