#!/usr/bin/env bash
# render-cf-pdf.sh — Build the CF Networking course PDF with Mermaid diagrams rendered as images
# Requires: pandoc, typst, mmdc (@mermaid-js/mermaid-cli), python3

set -euo pipefail

MMDC="/Users/I568351/homebrew/Cellar/node/26.5.0/bin/mmdc"
TMPDIR=$(mktemp -d)
COMBINED="$TMPDIR/combined.md"
RENDERED_MD="$TMPDIR/combined-rendered.md"
ARTIFACTS="$TMPDIR/artifacts"
mkdir -p "$ARTIFACTS"

echo "==> Temp dir: $TMPDIR"

# 1. Combine CF lessons + migration + comparison in reading order
{
  cat <<'HEADER'
---
title: Cloud Foundry Networking Engineering
subtitle: 23-Lesson Course (CF-00 through CF-22) — Garden, Silk CNI, Gorouter, Compliance, SAP BTP
date: November 2026
toc: true
---

HEADER

  for f in docs/cf/cf-[0-9][0-9]-*.md; do
    cat "$f"
    printf "\n\n---\n\n\\\\newpage\n\n"
  done

  printf "\n\n# Appendix: CF-to-Kubernetes Migration\n\n"
  for f in docs/migration/mig-[0-9][0-9]-*.md; do
    cat "$f"
    printf "\n\n---\n\n\\\\newpage\n\n"
  done

  printf "\n\n# Appendix: CF vs Kubernetes Comparison\n\n"
  cat docs/shared/cf-vs-k8s-comparison.md
  printf "\n\n---\n\n\\\\newpage\n\n"

} > "$COMBINED"

# Strip web-only "Jump to:" nav lines — they break Typst when anchors collide across combined files
sed -i '' '/^\*\*Jump to:\*\*/d' "$COMBINED"

TOTAL_DIAGRAMS=$(grep -c '```mermaid' "$COMBINED" || true)
echo "==> Combined: $(wc -l < "$COMBINED") lines, $TOTAL_DIAGRAMS Mermaid blocks"

# 2. Render each Mermaid block to PNG, replace in markdown
python3 - "$COMBINED" "$RENDERED_MD" "$ARTIFACTS" "$MMDC" <<'PYEOF'
import sys, re, subprocess, os, tempfile

src_file, dst_file, img_dir, mmdc = sys.argv[1:]
content = open(src_file).read()
mermaid_re = re.compile(r'```mermaid\n(.*?)```', re.DOTALL)

ok, fail = 0, 0

def render_one(m):
    global ok, fail
    src = m.group(1).strip().replace('\\n', ' ')
    idx = ok + fail + 1
    png_name = f"diagram_{idx:04d}.png"
    png_path = os.path.join(img_dir, png_name)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.mmd', delete=False) as f:
        f.write(src)
        tmp = f.name

    try:
        r = subprocess.run(
            [mmdc, '-i', tmp, '-o', png_path, '-e', 'png',
             '-b', 'white', '--size', '1400', '--quiet'],
            capture_output=True, text=True, timeout=20
        )
        if r.returncode == 0 and os.path.exists(png_path):
            ok += 1
            return f'![Diagram {idx}]({png_path})'
        else:
            fail += 1
            return m.group(0)
    except Exception:
        fail += 1
        return m.group(0)
    finally:
        os.unlink(tmp)

processed = mermaid_re.sub(render_one, content)
open(dst_file, 'w').write(processed)
print(f"  Rendered {ok} diagrams ({fail} kept as code blocks)")
PYEOF

echo "==> Building PDF..."
pandoc "$RENDERED_MD" \
  -o cf-networking.pdf \
  --pdf-engine=typst \
  --toc \
  --toc-depth=2 \
  -H pdf-table-styles.typ \
  2>&1

PDF_SIZE=$(ls -lh cf-networking.pdf | awk '{print $5}')
echo "==> Done — cf-networking.pdf ($PDF_SIZE)"
rm -rf "$TMPDIR"
