#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$REPO_DIR/.env.example"

for command_name in curl jq sed sort; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

current_version=$(sed -n 's/^CONTINUWUITY_VERSION=//p' "$ENV_FILE")
release_json=$(curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  https://forgejo.ellis.link/api/v1/repos/continuwuation/continuwuity/releases/latest)
latest_version=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$release_json")

if [[ ! $current_version =~ ^v[0-9] ]] || [[ ! $latest_version =~ ^v[0-9] ]]; then
  echo "Current or upstream Continuwuity release is invalid." >&2
  exit 1
fi

if [[ $latest_version != "$current_version" ]] && \
  [[ $(printf '%s\n%s\n' "$latest_version" "$current_version" | sort --version-sort | head -n 1) == "$latest_version" ]]; then
  echo "Upstream reports older Continuwuity release $latest_version; refusing an automatic downgrade." >&2
  exit 1
fi

sed -i "s/$current_version/$latest_version/g" "$ENV_FILE" "$REPO_DIR/README.md"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "old_version=$current_version"
    echo "new_version=$latest_version"
  } >>"$GITHUB_OUTPUT"
fi

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  {
    echo "## Continuwuity update check"
    echo
    echo "- Continuwuity: \`$current_version\` → \`$latest_version\`"
  } >>"$GITHUB_STEP_SUMMARY"
fi

printf 'Continuwuity: %s -> %s\n' "$current_version" "$latest_version"
