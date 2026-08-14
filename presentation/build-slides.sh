#!/bin/bash
# =============================================================================
# build-slides.sh – Generate HTML and PDF from Marp Markdown slides
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building HTML presentation..."
npx -y @marp-team/marp-cli@latest --no-stdin slides.md -o froscon-microvm.html --html --config-file .marprc.yml

echo "==> Building PDF presentation..."
npx -y @marp-team/marp-cli@latest --no-stdin --pdf slides.md -o froscon-microvm.pdf --allow-local-files --html --config-file .marprc.yml

echo "✅ Build complete!"
echo "   HTML: $SCRIPT_DIR/froscon-microvm.html"
echo "   PDF:  $SCRIPT_DIR/froscon-microvm.pdf"
