#!/usr/bin/env bash
# Refresh the digest pins of every base image in the two Dockerfiles.
#
# The images pin by digest on purpose (supply-chain control, threat model T7). The price
# of that pin is that Debian security patches only arrive when the pin moves and the
# image is rebuilt. When the image scanner reports patched OS packages, run:
#
#   make bump-base-images   # updates the FROM digests below
#   make deploy-demo        # rebuild + redeploy (or your pinned deploy)
#
# Requires a container tool (finch or docker) that can pull from public.ecr.aws.
set -euo pipefail

TOOL="${CONTAINER_TOOL:-${CDK_DOCKER:-finch}}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

bump_file() {
  local dockerfile="$1"
  echo "== $dockerfile"
  # Every unique digest-pinned image reference in FROM lines.
  grep -E '^FROM [^ ]+@sha256:' "$dockerfile" | awk '{print $2}' | sort -u | while read -r ref; do
    local repo="${ref%%@*}"
    local old="${ref##*@}"
    "$TOOL" pull -q "$repo" >/dev/null
    local new
    new="$("$TOOL" image inspect "$repo" --format '{{index .RepoDigests 0}}' | sed 's/.*@//')"
    if [ -z "$new" ]; then
      echo "   could not resolve a digest for $repo" >&2
      exit 1
    fi
    if [ "$old" = "$new" ]; then
      echo "   unchanged: $repo"
    else
      python3 - "$dockerfile" "$repo" "$old" "$new" <<'EOF'
import sys
path, repo, old, new = sys.argv[1:5]
src = open(path).read()
open(path, "w").write(src.replace(f"{repo}@{old}", f"{repo}@{new}"))
EOF
      echo "   bumped:    $repo"
      echo "              $old"
      echo "           -> $new"
    fi
  done
}

stamp_file() {
  # Move OS_PATCH_STAMP to today so the apt-upgrade layer cannot replay from cache,
  # even when the base digest itself is unchanged.
  local dockerfile="$1"
  python3 - "$dockerfile" "$(date -u +%Y-%m-%d)" <<'EOF'
import re, sys
path, today = sys.argv[1:3]
src = open(path).read()
open(path, "w").write(re.sub(r"ARG OS_PATCH_STAMP=\S+", f"ARG OS_PATCH_STAMP={today}", src))
EOF
  echo "   stamped:   $dockerfile -> $(date -u +%Y-%m-%d)"
}

cd "$REPO_ROOT"
bump_file frontend/Dockerfile
stamp_file frontend/Dockerfile
bump_file agent/Dockerfile
stamp_file agent/Dockerfile
echo "Done. Review the diff, then rebuild and deploy."
