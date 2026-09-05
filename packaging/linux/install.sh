#!/bin/sh
# Install the desktop integration: the desktop entry and the icon, and the
# executable with its models beside it. For a person installing by hand and
# for testing the entry without building a package. The Excelano apt
# repository ships the same files from `packaging/debian`, and the two must
# agree about where things go.
#
# The layout under PREFIX/lib/duckling is the one the package uses, because
# the application finds its models beside its own executable (src/lib.rs,
# `locate_assets`): the real binary sits there with `models/` and `pdfium/`,
# and PREFIX/bin/duckling is a symlink to it.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "${here}/../.." && pwd)
prefix="${HOME}/.local"
binaries=""
target_dir=""

usage() {
    cat <<'USAGE'
usage: install.sh [--prefix DIR] [--target-dir DIR] [--no-binary]

  --prefix DIR      where to install (default: ~/.local; use /usr/local for all users)
  --target-dir DIR  the Cargo target directory to take the executable from
  --no-binary       install the desktop entry and icon only

Without --no-binary, duckling is looked for under the target directory,
release before debug, and installed with the models under PREFIX/lib/duckling
and a symlink at PREFIX/bin/duckling.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
        --target-dir) target_dir="${2:?--target-dir needs a directory}"; shift 2 ;;
        --no-binary) binaries="none"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$binaries" != "none" ]; then
    if [ -z "$target_dir" ] && command -v cargo >/dev/null 2>&1; then
        target_dir=$(cd "$root" && cargo metadata --format-version 1 --no-deps 2>/dev/null |
            sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')
    fi
    [ -n "$target_dir" ] || target_dir="${root}/target"
fi

mkdir -p "${prefix}/share/applications" "${prefix}/share/icons/hicolor/scalable/apps"
install -m 0644 "${here}/duckling.desktop" "${prefix}/share/applications/duckling.desktop"
install -m 0644 "${here}/icons/duckling.svg" "${prefix}/share/icons/hicolor/scalable/apps/duckling.svg"

if [ "$binaries" != "none" ]; then
    found=""
    for candidate in "${target_dir}/release/duckling" "${target_dir}/debug/duckling"; do
        if [ -x "$candidate" ]; then found="$candidate"; break; fi
    done
    if [ -n "$found" ]; then
        [ -d "${root}/.models" ] && [ -d "${root}/.pdfium/lib" ] || {
            echo "install.sh: no models under ${root}; run packaging/fetch-models.sh first" >&2
            exit 1
        }
        lib="${prefix}/lib/duckling"
        rm -rf "${lib}/models" "${lib}/pdfium"
        mkdir -p "${lib}/models" "${lib}/pdfium" "${prefix}/bin"
        install -m 0755 "$found" "${lib}/duckling"
        cp -R "${root}/.models/." "${lib}/models/"
        cp "${root}/.pdfium/lib/"* "${lib}/pdfium/"
        find "${lib}/models" "${lib}/pdfium" -type f -exec chmod 0644 {} +
        find "${lib}/models" "${lib}/pdfium" -type d -exec chmod 0755 {} +
        ln -sfn "${lib}/duckling" "${prefix}/bin/duckling"
        echo "installed ${lib}/duckling from ${found}, with the models beside it"
    else
        echo "no duckling under ${target_dir}; it must be on PATH for the entry to work"
        echo "  (GLib drops a desktop entry whose Exec it cannot find, so until it is," \
             "the entry is not registered and the file manager offers nothing)"
    fi
fi

[ -x "$(command -v update-desktop-database || true)" ] &&
    update-desktop-database "${prefix}/share/applications" || true
[ -x "$(command -v gtk-update-icon-cache || true)" ] &&
    gtk-update-icon-cache -q -t -f "${prefix}/share/icons/hicolor" || true

echo "installed the Duckling desktop entry and icon under ${prefix}"
echo
echo "check it with:"
echo "  gio mime application/pdf    # lists duckling.desktop among the handlers"
