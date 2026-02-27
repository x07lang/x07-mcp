#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path('.').resolve()
errors: list[str] = []
PLACEHOLDER_SHA256 = "0000000000000000000000000000000000000000000000000000000000000000"


def _is_nonempty_str(value: object) -> bool:
    return isinstance(value, str) and bool(value)


for manifest_path in sorted((ROOT / 'servers').glob('*/x07.mcp.json')):
    doc = json.loads(manifest_path.read_text(encoding='utf-8'))
    publish = doc.get('publish') if isinstance(doc, dict) else None
    if not isinstance(publish, dict):
        continue
    tf = publish.get('trust_framework')
    if not isinstance(tf, dict):
        continue
    if not bool(tf.get('emit_meta_summary', False)):
        continue

    tf_path_raw = tf.get('path')
    lock_path_raw = tf.get('trust_lock_path') or tf.get('lock_path')

    if not _is_nonempty_str(tf_path_raw):
        errors.append(f'{manifest_path}: publish.trust_framework.path missing')
        continue
    if not _is_nonempty_str(lock_path_raw):
        errors.append(f'{manifest_path}: publish.trust_framework.trust_lock_path missing')
        continue

    tf_path = (manifest_path.parent / tf_path_raw).resolve()
    lock_path = (manifest_path.parent / lock_path_raw).resolve()
    if not tf_path.is_file():
        errors.append(f'{manifest_path}: trust framework file not found: {tf_path_raw}')
        continue
    if not lock_path.is_file():
        errors.append(f'{manifest_path}: trust lock file not found: {lock_path_raw}')
        continue

    framework = json.loads(tf_path.read_text(encoding='utf-8'))
    framework_schema = framework.get('schema_version')
    if framework_schema not in {
        'x07.mcp.trust.framework@0.2.0',
        'x07.mcp.trust.framework@0.3.0',
    }:
        errors.append(
            f'{manifest_path}: trust framework schema_version must be '
            'x07.mcp.trust.framework@0.2.0 or @0.3.0'
        )
        continue

    lock = json.loads(lock_path.read_text(encoding='utf-8'))
    lock_schema = lock.get('schema_version')
    if lock_schema not in {
        'x07.mcp.trust.lock@0.1.0',
        'x07.mcp.trust.lock@0.2.0',
    }:
        errors.append(
            f'{manifest_path}: trust lock schema_version must be '
            'x07.mcp.trust.lock@0.1.0 or @0.2.0'
        )
        continue

    if framework_schema == 'x07.mcp.trust.framework@0.2.0' and lock_schema != 'x07.mcp.trust.lock@0.1.0':
        errors.append(f'{manifest_path}: framework@0.2.0 requires lock@0.1.0')
        continue
    if framework_schema == 'x07.mcp.trust.framework@0.3.0' and lock_schema != 'x07.mcp.trust.lock@0.2.0':
        errors.append(f'{manifest_path}: framework@0.3.0 requires lock@0.2.0')
        continue

    lock_bundles = lock.get('bundles')
    if not isinstance(lock_bundles, list) or not lock_bundles:
        errors.append(f'{manifest_path}: trust lock bundles[] missing')
        continue
    lock_by_id: dict[str, dict] = {}
    for item in lock_bundles:
        if isinstance(item, dict) and isinstance(item.get('id'), str):
            lock_by_id[item['id']] = item

    bundles = framework.get('bundles')
    if not isinstance(bundles, list) or not bundles:
        errors.append(f'{manifest_path}: trust framework bundles[] missing')
        continue

    for idx, bundle in enumerate(bundles):
        if not isinstance(bundle, dict):
            continue

        bundle_id = bundle.get('id')
        if not _is_nonempty_str(bundle_id):
            errors.append(f'{manifest_path}: framework.bundles[{idx}].id missing')
            continue

        require_signature = bool(bundle.get('require_signature', False))

        if framework_schema == 'x07.mcp.trust.framework@0.2.0':
            if not require_signature:
                continue

            sig_rel = bundle.get('sig_jwt_path')
            if not _is_nonempty_str(sig_rel):
                errors.append(f'{manifest_path}: framework.bundles[{idx}].sig_jwt_path missing')
                continue

            sig_path = (tf_path.parent / sig_rel).resolve()
            if not sig_path.is_file():
                errors.append(f'{manifest_path}: signature jwt missing for {bundle_id}: {sig_rel}')

            lock_entry = lock_by_id.get(bundle_id)
            if not isinstance(lock_entry, dict):
                errors.append(f'{manifest_path}: trust lock missing bundle entry id={bundle_id}')
                continue
            if lock_entry.get('sig_jwt_path') != sig_rel:
                errors.append(f'{manifest_path}: trust lock sig_jwt_path mismatch for id={bundle_id}')
            continue

        source = bundle.get('source') if isinstance(bundle.get('source'), dict) else {}
        sig_source = bundle.get('sig_source') if isinstance(bundle.get('sig_source'), dict) else {}
        source_kind = source.get('kind') if isinstance(source.get('kind'), str) else ''
        sig_kind = sig_source.get('kind') if isinstance(sig_source.get('kind'), str) else ''

        if require_signature and sig_kind == 'file':
            sig_rel = sig_source.get('path')
            if not _is_nonempty_str(sig_rel):
                errors.append(f'{manifest_path}: framework.bundles[{idx}].sig_source.path missing')
            else:
                sig_path = (tf_path.parent / sig_rel).resolve()
                if not sig_path.is_file():
                    errors.append(f'{manifest_path}: signature file missing for {bundle_id}: {sig_rel}')

        needs_lock = require_signature or source_kind == 'url' or sig_kind == 'url'
        if not needs_lock:
            continue

        lock_entry = lock_by_id.get(bundle_id)
        if not isinstance(lock_entry, dict):
            errors.append(f'{manifest_path}: trust lock missing bundle entry id={bundle_id}')
            continue

        if source_kind == 'url' and lock_entry.get('bundle_url') != source.get('url'):
            errors.append(f'{manifest_path}: trust lock bundle_url mismatch for id={bundle_id}')
        if sig_kind == 'url' and lock_entry.get('sig_url') != sig_source.get('url'):
            errors.append(f'{manifest_path}: trust lock sig_url mismatch for id={bundle_id}')

