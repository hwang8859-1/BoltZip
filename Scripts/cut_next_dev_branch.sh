#!/bin/zsh
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./Scripts/cut_next_dev_branch.sh <new-dev-branch> [--cleanup-old <old-dev-branch>]

Example (after releasing dev-1.0.1 -> main & tagging v1.0.1):
  ./Scripts/cut_next_dev_branch.sh dev-1.0.2 --cleanup-old dev-1.0.1
EOF
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

NEW_BRANCH="$1"
shift
OLD_BRANCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --cleanup-old)
            if [ $# -lt 2 ]; then
                echo "Error: --cleanup-old requires a branch name." >&2
                exit 1
            fi
            OLD_BRANCH="$2"
            shift 2
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

if [ -n "$OLD_BRANCH" ]; then
    if [ "$OLD_BRANCH" = "main" ] || [ "$OLD_BRANCH" = "$NEW_BRANCH" ] || [[ "$OLD_BRANCH" == legacy/* ]]; then
        echo "Error: Refusing to delete protected branch '$OLD_BRANCH'." >&2
        exit 1
    fi
    if git show-ref --verify --quiet "refs/remotes/origin/$OLD_BRANCH"; then
        if ! git merge-base --is-ancestor "origin/$OLD_BRANCH" origin/main; then
            echo "Error: 'origin/$OLD_BRANCH' is NOT yet merged into 'origin/main'; aborting cleanup." >&2
            exit 1
        fi
        echo "==> Cleaning up merged remote branch 'origin/$OLD_BRANCH'..."
        git push origin --delete "$OLD_BRANCH"
    fi
    if git show-ref --verify --quiet "refs/heads/$OLD_BRANCH"; then
        git branch -d "$OLD_BRANCH"
    fi
fi

echo "==> Done! Active default development branch is now '$NEW_BRANCH'."
