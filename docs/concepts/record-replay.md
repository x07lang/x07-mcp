# Record/replay

`x07-mcp` includes helpers for deterministic stdio transcript replay.

The basic format is two JSONL files:

- client → server lines (`c2s.jsonl`)
- expected server → client lines (`s2c.jsonl`)

Replay runs the same dispatcher used by the stdio router and compares canonicalized JSON outputs line-by-line.
