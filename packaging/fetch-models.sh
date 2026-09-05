#!/bin/sh
# Fetch the runtime assets every package ships: the ONNX models for the PDF
# and image pipeline, and pdfium for this platform. Into `.models/` and
# `.pdfium/lib/` at the repository root, which is where docling.rs looks
# relative to the working directory during development and where the
# packaging scripts copy from. Every file is pinned by URL and SHA-256; a
# file that is present and matches is not fetched again, and a file that
# arrives and does not match is deleted and reported.
#
# The model set is docling.rs's own default: the release assets at tag
# `models-v1` of docling-project/docling.rs, plus the English PP-OCRv3
# recognizer the pipeline prefers at run time, which upstream hosts elsewhere.
# int8 and fp32 variants both ship, because the pipeline takes int8 by default
# and re-runs a page on fp32 when int8 finds no text on it. DESIGN.md §2.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

set -eu
cd "$(dirname "$0")/.."

BASE=https://github.com/docling-project/docling.rs/releases/download/models-v1

fetch() { # <url> <path> <sha256>
  if [ -f "$2" ] && echo "$3  $2" | sha256sum -c --quiet - 2>/dev/null; then
    echo "  = $2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  echo "  > $2"
  curl -fsSL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$2.part" "$1"
  if echo "$3  $2.part" | sha256sum -c --quiet -; then
    mv "$2.part" "$2"
  else
    rm -f "$2.part"
    echo "fetch-models: $2 did not match its pinned SHA-256; not kept" >&2
    exit 1
  fi
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    fetch "$BASE/libpdfium.so" .pdfium/lib/libpdfium.so \
      3019ad1cd6980e51d900bb9266f8980cb846cb8e0c1f6553c52a7a1626469020 ;;
  *)
    # The Windows and Mac lanes pin their own pdfium from bblanchon's
    # prebuilts; see packaging/<platform>/README.md.
    echo "fetch-models: no pinned pdfium for $(uname -s)-$(uname -m); fetch it by hand" >&2 ;;
esac

fetch "$BASE/layout_heron.onnx"      .models/layout_heron.onnx      2e5d4dd812c46b742a031611ab7ba061bf66937a56fdee266ada4fe1e3073764
fetch "$BASE/layout_heron_int8.onnx" .models/layout_heron_int8.onnx 5c7a4685c838b485069b81847f2c9330f7ffc488aefff7a8ceb7f7968c95e410
fetch "$BASE/ocr_rec.onnx"           .models/ocr_rec.onnx           897a3ededb38fee0dae2c1ccee38241f37df202c9509e3abca02e9217c5ee615
fetch "$BASE/ppocr_keys_v1.txt"      .models/ppocr_keys_v1.txt      a1c84d9bdb9ab29043c58896224d32941783eb821629618416dcb08f12886492
fetch "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv3/en_PP-OCRv3_rec_infer.onnx" \
      .models/ocr_rec_en.onnx ef7abd8bd3629ae57ea2c28b425c1bd258a871b93fd2fe7c433946ade9b5d9ea
fetch "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/en_dict.txt" \
      .models/en_dict.txt 5662df9d2d03f0e8ca0d3b0649d6acbab904b6a14b3d3521463c71c37c668ce3
fetch "$BASE/encoder.onnx"         .models/tableformer/encoder.onnx         790cb70168e66fcf77136fdd3ba6d0ff527ee366e083e62475e0339a5c811e00
fetch "$BASE/decoder.onnx"         .models/tableformer/decoder.onnx         40e9fc2f2878cfbf25ede41e5557eeb9ef091c43c0d7176baa54d01c0b477c34
fetch "$BASE/decoder.onnx.data"    .models/tableformer/decoder.onnx.data    f497d191f3907a2dd0ac9b4a2562e8f52c60f7657a1a714f5a8c4e855f3e39ef
fetch "$BASE/decoder_kv.onnx"      .models/tableformer/decoder_kv.onnx      295e452480e6eddb4ae8972dfff939c1a6a3293bfd8b30fe026c3d7d6ee92037
fetch "$BASE/decoder_kv.onnx.data" .models/tableformer/decoder_kv.onnx.data 7d60a29e01f66108d36075be51c012ff451e70aba83c644a1b59604395f13c10
fetch "$BASE/decoder_int8.onnx"    .models/tableformer/decoder_int8.onnx    fecb9d4ff8612b1afcd0c4955ed530aa5f36c4d03c4da8aa6a2da1e4ff5c2f0c
fetch "$BASE/bbox.onnx"            .models/tableformer/bbox.onnx            65247bba792830762c89baa5f2e5f06c8df7720181e4d0088107f7d88b06f915
fetch "$BASE/bbox.onnx.data"       .models/tableformer/bbox.onnx.data       7610e2593bfaecd72a535370f06e8c2468f9bf208bd2abe46cc727dda0a11392
echo "fetch-models: every asset present and verified"
