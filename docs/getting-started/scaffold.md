# Scaffold a server

Use either `x07` (delegation) or `x07-mcp` directly.

## Stdio template

```sh
x07 init --template mcp-server-stdio --dir ./my-mcp-server
```

Or:

```sh
x07-mcp scaffold init --template mcp-server-stdio --dir ./my-mcp-server
```

After scaffolding, lock dependencies:

```sh
cd ./my-mcp-server
x07 pkg lock
```

If you are testing unpublished local packages, add local paths before locking.

## HTTP template

```sh
x07 init --template mcp-server-http --dir ./my-mcp-http
```

Or:

```sh
x07-mcp scaffold init --template mcp-server-http --dir ./my-mcp-http
```

Then lock dependencies:

```sh
cd ./my-mcp-http
x07 pkg lock
```

The HTTP template includes:

- `config/mcp.server.json` (`x07.mcp.server_config@0.2.0`)
- `config/mcp.tools.json` (`x07.mcp.tools_manifest@0.2.0`)
- `config/mcp.oauth.json` (`x07.mcp.oauth@0.1.0`)
- replay fixtures under `tests/.x07_rr/sessions/`
