#!/bin/sh
# Fetch the runtime assets every package ships: the ONNX models for the PDF
# and image pipeline, and pdfium for this platform. Into `.models/` and
# `.pdfium/lib/` at the repository root, which is where docling.rs looks
# relative to the working directory during development and where the
# packaging scripts copy from. Every file is pinned by URL and SHA-256; a
# file that is present and matches is not fetched again, and a file that
# arrives and does not match is deleted and reported.
#
# The set is the one docling.rs resolves at run time. It is fetched from a
# release on this repository rather than from where each file originally came,
# and that is the point of it: `models-v1` on docling-project/docling.rs is a
# *rolling* tag whose assets are overwritten by upstream's publish workflow —
# five times in the ten days before the mirror was taken — and the English
# recognizer and the key list came from a branch. A hash pinned against a
# moving reference is a build that breaks on somebody else's schedule, and a
# cache then hides the change until the day it does not.
#
# Taking an upstream model change is deliberate: a new dated release here, the
# new hashes below, and a look at what the change does to conversion quality
# before either lands. A mirror tag is never republished.
#
# The original sources and their licences are in the mirror release's notes,
# which is where the attribution those licences require lives.
# The layout model ships int8 alone; TableFormer ships the one decoder the
# pipeline resolves and the fp32 encoder, which is the file that resolves in
# every configuration. DESIGN.md §2 says what each choice costs.
#
# A file this set does not name is removed from `.models/` when it is found
# there: the packaging scripts copy that directory whole, so what is on disk
# is what ships.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

set -eu
cd "$(dirname "$0")/.."

BASE=https://github.com/excelano/duckling/releases/download/models-2026-09-15

retire() { # <path>
  if [ -e "$1" ]; then
    rm -f "$1"
    echo "  - $1"
  fi
}

# ` *` rather than two spaces, which is sha256sum's binary mode. On this
# platform's Git Bash it is the same answer and on a future one it may not be,
# and a checksum that depends on how the reader felt about line endings is not
# a checksum.
fetch() { # <url> <path> <sha256> <size>
  if [ -f "$2" ] && echo "$3 *$2" | sha256sum -c --quiet - 2>/dev/null; then
    echo "  = $2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  echo "  > $2"
  curl -fsSL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$2.part" "$1"
  # macOS's `wc` pads its count with spaces; the pin has none.
  got=$(wc -c < "$2.part" | tr -d ' ')
  if [ "$got" != "$4" ]; then
    echo "fetch-models: $2 arrived as $got bytes and the pin says $4; not kept" >&2
    rm -f "$2.part"
    exit 1
  fi
  if echo "$3 *$2.part" | sha256sum -c --quiet -; then
    mv "$2.part" "$2"
  else
    # What was actually received, before it is thrown away. A mismatch is
    # either a transfer that stopped early or a different file upstream, and
    # those want opposite responses: the first is retried and the second is
    # investigated. Without the size and the hash the message fits both and
    # answers neither, which is how a Windows runner failed twice on the same
    # 172 MB file while every other lane stayed green.
    echo "fetch-models: $2 did not match its pinned SHA-256; not kept" >&2
    echo "  pinned   $3" >&2
    echo "  received $(sha256sum "$2.part" | cut -d' ' -f1)" >&2
    echo "  bytes    $got" >&2
    rm -f "$2.part"
    exit 1
  fi
}

# pdfium per platform. Linux x64 takes the build docling.rs pins for its
# conformance runs, mirrored with the models. Windows and macOS take
# bblanchon's prebuilts, the same source that Linux build came from, at one
# release tag for both, pinned by the archive's hash; only the library member
# is kept. The Mac archive is universal, so one file serves both architectures.
#
# Those two are not mirrored, and the difference is the tag: `chromium/8035`
# names one chromium build, and bblanchon publishes a new tag rather than
# overwriting that one.
PDFIUM=https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F8035

