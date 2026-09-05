#!/bin/sh
# Build the binary package the Excelano apt repository ships: the executable
# with its models and pdfium beside it under /usr/lib/duckling, a symlink on
# PATH, the desktop entry, the icon, the manual page. One package, `duckling`,
# for one product.
#
# A binary package rather than a source package, assembled from a staging
# tree the way `dpkg-deb` would assemble it from `debian/rules`. The shape is
# slipcase-desktop's through segler's. What is Duckling's own: the models,
# which are most of the package and are arch-independent data living in an
# arch-dependent directory. Debian would split them into a `duckling-data`
# package; one package for one product is the fleet's rule, and /usr/lib is
# where an application's private files may live, so they sit beside the
# executable that finds them there. DESIGN.md §8.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "${here}/../.." && pwd)
target_dir=""
outdir="${root}/dist"

usage() {
    cat <<'USAGE'
usage: build-deb.sh [--target-dir DIR] [--outdir DIR]

  --target-dir DIR  the Cargo target directory holding release/duckling
                    (default: ask cargo)
  --outdir DIR      where to write the .deb (default: ./dist)
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --target-dir) target_dir="${2:?--target-dir needs a directory}"; shift 2 ;;
        --outdir) outdir="${2:?--outdir needs a directory}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "build-deb.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$target_dir" ]; then
    target_dir=$(cd "$root" && cargo metadata --format-version 1 --no-deps |
        sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')
fi
binary="${target_dir}/release/duckling"
[ -x "$binary" ] || {
    echo "build-deb.sh: no executable at $binary — run 'cargo build --release' first" >&2
    exit 1
}

# The models are most of the package. Verified against their pins rather
# than trusted to be there: a package built from a half-fetched directory
# installs and converts no PDF.
"${here}/../fetch-models.sh" >/dev/null || {
    echo "build-deb.sh: the models are missing or do not match their pins" >&2
    exit 1
}

version=$("${here}/../version.sh")
changelog_version=$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "${here}/changelog")
[ "$changelog_version" = "$version" ] || {
    echo "build-deb.sh: the changelog's newest entry is ${changelog_version:-unreadable}," \
         "and Cargo.toml says ${version}" >&2
    echo "build-deb.sh: add an entry to packaging/debian/changelog before building" >&2
    exit 1
}

arch=$(dpkg-architecture -qDEB_HOST_ARCH)
case "$arch" in
    amd64) want=62 ;;
    arm64) want=183 ;;
    *) want="" ;;
esac
magic=$(od -An -tx1 -N4 "$binary" | tr -d ' \n')
[ "$magic" = "7f454c46" ] || { echo "build-deb.sh: $binary is not an ELF executable" >&2; exit 1; }
lo=$(od -An -tu1 -j18 -N1 "$binary" | tr -d ' ')
hi=$(od -An -tu1 -j19 -N1 "$binary" | tr -d ' ')
machine=$((lo + hi * 256))
if [ -n "$want" ] && [ "$machine" != "$want" ]; then
    echo "build-deb.sh: this machine is ${arch}, which wants ELF machine ${want}," \
         "and ${binary} is machine ${machine}" >&2
    exit 1
fi

name="duckling_${version}_${arch}"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
chmod 0755 "$stage"

lib="${stage}/usr/lib/duckling"
mkdir -p \
    "${stage}/DEBIAN" \
    "${stage}/usr/bin" \
    "${lib}/models" \
    "${lib}/pdfium" \
    "${stage}/usr/share/applications" \
    "${stage}/usr/share/icons/hicolor/scalable/apps" \
    "${stage}/usr/share/man/man1" \
    "${stage}/usr/share/doc/duckling" \
    "${stage}/usr/share/lintian/overrides"

install -m 0755 "$binary" "${lib}/duckling"
# `locate_assets` in src/lib.rs canonicalizes the executable's path, so the
# symlink resolves to the directory the models are in.
ln -s ../lib/duckling/duckling "${stage}/usr/bin/duckling"
cp -R "${root}/.models/." "${lib}/models/"
cp "${root}/.pdfium/lib/"* "${lib}/pdfium/"
find "${lib}/models" "${lib}/pdfium" -type f -exec chmod 0644 {} +

install -m 0644 "${here}/../linux/duckling.desktop" \
    "${stage}/usr/share/applications/duckling.desktop"
install -m 0644 "${here}/../linux/icons/duckling.svg" \
    "${stage}/usr/share/icons/hicolor/scalable/apps/duckling.svg"
# DEP-5, because the package carries three licences: ours, the models', and
# pdfium's. MIT is not a Debian common licence, so its text is inline.
install -m 0644 "${here}/copyright" "${stage}/usr/share/doc/duckling/copyright"

# Three tags about what pdfium has compiled into it; the file says why they
# are overridden rather than fixed.
install -m 0644 "${here}/lintian-overrides" "${stage}/usr/share/lintian/overrides/duckling"

gzip -9nc "${here}/changelog" > "${stage}/usr/share/doc/duckling/changelog.gz"
chmod 0644 "${stage}/usr/share/doc/duckling/changelog.gz"

sed "s/@VERSION@/${version}/" "${here}/duckling.1.in" \
    | gzip -9nc > "${stage}/usr/share/man/man1/duckling.1.gz"
chmod 0644 "${stage}/usr/share/man/man1/duckling.1.gz"

# Stripped here rather than by the build profile, so a developer's release
# binary keeps its symbols and only the packaged copy loses them. pdfium
# arrives stripped from its builder; asking again costs nothing.
strip --strip-unneeded "${lib}/duckling" "${lib}/pdfium/"*.so 2>/dev/null || true

find "$stage" -type d -exec chmod 0755 {} +

sed -e "s/@VERSION@/${version}/" -e "s/@ARCH@/${arch}/" \
    -e "s/@SIZE@/$(du -ks "${stage}/usr" | cut -f1)/" \
    "${here}/control.in" > "${stage}/DEBIAN/control"

(
    cd "$stage"
    find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
        | sort -z \
        | xargs -0 --no-run-if-empty md5sum > DEBIAN/md5sums
)
chmod 0644 "${stage}/DEBIAN/md5sums"

mkdir -p "$outdir"
# xz, and the highest level: three quarters of the package is ONNX weights
# that compress by a tenth at best, so the cost is in time and the saving
# is in what every installer downloads.
dpkg-deb --root-owner-group -Zxz -z9 --build "$stage" "${outdir}/${name}.deb" >/dev/null
echo "${outdir}/${name}.deb"

echo
echo "linked at load time:"
objdump -p "$binary" | awk '/NEEDED/ {print "  " $2}'
echo "declared in Depends:"
sed -n 's/^Depends: //p' "${stage}/DEBIAN/control" | tr ',' '\n' | sed 's/^ */  /'
