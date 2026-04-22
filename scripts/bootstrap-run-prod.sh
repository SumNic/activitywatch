#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Bootstrap ActivityWatch fork and run production mode.

Usage:
  bash scripts/bootstrap-run-prod.sh [options] [-- <run-prod.sh args...>]

Options:
  --repo <url>        Git repo to clone/update (default: https://github.com/SumNic/activitywatch.git)
  --branch <name>     Branch to checkout (default: master)
  --dir <path>        Clone dir (default: $XDG_CACHE_HOME/activitywatch-run-prod or ~/.cache/activitywatch-run-prod)
  --fork-user <name>  GitHub user/org for submodule forks (default: "SumNic")
  --fresh             Delete dir and re-clone (destructive)
  -h, --help          Show this help

Examples:
  bash scripts/bootstrap-run-prod.sh
  bash scripts/bootstrap-run-prod.sh --fresh
  bash scripts/bootstrap-run-prod.sh -- --sync-hard
EOF
}

REPO_URL="https://github.com/SumNic/activitywatch.git"
BRANCH="master"
FORK_USER="SumNic"
FRESH=0

DEFAULT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/activitywatch-run-prod"
TARGET_DIR="$DEFAULT_DIR"

RUNPROD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --dir) TARGET_DIR="${2:-}"; shift 2 ;;
    --fork-user) FORK_USER="${2:-}"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      RUNPROD_ARGS+=("$@")
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git

if [[ "$FRESH" -eq 1 && -e "$TARGET_DIR" ]]; then
  rm -rf "$TARGET_DIR"
fi

if [[ -d "$TARGET_DIR/.git" ]]; then
  cd "$TARGET_DIR"
  git remote set-url origin "$REPO_URL" >/dev/null 2>&1 || true
  git fetch origin "$BRANCH"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
  else
    git checkout -b "$BRANCH" --track "origin/$BRANCH"
  fi
  git reset --hard "origin/$BRANCH"
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

exec env FORK_USER="$FORK_USER" ./run-prod.sh --sync --sync-hard "${RUNPROD_ARGS[@]}"

