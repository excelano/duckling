#!/bin/sh
# Assemble the application bundle DESIGN.md §8 describes: the executable, the
# models and pdfium in the places a signed bundle allows them, the property
# list, and the icon. Cloned from slipcase-desktop's script of the same name;
# `README.md` beside this says what is Duckling's own and why.
#
# The bundle is the unit of everything on macOS. A bare executable can draw a
# window, but it has no bundle identifier, Launch Services files it as a
# nameless foreground process, and the sandbox has nothing to attach to.
#
# It signs the bundle when it is given an identity, because the Mac App Store is
# the chosen channel and an unsigned bundle is not a thing that can be tested:
# the App Sandbox is inert until the entitlement is inside a signature, so an
# unsigned bundle carrying `Duckling.entitlements` is not sandboxed and proves
# nothing.
#
#   ./packaging/macos/build-app.sh                        # a plain bundle
#   ./packaging/macos/build-app.sh --sign "Apple Development: ..."
#   ./packaging/macos/build-app.sh --store PROFILE        # what is uploaded
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "${here}/../.." && pwd)
binary=""
outdir="${root}/dist"
# Not on PATH, and README.md says so.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
identity=""
store_profile=""

usage() {
    cat <<'USAGE'
usage: build-app.sh [--binary PATH] [--outdir DIR] [--sign ID] [--store PROFILE]

  --binary PATH  the executable to bundle (default: the Apple silicon
                 release build, which is the only release build there is:
                 no ONNX Runtime exists for an Intel Mac, so

                   MACOSX_DEPLOYMENT_TARGET=13.4 \
                     cargo build --release --target aarch64-apple-darwin

                 is the build a Store bundle is made from, on either kind
                 of Mac)
  --outdir DIR   where to write Duckling.app (default: ./dist)
  --sign ID      sign the finished bundle with this identity and the sandbox
                 entitlements beside this script. `security find-identity -v
                 -p codesigning` lists what this machine holds. An Apple
                 Development identity is enough to test the sandbox; a Store
                 upload needs Apple Distribution.
  --store PROFILE
                 build what the Mac App Store takes: the bundle carrying
                 PROFILE as embedded.provisionprofile, signed for
                 distribution, wrapped by productbuild into the .pkg that is
                 uploaded. Chooses its own identities and refuses rather than
                 producing something subtly wrong. PROFILE is the
                 .provisionprofile downloaded from the developer portal:

                   ./packaging/macos/build-app.sh \
                       --store ~/Downloads/Duckling_Mac_App_Store.provisionprofile
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --binary) binary="${2:?--binary needs a path}"; shift 2 ;;
        --outdir) outdir="${2:?--outdir needs a directory}"; shift 2 ;;
        --sign) identity="${2:?--sign needs an identity}"; shift 2 ;;
        --store) store_profile="${2:?--store needs a .provisionprofile}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "build-app.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
done

# One trap for everything this script makes, set before the first `mktemp` and
# never re-armed: a second `trap ... EXIT` replaces the first rather than
# adding to it, which is how slipcase-desktop's copy once left its temporaries
# behind.
stage=""
store_plist=""
store_ents=""
cleanup() {
    [ -z "$stage" ] || rm -rf "$stage"
    [ -z "$store_plist" ] || rm -f "$store_plist"
    [ -z "$store_ents" ] || rm -f "$store_ents"
}
trap cleanup EXIT INT TERM

