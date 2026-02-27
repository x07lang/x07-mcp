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

    if not isinstance(tf_path_raw, str) or not tf_path_raw:
        errors.append(f'{manifest_path}: publish.trust_framework.path missing')
        continue
    if not isinstance(lock_path_raw, str) or not lock_path_raw:
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
    if framework.get('schema_version') != 'x07.mcp.trust.framework@0.2.0':
        errors.append(f'{manifest_path}: trust framework schema_version must be x07.mcp.trust.framework@0.2.0')
        continue

    lock = json.loads(lock_path.read_text(encoding='utf-8'))
    if lock.get('schema_version') != 'x07.mcp.trust.lock@0.1.0':
        errors.append(f'{manifest_path}: trust lock schema_version must be x07.mcp.trust.lock@0.1.0')
        continue

    lock_bundles = lock.get('bundles')
    if not isinstance(lock_bundles, list) or not lock_bundles:
        errors.append(f'{manifest_path}: trust lock bundles[] missing')
        continue
    lock_by_id = {}
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
        if not bool(bundle.get('require_signature', False)):
            continue

        bundle_id = bundle.get('id')
        sig_rel = bundle.get('sig_jwt_path')
        if not isinstance(bundle_id, str) or not bundle_id:
            errors.append(f'{manifest_path}: framework.bundles[{idx}].id missing')
            continue
        if not isinstance(sig_rel, str) or not sig_rel:
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

if errors:
    for e in errors:
        print(f'ERROR: {e}')
    raise SystemExit(1)

print('ok: release guard trust lock + bundle sig checks passed')
PY
