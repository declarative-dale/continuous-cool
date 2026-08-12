#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_DIR"

docker compose --env-file .env.example config --quiet

ruby <<'RUBY'
require "yaml"

compose = YAML.safe_load_file("compose.yaml", aliases: false)
services = compose.fetch("services")
raise "expected only the continuwuity service" unless services.keys == ["continuwuity"]

service = services.fetch("continuwuity")
raise "host ports must not be published" if service.key?("ports")
raise "custom networks are not allowed" if compose.key?("networks")
raise "registration must remain disabled" unless service.dig("environment", "CONTINUWUITY_ALLOW_REGISTRATION") == "false"
raise "federation must remain enabled" unless service.dig("environment", "CONTINUWUITY_ALLOW_FEDERATION") == "true"
raise "persistent volume mapping changed" unless service.fetch("volumes") == ["continuwuity-data:/var/lib/continuwuity"]
raise "image must remain explicitly versioned" if service.fetch("image").end_with?(":latest")
RUBY

if git ls-files | grep -Eq '(^|/)(registration\.ya?ml|ooye\.db([.-].*)?|\.env)$'; then
  echo "A runtime secret or database file is tracked by Git." >&2
  exit 1
fi

echo "Repository validation passed."