# Everything --store needs is checked before anything is built, because the
# failures here are cheap to see now and expensive to see after an upload: a
# profile for the wrong bundle identifier, an expired one, or a certificate this
# machine does not hold all produce a package that assembles perfectly and is
# refused by App Store Connect.
if [ -n "$store_profile" ]; then
    [ -z "$identity" ] || {
        echo "build-app.sh: --store chooses its own identities; drop --sign" >&2
        exit 2
    }
    [ -f "$store_profile" ] || {
        echo "build-app.sh: no provisioning profile at ${store_profile}" >&2
        exit 1
    }

    # The profile is a CMS-signed property list. Decoding it is also the check
    # that it is one.
    store_plist=$(mktemp -t duckling-profile)
    security cms -D -i "$store_profile" > "$store_plist" 2>/dev/null || {
        echo "build-app.sh: ${store_profile} is not a provisioning profile this can read" >&2
        exit 1
    }

    # ISO 8601 rather than PlistBuddy's rendering, which is locale-dependent and
    # would make this check pass or fail by what language the machine is in.
    store_expiry=$(plutil -extract ExpirationDate raw -o - "$store_plist" 2>/dev/null)
    store_expiry_at=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$store_expiry" +%s 2>/dev/null || echo "")
    [ -n "$store_expiry_at" ] || {
        echo "build-app.sh: cannot read the profile's expiry date (${store_expiry:-none})" >&2
        exit 1
    }
    [ "$store_expiry_at" -gt "$(date +%s)" ] || {
        echo "build-app.sh: the profile expired on ${store_expiry}" >&2
        exit 1
    }

    # The team and the application identifier come out of the profile rather
    # than being written down here. The profile is the thing App Store Connect
    # validates against, so it is the only copy that cannot drift.
    store_app_id=$(/usr/libexec/PlistBuddy -c \
        'Print Entitlements:com.apple.application-identifier' "$store_plist" 2>/dev/null || echo "")
    store_team=$(/usr/libexec/PlistBuddy -c \
        'Print Entitlements:com.apple.developer.team-identifier' "$store_plist" 2>/dev/null || echo "")
    [ -n "$store_app_id" ] && [ -n "$store_team" ] || {
        echo "build-app.sh: the profile carries no application-identifier or team-identifier" >&2
        exit 1
    }
fi

