#!/usr/bin/env bash
# Local maintenance for the mzane42/socai fork: keep ~/.socai/bin/socai on the latest
# upstream release WITH our patches (branch fix/tiktok-sidebar-search).
#
#   scripts/local-update.sh          rebase on a new upstream tag if any, rebuild if the
#                                    installed binary lacks the patch, else do nothing
#   scripts/local-update.sh --force  rebuild and reinstall even when up to date
#
# Never pushes. After a rebase, push yourself: git push --force-with-lease origin fix/tiktok-sidebar-search
set -euo pipefail

BRANCH=fix/tiktok-sidebar-search
BIN="$HOME/.socai/bin/socai"
MARKER='URL also proves the query'   # comment embedded in the patched page_scripts.js
QUERY_CHECK=core/src/sites/tiktok/page_scripts.js
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export SOCAI_TELEMETRY=0 SOCAI_TELEMETRY_QUERY_TEXT=0 SOCAI_NO_UPDATE_CHECK=1

die() { echo "local-update: $*" >&2; exit 1; }
patched() { [ -f "$1" ] && grep -aq "$MARKER" "$1"; }
version() { "$1" --version 2>/dev/null | awk '{print "v"$2}'; }

cd "$(dirname "$0")/.."
git checkout -q -- Cargo.lock 2>/dev/null || true   # upstream's lock lags a version; cargo rewrites it
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes in $(pwd), commit or stash first."
git checkout -q "$BRANCH"
git fetch -q upstream --tags

base=$(git describe --tags --abbrev=0 "$BRANCH")
latest=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -v -- '-' | head -1)
installed=$(version "$BIN" || true)
echo "patch base: $base | latest upstream: $latest | installed: ${installed:-none}$(patched "$BIN" && echo ' (patched)' || echo ' (NOT patched)')"

if [ "$latest" != "$base" ]; then
  # Did upstream touch the TikTok query check? Then our patch may be obsolete: review before keeping it.
  if git diff "$base" "$latest" -- "$QUERY_CHECK" | grep -q 'queryHydrated\|visibleQuery'; then
    echo "WARNING: upstream changed the TikTok query check between $base and $latest."
    echo "         Check whether socai-io fixed the sidebar search; if so, drop the patch instead of rebasing."
    echo "         git diff $base $latest -- $QUERY_CHECK"
  fi
  echo "rebasing $BRANCH from $base onto $latest"
  git rebase -q --onto "$latest" "$base" "$BRANCH" || { git rebase --abort; die "rebase conflict: resolve by hand (git rebase --onto $latest $base $BRANCH)."; }
elif [ "${1:-}" != "--force" ] && [ "$installed" = "$base" ] && patched "$BIN"; then
  echo "up to date, nothing to do."
  exit 0
fi

echo "building socai-cli (release)…"
cargo build --release -q -p socai-cli
git checkout -q -- Cargo.lock
built=target/release/socai
patched "$built" || die "built binary lacks the patch marker; not installing."
[ "$(version "$built")" = "$latest" ] || die "built $(version "$built"), expected $latest; not installing."

"$BIN" stop >/dev/null 2>&1 || true
[ -f "$BIN" ] && cp -p "$BIN" "$BIN.previous"
cp "$built" "$BIN"
patched "$BIN" && [ "$(version "$BIN")" = "$latest" ] || die "install check failed; previous binary kept at $BIN.previous."
echo "installed $latest (patched) → $BIN   (previous: $BIN.previous)"
[ "$latest" != "$base" ] && echo "now push the rebased branch: git push --force-with-lease origin $BRANCH"
exit 0
