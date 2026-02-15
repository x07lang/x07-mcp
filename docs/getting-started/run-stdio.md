# Run a stdio server

The stdio server reads newline-delimited JSON-RPC messages on stdin and writes newline-delimited JSON-RPC responses on stdout.

## 1) Bundle router + worker

From your project directory:

```sh
x07 bundle --profile os --out out/mcp-router
x07 bundle --profile sandbox --program src/worker_main.x07.json --out out/mcp-worker
```

`config/mcp.server.json` defaults `worker_exe_path` to `out/mcp-worker`. Update it if you use a different output path.

## 2) Run the router

```sh
./out/mcp-router
```

For development, you can also run the router via `x07 run --profile os`, but bundling is the easiest way to match real stdio behavior.
