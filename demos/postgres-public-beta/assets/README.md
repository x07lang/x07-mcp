# Demo assets

This directory holds reproducible, human-facing assets for the Postgres public-beta demo:

- verifier outputs (`summary.json`, `summary.html`, `summary.sarif.json`, …)
- a terminal command log used to generate the artifacts
- placeholder locations for screenshots/stills

## Regenerate

From `demos/postgres-public-beta/`:

1. start dependencies:
   ```sh
   ./scripts/run_demo.sh --deps-only
   ```
2. run the server (leave it running):
   ```sh
   ./scripts/run_demo.sh --server
   ```
3. run verifier commands:
   ```sh
   ./scripts/verify_demo.sh
   ```
4. copy outputs into `assets/captured/`:
   ```sh
   ./scripts/capture_outputs.sh
   ```

The demo scripts are the canonical source of truth for the command sequence.
