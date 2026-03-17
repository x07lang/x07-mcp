#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
x07_root_resolver="${ROOT}/scripts/ci/resolve_workspace_x07_root.sh"

project="${1:-}"
if [[ -z "${project}" ]]; then
  echo "usage: materialize_patch_deps.sh <project-x07.json>" >&2
  exit 2
fi

if [[ "${project}" = /* ]]; then
  project_abs="${project}"
else
  project_abs="${ROOT}/${project}"
fi

if [[ ! -f "${project_abs}" ]]; then
  echo "ERROR: project manifest not found: ${project}" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "${project_abs}")" && pwd)"
workspace_root="${X07_WORKSPACE_ROOT:-${ROOT}}"
use_workspace_patch_deps="${X07_MCP_USE_WORKSPACE_PATCH_DEPS:-1}"
workspace_x07_root=""
if [[ "${use_workspace_patch_deps}" == "1" ]]; then
  workspace_x07_root="$("${x07_root_resolver}" 2>/dev/null || true)"
fi

copy_local_package_if_present() {
  local name="$1"
  local version="$2"
  local target_dir="$3"
  local candidate

  for candidate in "${ROOT}/packages/ext/x07-${name}/${version}"; do
    if [[ -d "${candidate}" ]]; then
      mkdir -p "$(dirname "${target_dir}")"
      rm -rf "${target_dir}"
      cp -R "${candidate}" "${target_dir}"
      return 0
    fi
  done

  if [[ "${use_workspace_patch_deps}" == "1" ]]; then
    candidate="${workspace_x07_root}/packages/ext/x07-${name}/${version}"
    if [[ -d "${candidate}" ]]; then
      mkdir -p "$(dirname "${target_dir}")"
      rm -rf "${target_dir}"
      cp -R "${candidate}" "${target_dir}"
      return 0
    fi
  fi

  return 1
}

download_package_via_temp_project() {
  local name="$1"
  local version="$2"
  local target_dir="$3"
  local tmp
  local src

  tmp="$(mktemp -d)"
  jq -n \
    --arg name "${name}" \
    --arg version "${version}" \
    '{
      "schema_version": "x07.project@0.4.0",
      "default_profile": "os",
      "dependencies": [
        {
          "name": $name,
          "version": $version,
          "path": (".x07/deps/" + $name + "/" + $version)
        }
      ],
      "entry": "main.x07.json",
      "module_roots": ["."],
      "profiles": {
        "os": { "world": "run-os" }
      },
      "world": "run-os"
    }' >"${tmp}/x07.json"

  (
    cd "${tmp}"
    x07 pkg lock --project x07.json --json=off >/dev/null
  )

  src="${tmp}/.x07/deps/${name}/${version}"
  if [[ ! -d "${src}" ]]; then
    echo "ERROR: failed to materialize ${name}@${version} in temp lock project" >&2
    rm -rf "${tmp}"
    exit 1
  fi

  mkdir -p "$(dirname "${target_dir}")"
  rm -rf "${target_dir}"
  cp -R "${src}" "${target_dir}"
  rm -rf "${tmp}"
}

materialized_any=0
while IFS=$'\t' read -r name version path_value; do
  [[ -n "${name}" ]] || continue
  [[ -n "${path_value}" ]] || continue

  if [[ -z "${version}" ]]; then
    version="$(jq -r --arg name "${name}" '.dependencies[]? | select(.name == $name) | .version' "${project_abs}" | head -n 1)"
  fi
  if [[ -z "${version}" || "${version}" == "null" ]]; then
    echo "ERROR: patch entry has no version for ${name} in ${project}" >&2
    exit 2
  fi

  patch_path="${path_value}"
  if [[ "${patch_path}" == \$workspace* ]]; then
    patch_path="${workspace_root}${patch_path#\$workspace}"
  elif [[ "${patch_path}" != /* ]]; then
    patch_path="${project_dir}/${patch_path}"
  fi

  if [[ -d "${patch_path}" ]]; then
    continue
  fi

  echo "INFO: materializing patched dependency ${name}@${version} at ${patch_path}" >&2
  if ! copy_local_package_if_present "${name}" "${version}" "${patch_path}"; then
    download_package_via_temp_project "${name}" "${version}" "${patch_path}"
  fi
  materialized_any=1
done < <(jq -r '.patch // {} | to_entries[] | [.key, (.value.version // ""), (.value.path // "")] | @tsv' "${project_abs}")

if [[ "${materialized_any}" == "1" ]]; then
  echo "ok: patched dependency paths are materialized for ${project}" >&2
fi
