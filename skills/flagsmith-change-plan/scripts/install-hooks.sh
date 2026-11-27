#!/usr/bin/env bash
# install-hooks.sh: installs the post-commit hook that turns `git revert` of a flag change into an undo offer.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
cd "$(repo_root)"

hooks_dir=$(git rev-parse --git-path hooks)
current=$(git config --get core.hooksPath || true)
[[ -n $current ]] && hooks_dir=$current
mkdir -p "$hooks_dir"
target="$hooks_dir/post-commit"

if [[ -f $target ]] && ! grep -q 'flagsmith-change-plan' "$target"; then
  die "$target exists and is not ours: add this line to it instead: bash \"$here/hooks/post-commit\""
fi
printf '#!/usr/bin/env bash\n# flagsmith-change-plan\nexec bash "%s/hooks/post-commit"\n' "$here" > "$target"
chmod +x "$target"
printf 'installed: %s -> %s/hooks/post-commit\n' "$target" "${here#"$PWD"/}"