# Cargo is asked where its target directory is. `[build] target-dir` in a Cargo
# configuration file moves it and no environment variable then says so.
target_dir=$(cd "$root" && cargo metadata --format-version 1 --no-deps |
    sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')

# The release build is asked for by target on purpose, so that the same path
# holds on an Apple silicon Mac building natively and on an Intel Mac building
# across. There is no `--universal` here and there cannot be: `ort` has no
# prebuilt ONNX Runtime for `x86_64-apple-darwin` and neither does Microsoft
# since 1.28, so the second slice does not exist to join. README.md §1.
if [ -z "$binary" ]; then
    binary="${target_dir}/aarch64-apple-darwin/release/duckling"
fi
[ -x "$binary" ] || {
    echo "build-app.sh: no executable at $binary" >&2
    echo "  MACOSX_DEPLOYMENT_TARGET=13.4 cargo build --release --target aarch64-apple-darwin" >&2
    exit 1
}

# The models are most of the bundle. Verified against their pins rather than
# trusted to be there, the way `build-deb.sh` does: a bundle built from a
# half-fetched directory installs and converts no PDF.
"${here}/../fetch-models.sh" >/dev/null || {
    echo "build-app.sh: the models are missing or do not match their pins" >&2
    exit 1
}
pdfium_src="${root}/.pdfium/lib/libpdfium.dylib"
[ -f "$pdfium_src" ] || {
    echo "build-app.sh: no pdfium at ${pdfium_src} - run packaging/fetch-models.sh" >&2
    exit 1
}

# **A private symbol in a binary is a rejection, and one cost slipcase-desktop
# a review cycle.** Its 0.1.1 was refused on 2026-08-31 for referencing
# `_CGSSetWindowBackgroundBlurRadius`, which arrived through `winit` and which
# that application neither calls nor had heard of. Review scans the symbol
# table rather than the call graph, so *unreachable* is not *absent*: the same
# build with fat LTO and `-Wl,-dead_strip` still carried it. `Cargo.toml`'s
# `[patch.crates-io]` is what removes it, and this is what notices if it or
# anything like it comes back.
#
# **The question it asks is a real one rather than a list of names.** For every
# undefined symbol a binary imports from a system *framework*, does that
# framework's own public headers declare it? That is exactly the line Apple
# draws. Frameworks only: libSystem, libobjc and the rest are the compiler's own
# runtime, declared in no header by design, and asking about them produced a
# dozen findings that were all noise over there. The whole `.framework`
# directory is searched and not just its `Headers`, because Carbon and
# CoreServices are umbrellas whose declarations live beneath them.
#
# Asked of pdfium too, because it is nested code in the same bundle and review
# reads every Mach-O in it.
#
# **One symbol is let through by name, and it is the compiler's rather than a
# framework's.** `___CFConstantStringClassReference` is what clang emits for
# every `CFSTR("...")` literal; it is exported by CoreFoundation's `.tbd`,
# declared in no header since the macro became a compiler builtin, and present
# in every Objective-C program ever shipped. It arrives here through the CoreML
# provider objects inside ONNX Runtime, which slipcase-desktop's binary has no
# counterpart of, so this is the first copy of the check to meet it. Measured
# 2026-09-05: with it allowed, both binaries are clean once `Cargo.toml`'s
# winit pin is in place, and without the pin the executable carries the two
# `CGS` symbols that pin exists for.
private_symbols() {
    exe="$1"
    sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null) || sdk=""
    # Not being able to ask is not the same as a clean answer, and a check that
    # goes quiet on the machine that lacks a tool is the one that lets a build
    # through. Refuse instead.
    [ -n "$sdk" ] && [ -d "$sdk" ] || {
        echo "build-app.sh: no macOS SDK, so the private-symbol check cannot run" >&2
        echo "  install the Xcode command line tools: xcode-select --install" >&2
        exit 1
    }
    scratch=$(mktemp -d)
    # `nm -m` names the library each undefined symbol is expected to come from,
    # which is what makes the per-framework question askable at all. Every
    # slice of a fat file is listed, and a symbol in any is a finding.
    nm -mu "$exe" 2>/dev/null |
        sed -n 's/.*(undefined) external _\{0,1\}\([A-Za-z0-9_]*\) (from \([A-Za-z0-9_+]*\)).*/\2 \1/p' |
        sort -u > "${scratch}/pairs"
    # A binary that imports nothing is not a clean answer, it is `nm` having
    # failed to read the file - and an empty list walks through every check
    # below it without a word. Refuse that rather than pass it.
    [ -s "${scratch}/pairs" ] || {
        echo "build-app.sh: nm read no imported symbols from ${exe}" >&2
        echo "  a Mach-O binary always imports some; this is not a pass" >&2
        rm -rf "$scratch"
        exit 1
    }
    : > "${scratch}/flagged"
    for framework in $(cut -d' ' -f1 "${scratch}/pairs" | sort -u); do
        dir="${sdk}/System/Library/Frameworks/${framework}.framework"
        [ -d "$dir" ] || continue
        awk -v f="$framework" '$1 == f { print $2 }' "${scratch}/pairs" |
            sort -u > "${scratch}/wanted"
        find "$dir" -name '*.h' -print0 2>/dev/null |
            xargs -0 grep -hoFw -f "${scratch}/wanted" 2>/dev/null |
            sort -u > "${scratch}/declared"
        comm -23 "${scratch}/wanted" "${scratch}/declared" |
            grep -vx '__CFConstantStringClassReference' |
            sed "s/^/${framework} /" >> "${scratch}/flagged" || true
    done
    if [ -s "${scratch}/flagged" ]; then
        echo "build-app.sh: ${exe} imports symbols no public header declares:" >&2
        sed 's/^/  /' "${scratch}/flagged" >&2
        echo "  App Store review refuses these as Guideline 2.5.1." >&2
        echo "  Find the crate with: grep -rn SYMBOL ~/.cargo/registry/src/*/" >&2
        rm -rf "$scratch"
        exit 1
    fi
    rm -rf "$scratch"
}
private_symbols "$binary"
private_symbols "$pdfium_src"

# Two numbers, not one, and that is the whole reason `version.sh` takes an
# argument. `CFBundleShortVersionString` is what a person sees in the About box
# and is the release version. `CFBundleVersion` is what App Store Connect
# deduplicates uploads by: it must increase on *every* upload, including a
# rejected one resubmitted with no change, so it cannot be the release version.
version=$("${here}/../version.sh" --short)
build=$("${here}/../version.sh" --build)

