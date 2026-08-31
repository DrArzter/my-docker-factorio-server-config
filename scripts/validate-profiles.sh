#!/usr/bin/env bash

set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
schema="${repository_root}/profiles/schema.json"

for command in docker jq; do
  command -v "${command}" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "${command}" >&2
    exit 1
  }
done

# A newline-delimited membership list instead of an associative array, so the
# script also runs on the bash 3.2 that macOS ships.
seen_ids=$'\n'
profile_count=0

while IFS= read -r profile; do
  profile_directory="$(dirname -- "${profile}")"
  profile_id="$(jq -er '.id' "${profile}")"
  directory_id="$(basename -- "${profile_directory}")"

  jq -e --slurpfile schema "${schema}" '
    .schema_version == $schema[0].properties.schema_version.const
    and (.id | test($schema[0].properties.id.pattern))
    and (.display_name | type == "string" and length > 0)
    and (.gameplay == "modded" or .gameplay == "vanilla-like")
    and .game == "factorio"
    and (.factorio_version | type == "string" and test("^[0-9]+(\\.[0-9]+)*$"))
    and .loader.type == "factorio"
    and .loader.version == null
    and .compose_file == "compose.yaml"
  ' "${profile}" >/dev/null

  [[ "${profile_id}" == "${directory_id}" ]] || {
    printf 'error: profile id %s must match directory %s\n' "${profile_id}" "${directory_id}" >&2
    exit 1
  }
  [[ "${seen_ids}" != *$'\n'"${profile_id}"$'\n'* ]] || {
    printf 'error: duplicate profile id: %s\n' "${profile_id}" >&2
    exit 1
  }
  seen_ids="${seen_ids}${profile_id}"$'\n'

  compose_file="${profile_directory}/$(jq -r '.compose_file' "${profile}")"
  [[ -f "${compose_file}" ]] || {
    printf 'error: missing Compose file for %s\n' "${profile_id}" >&2
    exit 1
  }

  # A pin list is exact name:version lines — the resolver's own contract.
  mods_source="$(jq -r '.mods.source // empty' "${profile}")"
  if [[ -n "${mods_source}" ]]; then
    [[ -f "${profile_directory}/${mods_source}" ]] || {
      printf 'error: missing mod source for %s: %s\n' "${profile_id}" "${mods_source}" >&2
      exit 1
    }
    bad_pins="$(grep -Ev '^[[:space:]]*(#|$)' "${profile_directory}/${mods_source}" \
      | grep -Ev '^[A-Za-z0-9_-]+:[0-9]+(\.[0-9]+)*$' || true)"
    [[ -z "${bad_pins}" ]] || {
      printf 'error: malformed mod pins for %s:\n%s\n' "${profile_id}" "${bad_pins}" >&2
      exit 1
    }
  fi

  rendered="$(
    docker compose \
      --project-directory "${profile_directory}" \
      -f "${compose_file}" \
      config --format json
  )"
  factorio_version="$(jq -r '.factorio_version' "${profile}")"
  # profile_directory is already absolute; plain concatenation avoids GNU
  # realpath flags the macOS userland does not have.
  expected_data_directory="${profile_directory}/data"

  # The image tag IS the runtime version — the engine has no separate loader —
  # so the profile's factorio_version and the Compose file must agree.
  jq -e \
    --arg factorio_version "${factorio_version}" \
    --arg expected_data_directory "${expected_data_directory}" '
      (.services.factorio.image | endswith(":" + $factorio_version))
      and any(.services.factorio.volumes[]; .target == "/factorio" and .source == $expected_data_directory)
      and any(.services.factorio.ports[]; .target == 34197 and .protocol == "udp")
      and any(.services.factorio.ports[]; .target == 27015 and .host_ip == "127.0.0.1")
      and .services.factorio.restart == "no"
    ' <<<"${rendered}" >/dev/null

  printf 'profile=%s result=valid\n' "${profile_id}"
  profile_count=$((profile_count + 1))
done < <(find "${repository_root}/profiles" -mindepth 2 -maxdepth 2 -name profile.json -type f | sort)

(( profile_count > 0 )) || {
  printf 'error: no profiles found\n' >&2
  exit 1
}

printf 'result=passed profiles=%d\n' "${profile_count}"