fetch_member() { # <url> <archive sha256> <member> <path>
  if [ -f "$4" ]; then
    echo "  = $4"
    return
  fi
  mkdir -p "$(dirname "$4")"
  echo "  > $4"
  tgz="$4.tgz.part"
  curl -fsSL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$tgz" "$1"
  if ! echo "$2  $tgz" | sha256sum -c --quiet -; then
    rm -f "$tgz"
    echo "fetch-models: $(basename "$1") did not match its pinned SHA-256; not kept" >&2
    exit 1
  fi
  tar xzf "$tgz" -O "$3" > "$4.part"
  rm -f "$tgz"
  mv "$4.part" "$4"
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    fetch "$BASE/libpdfium.so" .pdfium/lib/libpdfium.so \
      b0361f8ba0bc6ffeb2325949a88f08b09356f46abe257ffdf846202999daa27b 7824656 ;;
  Darwin-*)
    fetch_member "$PDFIUM/pdfium-mac-univ.tgz" \
      794bb5e0d66954a9f61fb1a0224f9e4b8577a792b7f9387d9294c314d6c8bd50 \
      lib/libpdfium.dylib .pdfium/lib/libpdfium.dylib ;;
  MINGW*|MSYS*|CYGWIN*)
    fetch_member "$PDFIUM/pdfium-win-x64.tgz" \
      61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41 \
      bin/pdfium.dll .pdfium/lib/pdfium.dll ;;
  *)
    echo "fetch-models: no pinned pdfium for $(uname -s)-$(uname -m)" >&2
    exit 1 ;;
esac

fetch "$BASE/layout_heron_int8.onnx" .models/layout_heron_int8.onnx 1c53e651ade205ce7d6dfbe54af9730d774af4ec0249832b94860466de0b440b  68695321
fetch "$BASE/ocr_rec.onnx"           .models/ocr_rec.onnx           897a3ededb38fee0dae2c1ccee38241f37df202c9509e3abca02e9217c5ee615  10690752
fetch "$BASE/ppocr_keys_v1.txt"      .models/ppocr_keys_v1.txt      a1c84d9bdb9ab29043c58896224d32941783eb821629618416dcb08f12886492     26250
fetch "$BASE/ocr_rec_en.onnx"        .models/ocr_rec_en.onnx        ef7abd8bd3629ae57ea2c28b425c1bd258a871b93fd2fe7c433946ade9b5d9ea   8967018
fetch "$BASE/en_dict.txt"            .models/en_dict.txt            5662df9d2d03f0e8ca0d3b0649d6acbab904b6a14b3d3521463c71c37c668ce3       190
fetch "$BASE/encoder.onnx"         .models/tableformer/encoder.onnx         d6a360e3c7663ebaffa5e578ddb6f0d1806f1b469f85b7c304e7a7de41a43abf 107827334
fetch "$BASE/decoder_kv.onnx"      .models/tableformer/decoder_kv.onnx      1a260bbf82a205bfcac64b0a92219ea76aae9faa99dd357bbbefcca5b558db89    350270
fetch "$BASE/decoder_kv.onnx.data" .models/tableformer/decoder_kv.onnx.data 0d567955041b9b62ea95464372ffdf4e05f7a9429f6318401187bb30470275e0 115605504
fetch "$BASE/bbox.onnx"            .models/tableformer/bbox.onnx            40bd7897bef9b1f152ca8132b07691464db6444df7e3c5cb6f5d7451b8356054     52225
fetch "$BASE/bbox.onnx.data"       .models/tableformer/bbox.onnx.data       7610e2593bfaecd72a535370f06e8c2468f9bf208bd2abe46cc727dda0a11392  39649280

# TableFormer's decoder is picked by preference and `decoder_kv.onnx` is the
# first candidate upstream hosts, so it is the only decoder a package needs.
# The candidates behind it in that order come to 122 MB nothing ever opens,
# and `tests/convert.rs` asks docling.rs what it resolved so that a release
# which reordered the preference fails a test rather than a conversion.
# The fp32 layout model is 172 MB loaded only by `predict_fp32_fallback`, to
# re-run a page whose int8 detections cover too little of it. Cut 2026-09-21:
# the guard did not fire once over 2,018 pages of docling.rs's corpus, and
# without the file `predict_fp32_fallback` returns `Ok(None)` and the page
# keeps its int8 regions, which docling.rs supports. DESIGN.md §2.
retire .models/layout_heron.onnx
# The fp16 repack is half the encoder and the pipeline prefers it on the CPU
# path, but `prefer_fp32()` drops it from the candidates entirely, so a build
# that ever compiles in a GPU provider would resolve to a file no package
# carries and lose ML table structure behind one stderr line. The fp32 file
# resolves in both configurations, which is what it is 54 MB for. DESIGN.md §2.
retire .models/tableformer/encoder_fp16.onnx
retire .models/tableformer/decoder_int8.onnx
retire .models/tableformer/decoder.onnx
retire .models/tableformer/decoder.onnx.data
echo "fetch-models: every asset present and verified"
