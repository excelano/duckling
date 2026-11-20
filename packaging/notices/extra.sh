# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

pdf=$(crate_dir docling-pdf)
section "Adobe Glyph List and font data, in docling-pdf" "$pdf/data/adobe-glyph-list/LICENSE.txt"
section "Adobe CID-to-Unicode mapping resources, in docling-pdf" "$pdf/data/mapping-resources-pdf/LICENSE.txt"
section "Oniguruma, compiled in by onig_sys" "$(crate_dir onig_sys)/oniguruma/COPYING"

onnx=$(grep -o 'ms@[0-9.]*' "$(crate_dir ort-sys)/build/download/dist.tsv" | sort -u | sed 's/ms@//')
if [ "$(wc -l <<<"$onnx")" -ne 1 ] || [ ! -f "packaging/notices/onnxruntime-$onnx-LICENSE.txt" ]; then
    echo "notices.sh: ort links ONNX Runtime $onnx; packaging/notices has no license for it" >&2
    exit 1
fi
section "ONNX Runtime $onnx, linked by ort" "packaging/notices/onnxruntime-$onnx-LICENSE.txt"
section "ONNX Runtime $onnx third-party notices" "packaging/notices/onnxruntime-$onnx-ThirdPartyNotices.txt"
section "DirectML 1.15.4, shipped with the Windows package" packaging/notices/directml-1.15.4-LICENSE.txt
section "DirectML 1.15.4 third-party notices" packaging/notices/directml-1.15.4-ThirdPartyNotices.txt
