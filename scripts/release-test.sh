#!/bin/bash
# M7-5: release.sh refuses a dirty tree, an ad hoc identity and an existing tag with one line, writing nothing.
# Runs HEAD's release.sh in a scratch worktree, so commit first. A v1.0.0 tag it makes is deleted; a real one is left alone.
set -uo pipefail
cd "$(dirname "$0")/.."
W=$(mktemp -d)/wt
git worktree add -q --detach "$W" HEAD || exit 1
made_tag=0
cleanup() { [ $made_tag = 1 ] && git tag -d v1.0.0 >/dev/null; git worktree remove --force "$W"; rm -rf "$(dirname "$W")"; }
trap cleanup EXIT
fails=0
# refuses <row> <reason> <command...>
refuses() {
  local row=$1 want=$2 out code; shift 2
  out=$("$@" 2>&1); code=$?
  if [ $code -ne 0 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && [[ "$out" == *"$want"* ]] && ! ls -d "$W"/build/Swivel-1.0.0* >/dev/null 2>&1; then
    echo "PASS $row"
  else
    echo "FAIL $row: exit $code, '$out'"; fails=$((fails + 1))
  fi
}
touch "$W/untracked"
refuses "M7-5 dirty tree" "working tree is dirty" "$W/scripts/release.sh"
rm "$W/untracked"
refuses "M7-5 ad hoc" "not Swivel Dev" env SWIVEL_IDENTITY=- "$W/scripts/release.sh"
if ! git rev-parse -q --verify refs/tags/v1.0.0 >/dev/null; then git tag v1.0.0 HEAD && made_tag=1; fi
refuses "M7-5 tag exists" "tag v1.0.0 already exists" env SWIVEL_IDENTITY="Swivel Dev" "$W/scripts/release.sh"
echo "$fails failed"
exit $((fails > 0))
