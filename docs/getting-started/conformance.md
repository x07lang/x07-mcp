# Run conformance

Run server conformance with either `x07 mcp` delegation or `x07-mcp` directly.

## Against an existing server URL

```sh
x07 mcp conformance --url http://127.0.0.1:8080/mcp
```

Equivalent direct call:

```sh
x07-mcp conformance --url http://127.0.0.1:8080/mcp
```

## Spawn a reference server

```sh
x07-mcp conformance \
  --url http://127.0.0.1:8080/mcp \
  --baseline conformance/conformance-baseline.yml \
  --spawn postgres-mcp \
  --mode oauth
```

Use `--mode noauth` for the no-auth profile.