publish_server_docs: list[Path] = []
publish_server_docs.extend(sorted((ROOT / 'templates').glob('*/publish/server.json')))
publish_server_docs.extend(sorted((ROOT / 'servers').glob('*/publish/server.json')))

for server_path in publish_server_docs:
    doc = json.loads(server_path.read_text(encoding='utf-8'))
    meta = (
        doc.get('_meta', {})
        .get('io.modelcontextprotocol.registry/publisher-provided', {})
        .get('x07', {})
    )
    if not isinstance(meta, dict):
        errors.append(f'{server_path}: missing _meta publisher-provided x07 block')
        continue
    trust_lock_sha = meta.get('trustLockSha256')
    if not isinstance(trust_lock_sha, str) or not trust_lock_sha:
        errors.append(f'{server_path}: trustLockSha256 missing')
        continue
    if trust_lock_sha == PLACEHOLDER_SHA256:
        errors.append(f'{server_path}: trustLockSha256 is placeholder all-zero value')

    trust_pack = meta.get('trustPack') if isinstance(meta.get('trustPack'), dict) else None
    if trust_pack is not None:
        pack_version = trust_pack.get('packVersion')
        if not _is_nonempty_str(pack_version):
            errors.append(f'{server_path}: trustPack.packVersion missing')
        lock_sha = trust_pack.get('lockSha256')
        if not _is_nonempty_str(lock_sha):
            errors.append(f'{server_path}: trustPack.lockSha256 missing')
        elif lock_sha == PLACEHOLDER_SHA256:
            errors.append(f'{server_path}: trustPack.lockSha256 is placeholder all-zero value')

if errors:
    for e in errors:
        print(f'ERROR: {e}')
    raise SystemExit(1)

print('ok: release guard trust lock + bundle sig checks passed')
PY