app="${outdir}/Duckling.app"
rm -rf "$app"
mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources" "${app}/Contents/Frameworks"

# The icon comes from the one drawing every platform's icon comes from, which
# `packaging/README.md` names as the source. macOS wants a raster at ten sizes
# in an `.iconset` directory, and `iconutil` turns that into the `.icns`.
#
# `sips` reads the SVG, but it rasterizes at whatever width and height the
# document declares and then resamples to the size asked for, so rendering the
# 64-unit source at 1024 gives a soft upscale of a 64-pixel bitmap. Rewriting
# the declared size first makes each rendering a true one at that size, which
# is also how the Linux icon theme draws the same file. slipcase-desktop
# measured both ways at 16 pixels before this was written.
stage=$(mktemp -d)
iconset="${stage}/duckling.iconset"
mkdir -p "$iconset"
svg="${root}/packaging/linux/icons/duckling.svg"
[ -f "$svg" ] || { echo "build-app.sh: no icon source at $svg" >&2; exit 1; }

render() {
    size=$1
    out=$2
    sed -E "s/(<svg[^>]*)width=\"[0-9]+\" height=\"[0-9]+\"/\1width=\"${size}\" height=\"${size}\"/" \
        "$svg" > "${stage}/at-${size}.svg"
    sips -s format png "${stage}/at-${size}.svg" --out "$out" >/dev/null 2>&1
    # The rewrite above is a substitution on someone else's file and would fail
    # silently if the attributes were ever written differently, leaving every
    # icon a 64-pixel upscale. Checked rather than trusted.
    got=$(sips -g pixelWidth "$out" | sed -n 's/.*pixelWidth: *//p')
    [ "$got" = "$size" ] || {
        echo "build-app.sh: asked for ${size}px and got ${got}px - the SVG's width and height attributes are not where the substitution expects them" >&2
        exit 1
    }
}

for pair in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x \
            128:128x128 256:128x128@2x 256:256x256 512:256x256@2x \
            512:512x512 1024:512x512@2x
do
    render "${pair%%:*}" "${iconset}/icon_${pair#*:}.png"
done
iconutil --convert icns "$iconset" --output "${app}/Contents/Resources/duckling.icns"

sed -e "s/@VERSION@/${version}/g" -e "s/@BUILD@/${build}/g" \
    "${here}/Info.plist.in" > "${app}/Contents/Info.plist"
# A malformed property list is not an error Finder reports; it is a bundle that
# quietly does not launch. Parsed here so the failure is loud.
plutil -lint "${app}/Contents/Info.plist" >/dev/null

install -m 0755 "$binary" "${app}/Contents/MacOS/duckling"

# **The models and pdfium, in the two places a signed bundle allows them.**
# Linux and Windows put `models/` and `pdfium/` beside the executable, and a
# bundle cannot: `codesign` treats everything under `Contents/MacOS` as code
# and refuses to seal 780 MB of weights there, and a shared library has to be
# nested code under `Contents/Frameworks` for the Store to accept it. So the
# models are resources and pdfium is a framework, and `locate_assets` in
# `src/lib.rs` looks in both places after looking beside the executable.
#
# `cp -c` clones on APFS, which is every Mac this runs on, so 780 MB costs no
# time and no space; it falls back to a copy on a filesystem that cannot.
cp -Rc "${root}/.models/." "${app}/Contents/Resources/models/" 2>/dev/null ||
    cp -R "${root}/.models/." "${app}/Contents/Resources/models/"
find "${app}/Contents/Resources/models" -type f -exec chmod 0644 {} +

# pdfium is fetched universal and the executable is one architecture, so the
# library is thinned to match: an x86_64 slice in an arm64-only bundle is 7 MB
# that nothing loads. A bundle made from an `intel-mac` development build gets
# the x86_64 slice by the same rule.
arch=$(lipo -archs "$binary" | tr ' ' ',')
case "$arch" in
    *,*)
        cp "$pdfium_src" "${app}/Contents/Frameworks/libpdfium.dylib" ;;
    *)
        lipo -thin "$arch" "$pdfium_src" -output "${app}/Contents/Frameworks/libpdfium.dylib" ;;
