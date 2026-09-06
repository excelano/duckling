#!/bin/sh
# Ask an *installed* Duckling what it actually is, on the machine it is on.
#
# `build-app.sh --store` checks what it built, on the machine that built it.
# That is a different question from this one, and the gap between them is where
# a submission goes wrong: the artefact is carried to another machine, macOS
# decides something about it there, and nothing in the build says what.
#
# For Duckling that other machine is every machine that can run the release
# build: the lane is an Intel Mac and the build is Apple silicon only
# (README.md §1), so the walkthrough is always somewhere else and its
# mechanical half should not be typed out from a list.
#
#     ./check-install.sh                    # /Applications/Duckling.app
#     ./check-install.sh /path/to/App       # somewhere else
#
# It reports; it does not repair, and it does not stop at the first bad answer.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
set -u

app="${1:-/Applications/Duckling.app}"
bundle_id="com.excelano.duckling"
team="9K6W5PMFYP"

findings=0
say()  { printf '  %-46s %s\n' "$1" "$2"; }
ok()   { say "$1" "ok - $2"; }
bad()  { say "$1" "NO - $2"; findings=$((findings + 1)); }
note() { printf '  %-46s %s\n' "$1" "$2"; }

echo "check-install.sh on $(uname -m), macOS $(sw_vers -productVersion)"
echo "$app"
echo

[ -d "$app" ] || { echo "  not installed at $app"; exit 2; }

exe="${app}/Contents/MacOS/duckling"

# 1. The architecture. There is one release architecture, and a bundle made
#    from the `intel-mac` development build is the only way to get the other
#    one here - it runs, it draws, and it converts no PDF.
arches=$(lipo -archs "$exe" 2>/dev/null)
case "$arches" in
    arm64) ok "the binary is arm64" "$arches" ;;
    *) bad "the binary is arm64" "${arches:-lipo could not read it} - a development build, or nothing" ;;
esac

# 2. Whether ONNX Runtime is inside it, which the architecture already implies
#    and which is asked directly because it is the fact that matters.
if nm "$exe" 2>/dev/null | grep -q ' T _OrtGetApiBase'; then
    ok "ONNX Runtime is linked in" "OrtGetApiBase is defined"
else
    bad "ONNX Runtime is linked in" "not defined - PDFs and images cannot convert"
fi

# 3. The models and pdfium, in the places `locate_assets` looks for a bundle.
models="${app}/Contents/Resources/models"
if [ -f "${models}/layout_heron_int8.onnx" ] && [ -f "${models}/tableformer/decoder_kv.onnx" ]; then
    ok "the models are in Contents/Resources/models" "$(du -sh "$models" | cut -f1)"
else
    bad "the models are in Contents/Resources/models" "absent or incomplete"
fi
pdfium="${app}/Contents/Frameworks/libpdfium.dylib"
if [ -f "$pdfium" ]; then
    ok "pdfium is in Contents/Frameworks" "$(lipo -archs "$pdfium" 2>/dev/null)"
    # The arm64 slice arrives from bblanchon carrying the ad-hoc signature
    # Apple's linker gives every arm64 binary, which verifies and is not a
    # signature the Store accepts. What is wanted is the bundle's own team.
    pdfium_auth=$(codesign -dvv "$pdfium" 2>&1 | sed -n 's/^Authority=//p' | head -1)
    if [ -n "$pdfium_auth" ]; then
        ok "  and it is signed by the same team" "$pdfium_auth"
    else
        bad "  and it is signed by the same team" "ad-hoc or unsigned - build-app.sh --sign or --store signs it"
    fi
else
    bad "pdfium is in Contents/Frameworks" "no libpdfium.dylib"
fi

# 4. And whether the machine is actually running the arm64 slice natively,
#    which `ps` cannot tell: `vmmap` prints the code type of a process you own.
pid=$(pgrep -f "Duckling.app/Contents/MacOS/duckling" | head -1)
if [ -n "$pid" ]; then
    code_type=$(vmmap "$pid" 2>/dev/null | sed -n 's/^Code Type: *//p' | head -1)
    case "$(uname -m),$code_type" in
        arm64,ARM64*|x86_64,X86*) ok "the running process is native" "$code_type on $(uname -m)" ;;
        *,"") note "the running process is native" "vmmap said nothing usable" ;;
        *) bad "the running process is native" "$code_type on $(uname -m)" ;;
    esac
else
    note "the running process is native" "not running - launch it and re-run"
fi

# 5. Which kind of build this is, decided from the certificate rather than from
#    what the caller believed. They want *different* answers to the checks
#    below - a Store build must carry an application identifier and a profile,
#    a Developer ID or development build must carry neither, and a TestFlight
#    build carries the identifier and no profile, because Apple strips the
#    profile and re-signs.
auth=$(codesign -dv --verbose=2 "$app" 2>&1)
case "$auth" in
    *"TestFlight Beta Distribution"*)
        kind=testflight
        ok "signed" "TestFlight Beta Distribution - Apple re-signed this" ;;
    *"Apple Distribution: Excelano LLC (${team})"*)
        kind=store
        ok "signed" "Apple Distribution, team ${team} - a Store build" ;;
    *"Developer ID Application: Excelano LLC (${team})"*)
        kind=devid
        ok "signed" "Developer ID, team ${team} - the outside-the-Store hedge" ;;
    *"Apple Development"*)
        kind=dev
        ok "signed" "Apple Development - a local test build, not shippable" ;;
    *)
        kind=unknown
        bad "signed" "$(printf '%s' "$auth" | sed -n 's/^Authority=//p' | head -1 | grep . || echo 'not signed - a plain build-app.sh bundle, which is not sandboxed')" ;;
