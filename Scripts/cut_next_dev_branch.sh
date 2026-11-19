#!/bin/zsh
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./Scripts/cut_next_dev_branch.sh <new-dev-branch>

Note:
  Released dev-* branches are kept permanently as read-only archives.
  --cleanup-old is rejected before any branch operations.

Example (after releasing dev-1.0.3 -> main & tagging v1.0.3):
  ./Scripts/cut_next_dev_branch.sh dev-1.0.4
EOF
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
    --cleanup-old)
        echo "Error: Released dev branches must be retained. --cleanup-old is no longer supported." >&2
        exit 1
        ;;
esac

NEW_BRANCH="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --cleanup-old)
            echo "Error: Released dev branches must be retained. --cleanup-old is no longer supported." >&2
            exit 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ ! "$NEW_BRANCH" =~ ^dev-[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; then
    echo "Error: Branch name '$NEW_BRANCH' must follow 'dev-X.Y.Z' (e.g. dev-1.0.2)." >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Error: Tracked working tree is dirty. Commit or stash changes first." >&2
    exit 1
fi

GH_BIN="${GH_BIN:-$(command -v gh || true)}"
if [ -z "$GH_BIN" ] && [ -x "/opt/homebrew/bin/gh" ]; then
    GH_BIN="/opt/homebrew/bin/gh"
fi
if [ -z "$GH_BIN" ]; then
    echo "Error: GitHub CLI (gh) is required to update the repository default branch." >&2
    exit 1
fi

echo "==> Fetching latest refs from origin..."
git fetch origin --prune

if git show-ref --verify --quiet "refs/remotes/origin/$NEW_BRANCH"; then
    echo "Error: Remote branch 'origin/$NEW_BRANCH' already exists." >&2
    exit 1
fi

echo "==> Creating '$NEW_BRANCH' from origin/main..."
git checkout -b "$NEW_BRANCH" origin/main
git push -u origin "$NEW_BRANCH"

REPO_NWO="$("$GH_BIN" repo view --json nameWithOwner --jq '.nameWithOwner')"
echo "==> Setting GitHub default branch of $REPO_NWO to '$NEW_BRANCH'..."
"$GH_BIN" api -X PATCH "repos/$REPO_NWO" -f default_branch="$NEW_BRANCH" --silent
git remote set-head origin "$NEW_BRANCH"

echo "==> Done! Active default development branch is now '$NEW_BRANCH'."
