# mcp-server-http-tasks (x07 template)

This template demonstrates MCP Streamable HTTP + Tasks (create/poll/result/cancel rules)
with deterministic RR fixtures.

## Quickstart

```bash
# from a newly initialized project based on this template
x07 pkg lock --project x07.json
x07 test --manifest tests/tests.json
```

## Run the server (dev)

```bash
x07 run --project x07.json --profile os_dev
```

The server listens on: http://127.0.0.1:8080/mcp

## Notes

* Tasks are enabled and negotiated via server capabilities + per-tool `execution.taskSupport`.
* The included RR transcript validates the `hello.wait` task flow end-to-end.