esac
chmod 0755 "${app}/Contents/Frameworks/libpdfium.dylib"

# A released bundle's executable has to agree with the floor its property list
# declares, and Cargo's default does not: without `MACOSX_DEPLOYMENT_TARGET`
# an arm64 build says 11.0 while the bundle says 13.4. Finder would refuse to
# launch it below 13.4 and the binary would claim to run there, which is a
# promise to a person that the bundle then breaks - and 13.4 is not this
# repository's choice but ONNX Runtime's, measured off the library `ort`
# links: README.md §1. Checked for a Store build; a development bundle for the
# local loop is left alone, because failing the everyday bundle over a floor
# that only matters on somebody else's machine would be theatre.
floor=$(plutil -extract LSMinimumSystemVersion raw "${app}/Contents/Info.plist")
if [ -n "$store_profile" ]; then
    # A Store build is Apple silicon or it is nothing - README.md §1 - and an
    # executable with no ONNX Runtime linked into it, which is what the
    # `intel-mac` feature produces, converts no PDF wherever it runs.
    [ "$arch" = arm64 ] || {
        echo "build-app.sh: a Store build is arm64 and this executable is ${arch}" >&2
        exit 1
    }
    nm "${app}/Contents/MacOS/duckling" 2>/dev/null | grep -q ' T _OrtGetApiBase' || {
        echo "build-app.sh: no ONNX Runtime is linked into this executable; it was built with the intel-mac feature or without the pdf pipeline" >&2
        exit 1
    }
    for bin in "${app}/Contents/MacOS/duckling" "${app}/Contents/Frameworks/libpdfium.dylib"; do
        # Two shapes: a modern build emits LC_BUILD_VERSION with `minos`, and
        # an old enough deployment target emits LC_VERSION_MIN_MACOSX with
        # `version`. Both are read, so this cannot pass by finding neither.
        got=$(otool -arch arm64 -l "$bin" |
            awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/ {want=1; next}
                 want && ($1 == "minos" || $1 == "version") {print $2; exit}')
        case "$bin" in
            *duckling)
                [ "$got" = "$floor" ] || {
                    echo "build-app.sh: the executable was built for ${got:-nothing} and Info.plist declares ${floor} - rebuild with MACOSX_DEPLOYMENT_TARGET=${floor}" >&2
                    exit 1
                } ;;
            *)
                # A library may be older than the bundle's floor, never newer.
                [ "$(printf '%s\n%s\n' "$got" "$floor" | sort -V | head -1)" = "$got" ] || {
                    echo "build-app.sh: libpdfium.dylib wants macOS ${got} and Info.plist declares ${floor}" >&2
                    exit 1
                } ;;
        esac
    done
fi

# Signing is inside out: the nested library first, then the bundle, each with
# the identity the bundle gets. `--deep` is the thing not to use here - Apple
# deprecated it because it signs whatever it finds with the outer code's
# entitlements, and a library carrying the sandbox entitlement is wrong.
sign_nested() {
    codesign --force --timestamp="${2:-none}" ${3:-} --sign "$1" \
        "${app}/Contents/Frameworks/libpdfium.dylib"
}

