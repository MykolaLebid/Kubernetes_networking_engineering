#!/usr/bin/env bash
# render-epub.sh — Build the course EPUB with Mermaid diagrams rendered as images
# Renders each diagram individually so parse failures don't block the rest.
# Requires: pandoc, mmdc (@mermaid-js/mermaid-cli), python3

set -euo pipefail

MMDC="/Users/I568351/homebrew/Cellar/node/26.5.0/bin/mmdc"
TMPDIR=$(mktemp -d)
COMBINED="$TMPDIR/combined.md"
RENDERED_MD="$TMPDIR/combined-rendered.md"
ARTIFACTS="$TMPDIR/artifacts"
mkdir -p "$ARTIFACTS"

echo "==> Temp dir: $TMPDIR"

# 1. Combine all 34 lessons
{
  cat <<'HEADER'
---
title: Kubernetes Network Engineering
subtitle: 34-Lesson Complete Course
author: Kubernetes Network Engineering Course
date: November 2026
lang: en
toc: true
toc-depth: 2
---

HEADER

  for f in lessons/[0-9][0-9]-*.md; do
    cat "$f"
    printf "\n\n---\n\n"
  done
} > "$COMBINED"

TOTAL_DIAGRAMS=$(grep -c '```mermaid' "$COMBINED")
echo "==> Combined: $(wc -l < "$COMBINED") lines, $TOTAL_DIAGRAMS Mermaid blocks"

# 2. Python: extract each diagram, render individually, replace with image ref
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
             '-b', 'white', '--size', '900', '--quiet'],
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

echo "==> Building EPUB..."
pandoc "$RENDERED_MD" \
  -o kubernetes-network-engineering.epub \
  --split-level=2 \
  --toc \
  --toc-depth=2 \
  --metadata title="Kubernetes Network Engineering" \
  --metadata author="Kubernetes Network Engineering Course" \
  --metadata lang="en" \
  --css epub-table-styles.css \
  2>&1

EPUB_SIZE=$(ls -lh kubernetes-network-engineering.epub | awk '{print $5}')
echo "==> Done — kubernetes-network-engineering.epub ($EPUB_SIZE)"
rm -rf "$TMPDIR"
