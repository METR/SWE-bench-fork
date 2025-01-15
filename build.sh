#!/usr/bin/env bash
set -eu

###############################################################################
# CONFIGURATION
###############################################################################
VERSION="0.0.1"

# Use DRY_RUN="echo" to only print commands instead of running them.
DRY_RUN=""
#DRY_RUN="echo"

# TODO: build Python. We don't ned to do this right now

###############################################################################
# 1. Fetch all Docker tags from Docker Hub for metrevals/swebench
#    (We assume you have jq installed.)
###############################################################################
all_tags=$(next_url="https://hub.docker.com/v2/repositories/metrevals/swebench/tags/?page_size=100" ; while [ ! -z "$next_url" ]; do response=$(curl -s "$next_url?page_size=100"); echo "$response" | jq -r '.results[].name'; next_url=$(echo "$response" | jq -r '.next | select(. != null)'); done)
#all_tags=$(curl -s "https://hub.docker.com/v2/repositories/metrevals/swebench/tags/?page_size=100" | jq -r '.results[].name')


###############################################################################
# 2. Filter tags that contain 'sweb.eval.', and that don't have versions, and are on x86_64
###############################################################################
candidate_tags=$(echo "$all_tags" | grep 'sweb.eval.')
candidate_tags=$(echo "$candidate_tags" | grep -v -E '[0-9]+\.[0-9]+\.[0-9]+')


map_platform() {
    local platform=$1
    case "$platform" in
        "arm64")
            echo "linux/arm64/v8"
            ;;
        "x86_64")
            echo "linux/x86_64"
            ;;
        *)
            echo "Unknown platform: $platform" >&2
            exit 1
            ;;
    esac
}


# Count total number of tags
total_tags=$(echo "$candidate_tags" | wc -l)
echo "Found $total_tags tags that match 'sweb.eval.'"

###############################################################################
# 3. Loop over each matching tag
###############################################################################
current_tag=0
for tag in $candidate_tags; do
  ((current_tag++))
  echo "Processing tag [$current_tag/$total_tags]: $tag"


  # The format of the tag is sweb.eval.arm64.astropy__astropy-14995
  # So we pull out the platform from this
  platform=$(echo "$tag" | cut -d. -f3)
  echo "  --> Platform: $platform"


  # Map the platform to Docker platform string
  docker_platform=$(map_platform "$platform")
  echo "  --> Docker platform: $docker_platform"

  # Construct the new tag by appending ".$VERSION"
  # e.g. sweb.eval.arm64.astropy__astropy-14995.0.0.1
  new_tag="${tag}.${VERSION}"

  # 4. Build a new image on top of the existing one
  #    If you really need --platform <platform>, you can add that to docker build.
  #    For example:
  #        --platform "linux/arm64"   or   --platform "linux/amd64"
  #    But you'd have to map 'arm64' → 'linux/arm64', etc.
  $DRY_RUN cat <<EOF | DOCKER_BUILDKIT=1 docker build \
    -t "metrevals/swebench:$new_tag" \
    --push \
    --platform "$docker_platform" \
    -
FROM metrevals/swebench:$tag
# Example: install extra packages, tweak environment, etc.
RUN apt update && apt install -y \
    bash \
    coreutils \
    file \
    findutils \
    gawk \
    git \
    grep \
    jq \
    make \
    sed \
    wget
RUN pip install --break-system-packages flake8
EOF

  echo "  --> Built and pushed metrevals/swebench:$new_tag"
  echo
done