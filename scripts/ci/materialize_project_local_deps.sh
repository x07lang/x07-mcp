#!/usr/bin/env bash
set -euo pipefail

CALLER_PWD="${PWD}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
x07_root_resolver="${ROOT}/scripts/ci/resolve_workspace_x07_root.sh"

project="${1:-}"
if [[ -z "${project}" ]]; then
  echo "usage: materialize_project_local_deps.sh <project-x07.json>" >&2
  exit 2
fi

if [[ "${project}" = /* ]]; then
  project_abs="${project}"
elif [[ -f "${CALLER_PWD}/${project}" ]]; then
  project_abs="${CALLER_PWD}/${project}"
else
  project_abs="${ROOT}/${project}"
fi

if [[ ! -f "${project_abs}" ]]; then
  echo "ERROR: project manifest not found: ${project}" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "${project_abs}")" && pwd)"
project_abs="${project_dir}/$(basename "${project_abs}")"
cd "${ROOT}"
workspace_root="${X07_WORKSPACE_ROOT:-${ROOT}}"
refresh_local_deps="${X07_MCP_LOCAL_DEPS_REFRESH:-0}"
use_pkg_add="${X07_MCP_LOCAL_USE_PKG_ADD:-0}"

resolve_workspace_x07_root_or_fail() {
  local stderr_log
  local resolved=""
  local status=0

  stderr_log="$(mktemp)"
  set +e
  resolved="$("${x07_root_resolver}" 2>"${stderr_log}")"
  status=$?
  set -e

  if [[ "${status}" -ne 0 || -z "${resolved}" || ! -d "${resolved}" ]]; then
    cat "${stderr_log}" >&2 || true
    rm -f "${stderr_log}"
    echo "ERROR: local-deps mode requires a clean x07 checkout at the pinned tag" >&2
    exit 2
  fi

  rm -f "${stderr_log}"
  printf '%s\n' "${resolved}"
}

WORKSPACE_X07_ROOT="$(resolve_workspace_x07_root_or_fail)"

copy_local_pkg_if_present() {
  local name="$1"
  local version="$2"
  local target_dir="$3"
  local candidate=""
  local candidate_abs=""
  local target_abs=""
  local candidates=(
    "${ROOT}/packages/ext/x07-${name}/${version}"
    "${WORKSPACE_X07_ROOT}/packages/ext/x07-${name}/${version}"
  )

  for candidate in "${candidates[@]}"; do
    if [[ ! -d "${candidate}" ]]; then
      continue
    fi
    mkdir -p "$(dirname "${target_dir}")"
    mkdir -p "${target_dir}"
    candidate_abs="$(cd "${candidate}" && pwd -P)"
    target_abs="$(cd "${target_dir}" && pwd -P)"
    if [[ "${candidate_abs}" == "${target_abs}" ]]; then
      return 0
    fi
    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"
    (
      cd "${candidate}"
      tar -cf - .
    ) | (
      cd "${target_dir}"
      tar -xf -
    )
    return 0
  done

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

resolve_dependency_path() {
  local path_value="$1"
  if [[ "${path_value}" == \$workspace* ]]; then
    printf '%s\n' "${workspace_root}${path_value#\$workspace}"
  elif [[ "${path_value}" = /* ]]; then
    printf '%s\n' "${path_value}"
  else
    printf '%s\n' "${project_dir}/${path_value}"
  fi
}

materialized_any=0
while IFS=$'\t' read -r name version path_value; do
  [[ -n "${name}" && -n "${version}" && -n "${path_value}" ]] || continue

  local_pkg_add_path=".x07/local/${name}/${version}"
  target_path="$(resolve_dependency_path "${path_value}")"
  if [[ "${use_pkg_add}" == "1" ]]; then
    target_path="${project_dir}/${local_pkg_add_path}"
  fi

  if [[ -d "${target_path}" && "${refresh_local_deps}" != "1" ]]; then
    continue
  fi

  if ! copy_local_pkg_if_present "${name}" "${version}" "${target_path}"; then
    download_package_via_temp_project "${name}" "${version}" "${target_path}"
  fi

  echo "INFO: materializing local dependency ${name}@${version} at ${target_path}" >&2
  materialized_any=1

  if [[ "${use_pkg_add}" == "1" ]]; then
    (
      cd "${project_dir}"
      x07 pkg remove "${name}" >/dev/null 2>&1 || true
      x07 pkg add "${name}@${version}" --path "${local_pkg_add_path}" >/dev/null
    )
  fi
done < <(jq -r '.dependencies[]? | [.name, .version, .path] | @tsv' "${project_abs}")

if [[ "${materialized_any}" == "1" ]]; then
  echo "ok: local dependency paths are materialized for ${project}" >&2
fi
