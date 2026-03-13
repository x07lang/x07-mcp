#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from workbench_summary import BUNDLE_SCHEMA, PUBLISH_SCHEMA, compute_bundle_summary, compute_publish_readiness


class WorkbenchSummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = pathlib.Path(__file__).resolve().parents[3]
        self.server_dir = self.repo_root / "servers" / "x07lang-mcp"
        self.server_json = self.server_dir / "publish" / "server.mcp-registry.json"
        self.server_manifest = self.server_dir / "x07.mcp.json"
        self.mcpb_path = self.server_dir / "dist" / "x07lang-mcp.mcpb"
        self.schema_path = self.repo_root / "registry" / "schema" / "server.schema.2025-12-11.json"
        self.schema_url = "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json"

    def test_publish_readiness_success(self) -> None:
        summary, trust_summary, manifest_path = compute_publish_readiness(
            server_json_path=self.server_json,
            mcpb_path=self.mcpb_path,
            schema_path=self.schema_path,
            schema_url=self.schema_url,
        )

        self.assertEqual(summary["schema_version"], PUBLISH_SCHEMA)
        self.assertTrue(summary["ok"])
        self.assertEqual(summary["status"], "ready")
        self.assertEqual(summary["publish"]["manifest_version"], "0.3")
        self.assertEqual(summary["capabilities"]["tool_count"], 19)
        self.assertIsInstance(trust_summary, dict)
        self.assertEqual(manifest_path, self.server_manifest)

    def test_publish_readiness_sha_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = pathlib.Path(tmp_dir)
            bad_server_json = tmp_path / "server.json"
            server_doc = json.loads(self.server_json.read_text(encoding="utf-8"))
            server_doc["packages"][0]["fileSha256"] = "0" * 64
            bad_server_json.write_text(
                json.dumps(server_doc, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )

            summary, _, _ = compute_publish_readiness(
                server_json_path=bad_server_json,
                mcpb_path=self.mcpb_path,
                schema_path=self.schema_path,
                schema_url=self.schema_url,
                manifest_path_override=self.server_manifest,
            )

        self.assertFalse(summary["ok"])
        self.assertEqual(summary["status"], "blocked")
        blocker_codes = {item["code"] for item in summary["blockers"]}
        self.assertIn("MCP_PUBLISH_MCPB_SHA_MISMATCH", blocker_codes)

    def test_bundle_summary_success(self) -> None:
        summary = compute_bundle_summary(
            server_dir=self.server_dir,
            mcpb_path=self.mcpb_path,
        )

        self.assertEqual(summary["schema_version"], BUNDLE_SCHEMA)
        self.assertTrue(summary["ok"])
        self.assertEqual(summary["status"], "ready")
        self.assertEqual(summary["bundle"]["sha256"], "b1fae8628268d2411bbac74ed0ae53bcad26116e8fe9176ac46a0ef5ca0e08b7")
        self.assertEqual(summary["publish"]["status"], "ready")


if __name__ == "__main__":
    unittest.main()