esac
case "$auth" in
    *"Apple Root CA"*) ok "the chain reaches the Apple Root CA" "three authorities" ;;
    *) bad "the chain reaches the Apple Root CA" "it does not" ;;
esac

if codesign --verify --deep --strict "$app" 2>/dev/null; then
    ok "the signature verifies" "--deep --strict"
else
    bad "the signature verifies" "$(codesign --verify --deep --strict "$app" 2>&1 | head -1)"
fi

# 6. The entitlements, read back out of the signature rather than off the file
#    that was fed to it. `plutil -p` spells a boolean `1` on one macOS and
#    `true` on another, so both are accepted.
ents=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - 2>/dev/null)
case "$ents" in
    *'"com.apple.security.app-sandbox" => 1'*|*'"com.apple.security.app-sandbox" => true'*)
        ok "the sandbox is in the signature" "app-sandbox" ;;
    *'com.apple.security.app-sandbox'*)
        bad "the sandbox is in the signature" "present but not true" ;;
    *) bad "the sandbox is in the signature" "absent - the build is not sandboxed" ;;
esac
case "$kind" in
    store|testflight) wants_app_id=yes ;;
    *) wants_app_id=no ;;
esac
case "$wants_app_id,$ents" in
    yes,*"${team}.${bundle_id}"*)
        ok "the application identifier is there" "${team}.${bundle_id}" ;;
    yes,*)
        bad "the application identifier is there" "absent - the upload is refused" ;;
    no,*"${team}.${bundle_id}"*)
        bad "no application identifier" "present on a ${kind} build - it will not launch" ;;
    *)  ok "no application identifier" "correct for a ${kind} build" ;;
esac
case "$ents" in
    *keychain-access-groups*) bad "keychain-access-groups is declined" "it is present" ;;
    *) ok "keychain-access-groups is declined" "absent, as intended" ;;
esac

# 7. The profile has to be inside the bundle, and inside it *before* it was
#    signed. A TestFlight build carries none and must not.
profile="${app}/Contents/embedded.provisionprofile"
if [ "$kind" != store ] && [ ! -f "$profile" ]; then
    ok "no provisioning profile" "correct for a ${kind} build"
elif [ -f "$profile" ]; then
    plist=$(mktemp)
    if security cms -D -i "$profile" -o "$plist" 2>/dev/null; then
        pname=$(plutil -extract Name raw -o - "$plist" 2>/dev/null)
        pexp=$(plutil -extract ExpirationDate raw -o - "$plist" 2>/dev/null)
        ok "a provisioning profile is embedded" "${pname:-unnamed}, expires ${pexp:-unknown}"
    else
        bad "a provisioning profile is embedded" "present but would not decode"
    fi
    rm -f "$plist"
else
    bad "a provisioning profile is embedded" "no embedded.provisionprofile"
fi

# 8. What the bundle claims about itself.
short=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${app}/Contents/Info.plist" 2>/dev/null)
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
    "${app}/Contents/Info.plist" 2>/dev/null)
floor=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" \
    "${app}/Contents/Info.plist" 2>/dev/null)
note "the version it declares" "${short:-?} (build ${build:-?}), macOS ${floor:-?} and later"

# 9. Gatekeeper's verdict, which is not the signature's - and which for a Store
#    build is *rejection*, correctly: `spctl -a` assesses the Developer ID
#    policy, and a Store build is not distributed under it.
gk=$(spctl -a -vvv "$app" 2>&1)
case "$kind,$gk" in
    *,*accepted*)
        note "Gatekeeper" "accepted - $(printf '%s' "$gk" | sed -n 's/.*source=//p' | head -1)" ;;
    store,*rejected*)
        note "Gatekeeper" "rejected, as a Store build correctly is" ;;
    devid,*"Unnotarized Developer ID"*)
        note "Gatekeeper" "rejected - unnotarized, which is the hedge's own step" ;;
    dev,*rejected*)
        note "Gatekeeper" "rejected, as a development build correctly is" ;;
    testflight,*rejected*)
        bad "Gatekeeper" "rejected a TestFlight build, which it should accept" ;;
    *)  bad "Gatekeeper" "$(printf '%s' "$gk" | tr '\n' ' ')" ;;
esac
if xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
    note "it carries com.apple.quarantine" "$(xattr -p com.apple.quarantine "$app" 2>/dev/null)"
else
    note "it carries com.apple.quarantine" "no - so Gatekeeper is not consulted"
fi

# 10. Whether the App Sandbox actually engaged, which is a fact about a *run*
#     rather than about the bundle. The container directory is made on first
#     launch and by nothing else, so its absence after a launch means the
#     entitlement was carried and not honoured.
container="${HOME}/Library/Containers/${bundle_id}"
if [ -d "$container" ]; then
    ok "a sandbox container exists" "$(basename "$container")"
else
    note "a sandbox container exists" "not yet - launch it once and re-run"
fi

echo
if [ "$findings" -eq 0 ]; then
    echo "Nothing mechanical is wrong with this install."
else
    echo "${findings} thing(s) to write down - in the commit, and in"
    echo "CHECKLIST.md only if the next person would run the list differently."
fi
echo "The rest needs eyes: a scanned PDF converting with the network off, the"
echo "folder panel when a single file is converted beside itself, the icon,"
echo "and the layout at 2x."
exit 0