# The Store path. Everything it needs was validated before the build; what is
# left is to put the profile inside the bundle, sign what a submission is signed
# with, and wrap it.
if [ -n "$store_profile" ]; then
    # The profile has to match the bundle it goes into. `application-identifier`
    # is `TEAMID.bundle-identifier`, so the tail of it is what Info.plist must
    # say - a profile for a neighbouring identifier signs perfectly and is
    # refused at upload.
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${app}/Contents/Info.plist")
    [ "$store_app_id" = "${store_team}.${bundle_id}" ] || {
        echo "build-app.sh: the profile is for ${store_app_id} and this bundle is ${bundle_id}" >&2
        exit 1
    }

    # One identity or none, never a guess. Two certificates of the same kind in
    # one keychain is an ordinary state - an expiring one beside its replacement
    # - and picking whichever `grep` found first is how a package gets signed
    # with the wrong one.
    find_identity() {
        matches=$(security find-identity -v 2>/dev/null |
            grep "$1: .*(${store_team})" | sed 's/.*"\(.*\)"/\1/')
        count=$(printf '%s' "$matches" | grep -c . || true)
        [ "$count" = 1 ] || {
            echo "build-app.sh: expected one \"$1\" identity for team ${store_team}, found ${count}" >&2
            [ "$count" = 0 ] || echo "$matches" | sed 's/^/  /' >&2
            return 1
        }
        printf '%s' "$matches"
    }
    app_identity=$(find_identity "Apple Distribution") || exit 1
    # Apple's portal calls this Mac Installer Distribution; the certificate calls
    # itself something else, and the certificate is what `security` reports. It
    # also never appears under `-p codesigning`, because it signs a package
    # rather than code, which is why nothing here filters by that policy.
    pkg_identity=$(find_identity "3rd Party Mac Developer Installer") || exit 1

    # Before the signature, because a signature covers what is in the bundle
    # when it is made and this is part of what gets covered.
    cp "$store_profile" "${app}/Contents/embedded.provisionprofile"

    # **Then strip every extended attribute off the bundle, and this is not
    # tidying.** App Store Connect refuses a package containing any file marked
    # `com.apple.quarantine` - ITMS-91109 - and a profile is downloaded from the
    # developer portal in a browser, so it arrives marked. macOS `cp` preserves
    # extended attributes, so the mark rides into the bundle, through the
    # signature, through `productbuild`, and past `altool --validate-app`. The
    # upload is then accepted, ingestion rejects it hours later by email, and
    # nothing appears in App Store Connect at all. slipcase-desktop measured
    # this on its build 165. The models arrive by `curl` and carry nothing, but
    # a model file somebody once dragged in from a browser would, so all of it
    # is cleared.
    xattr -cr "$app"

    # The entitlements a Store build is signed with are not the ones a
    # development build is signed with, and this is generated rather than
    # committed so the team identifier has exactly one source: the profile.
    #
    # `keychain-access-groups` is deliberately absent. The profile grants it and
    # this application touches no keychain, and a capability asked for and
    # unused is a question at review with no good answer - the same rule
    # `AppxManifest.xml` follows about declaring only `runFullTrust`.
    store_ents=$(mktemp -t duckling-entitlements)
    cat > "$store_ents" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.application-identifier</key>
	<string>${store_app_id}</string>
	<key>com.apple.developer.team-identifier</key>
	<string>${store_team}</string>
