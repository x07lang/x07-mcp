# Prompts manifest (`x07.mcp.prompts_manifest@0.1.0`)

`config/mcp.prompts.json` declares static prompts exposed via:

- `prompts/list`
- `prompts/get`

## Shape

```json
{
  "schema_version": "x07.mcp.prompts_manifest@0.1.0",
  "prompts": [
    {
      "name": "help",
      "text": "ok"
    }
  ]
}
```

Notes:

- `prompts` may be empty.
- v1 uses deterministic static text prompts.
- If a prompt named `mcp.instructions_v1` is present, its `text` is returned as `InitializeResult.instructions` (keep it short).
