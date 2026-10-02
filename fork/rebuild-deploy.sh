#!/usr/bin/env bash
# Rebuild the `deploy` branch: the latest upstream release tag, every branch in
# fork/carried-branches.txt cherry-picked on top, then the fork's own files.
#
#   fork/rebuild-deploy.sh            # latest release
#   fork/rebuild-deploy.sh v0.17.0    # a specific release
#
# Remotes: `origin` is securo-finance/securo, `fork` is rhuanbarreto/securo.
# Run it from a checkout of `deploy`: the carry list and the fork's own files
# are taken from that commit, so a carry-list edit committed locally is picked up
# before anything is pushed. The result is local; review it, then
# `git push --force-with-lease fork deploy`.
# A cherry-pick conflict stops the script: resolve it, `git cherry-pick
# --continue`, and run the remaining steps by hand.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = deploy ] || { echo "Run this on the deploy branch." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or discard local changes first." >&2; exit 1; }
source_commit="$(git rev-parse HEAD)"
git fetch --quiet --tags origin
git fetch --quiet fork

tag="${1:-$(git tag --list 'v*' --sort=-v:refname | head -n1)}"
fork_files=(FORK.md fork .github/workflows/fork-images.yml)

mapfile -t branches < <(git show "$source_commit:fork/carried-branches.txt" | grep -Ev '^\s*(#|$)')

echo "Base: $tag"
git switch --quiet --force-create deploy "$tag"

for b in "${branches[@]}"; do
  range="origin/main..fork/$b"
  count="$(git rev-list --count "$range")"
  if [ "$count" -eq 0 ]; then
    echo "  $b: nothing beyond upstream main, remove it from the carry list"
    continue
  fi
  merged="$(gh pr list -R securo-finance/securo --head "$b" --state merged --json number -q '.[0].number' 2>/dev/null || true)"
  if [ -n "$merged" ]; then
    echo "  $b: merged upstream as #$merged; carried until a release includes it"
  fi
  echo "  $b: cherry-picking $count commit(s)"
  git cherry-pick "$range"
done

git checkout "$source_commit" -- "${fork_files[@]}"
git commit --quiet -m "chore(fork): build and deploy images from this branch"
echo "Done. Review with: git log --oneline $tag..deploy"