</dict>
</plist>
ENTITLEMENTS

    sign_nested "$app_identity" "" "--options runtime"
    codesign --force --timestamp --options runtime \
        --sign "$app_identity" \
        --entitlements "$store_ents" \
        "$app"

    # Read back rather than trusted, for both of them. The sandbox one is the
    # failure that costs a day; the identifier one is the failure that costs an
    # upload, and neither is visible by looking at the bundle.
    granted=$(codesign -d --entitlements - --xml "$app" 2>/dev/null |
        plutil -extract 'com\.apple\.security\.app-sandbox' raw - 2>/dev/null)
    [ "$granted" = true ] || {
        echo "build-app.sh: the Store signature carries no app-sandbox entitlement" >&2
        exit 1
    }
    # And refuse if anything is still marked, because the cost of finding out
    # later is an upload, a wait, and an email. `find -exec` rather than
    # `xargs`: xargs answers 123 when the command it ran was false, which is
    # the *normal* case here, and under `set -eu` that kills the script.
    marked=$(find "$app" -type f -exec sh -c \
        'xattr -p com.apple.quarantine "$1" >/dev/null 2>&1 && echo "$1"' _ {} \;)
    [ -z "$marked" ] || {
        echo "build-app.sh: files in the bundle carry com.apple.quarantine, which" >&2
        echo "  App Store Connect refuses as ITMS-91109:" >&2
        printf '  %s\n' $marked >&2
        exit 1
    }

    granted=$(codesign -d --entitlements - --xml "$app" 2>/dev/null |
        plutil -extract 'com\.apple\.application-identifier' raw - 2>/dev/null)
    [ "$granted" = "$store_app_id" ] || {
        echo "build-app.sh: the Store signature says application-identifier ${granted:-nothing}, not ${store_app_id}" >&2
        exit 1
    }
    [ -f "${app}/Contents/embedded.provisionprofile" ] || {
        echo "build-app.sh: the signed bundle carries no embedded.provisionprofile" >&2
        exit 1
    }
    codesign --verify --deep --strict "$app" || {
        echo "build-app.sh: the signed bundle does not verify" >&2
        exit 1
    }
    echo "signed ${app} for the Store with ${app_identity}"

    # `--component ... /Applications` is where the Store installs it.
    # `productbuild` rather than `pkgbuild`: the first makes a distribution
    # package, which is what the upload takes, and the second makes a
    # component package, which it does not.
    pkg="${outdir}/Duckling.pkg"
    productbuild --component "$app" /Applications --sign "$pkg_identity" "$pkg" >/dev/null
    pkgutil --check-signature "$pkg" | sed -n '1,3p'
    echo "built ${pkg} signed with ${pkg_identity} ($(du -h "$pkg" | cut -f1))"

    # Launch Services must not know this bundle. It cannot run on this machine:
    # AMFI refuses its restricted entitlements without a profile covering the
    # Mac, and a Store profile covers none (README.md). Launch Services does not
    # ask whether a bundle can launch before choosing it, and among copies of
    # one identifier it prefers the newer version, so a submission build
    # sitting here is what `open -a Duckling` would reach - and be killed by
    # the kernel on the spot. slipcase-desktop measured this on 2026-09-04.
    # `-u` exits 1 when the bundle was never registered, which is the usual
    # state straight after a build, so its status is not the script's.
    "$lsregister" -u "$app" >/dev/null 2>&1 || true

    echo
    echo "validate it without submitting, then upload; packaging/macos/SUBMITTING.local.md has the account half:"
    echo "  xcrun altool --validate-app -f ${pkg} -t macos --apiKey KEY_ID --apiIssuer ISSUER_ID"
    echo "  xcrun altool --upload-app   -f ${pkg} -t macos --apiKey KEY_ID --apiIssuer ISSUER_ID"
    exit 0
fi

# Last, so that nothing this script writes lands inside the bundle after it has
# been sealed. A signature covers what is there when it is made, and adding a
# file afterwards is how a bundle becomes one macOS reports as damaged.
if [ -n "$identity" ]; then
    sign_nested "$identity"
    codesign --force --timestamp=none \
        --sign "$identity" \
        --entitlements "${here}/Duckling.entitlements" \
        "$app"
    # A signature that did not carry the entitlements is the failure that costs
    # a day: the bundle launches, behaves exactly as an unsigned one does, and
    # every sandbox measurement made against it is quietly meaningless. The
    # dots in the key are escaped because `plutil -extract` reads an unescaped
    # one as a key path separator.
    granted=$(codesign -d --entitlements - --xml "$app" 2>/dev/null |
        plutil -extract 'com\.apple\.security\.app-sandbox' raw - 2>/dev/null)
    [ "$granted" = true ] || {
        echo "build-app.sh: the signature carries no app-sandbox entitlement" >&2
        exit 1
    }
    codesign --verify --deep --strict "$app" || {
        echo "build-app.sh: the signed bundle does not verify" >&2
        exit 1
    }
    echo "signed ${app} with ${identity}"
fi

echo "built ${app} from ${binary} ($(du -sh "$app" | cut -f1), ${arch}, floor ${floor})"
echo
echo "run it with a file, and check what it found beside itself:"
echo "  open -a ${app} --args /path/to/some.pdf"
echo "  ./packaging/macos/check-install.sh ${app}"
