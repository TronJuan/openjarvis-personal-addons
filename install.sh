#!/usr/bin/env bash
# Adds the personal add-ons to an existing OpenJarvis install on macOS or Linux.
#   ./install.sh                     # uses $OPENJARVIS_HOME/src (default ~/.openjarvis/src)
#   ./install.sh /path/to/OpenJarvis
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
home="${OPENJARVIS_HOME:-$HOME/.openjarvis}"
src="${1:-$home/src}"

[[ -d "$src/.git" ]] || { echo "No OpenJarvis git checkout at $src. Pass its path as the first argument." >&2; exit 1; }
echo "OpenJarvis source: $src"
cd "$src"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "The OpenJarvis folder has uncommitted changes. Commit or stash them first." >&2
    exit 1
fi
if ! git -c user.name="OpenJarvis add-ons" -c user.email="addons@localhost" am --3way "$here"/patches/*.patch; then
    git am --abort
    echo "The patches did not apply to this version of OpenJarvis. See README > Compatibility." >&2
    exit 1
fi

venv=""
for v in "$src/.venv" "$home/.venv"; do [[ -x "$v/bin/python" ]] && { venv="$v"; break; }; done
if [[ -n "$venv" ]]; then
    echo "Installing python-docx and Playwright into $venv"
    uv pip install --python "$venv/bin/python" python-docx "playwright>=1.40"
else
    echo "No .venv found; install python-docx and playwright into OpenJarvis's Python yourself." >&2
fi

echo "Building the web UI"
(cd frontend && npm ci --no-audit --no-fund && npm run build)

echo
echo "Done. Restart 'jarvis serve', open the web UI, then go to Settings:"
echo "  Email accounts   - connect Gmail with an app password"
echo "  Personal agents  - fill in your profile and resume, then press Run now"
if [[ -n "$venv" ]]; then
    echo
    echo "To run the agents on a schedule, add these lines with 'crontab -e':"
    echo "*/15 * * * * cd '$src' && '$venv/bin/python' -m openjarvis.personal.runner eventmate"
    echo "0 8 * * *    cd '$src' && '$venv/bin/python' -m openjarvis.personal.runner jobs"
fi
