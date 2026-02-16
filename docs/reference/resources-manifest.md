# Resources manifest (`x07.mcp.resources_manifest@0.1.0`)

`config/mcp.resources.json` declares static resources exposed via:

- `resources/list`
- `resources/read`

## Shape

```json
{
  "schema_version": "x07.mcp.resources_manifest@0.1.0",
  "resources": [
    {
      "uri": "about:example",
      "name": "about",
      "mimeType": "text/plain",
      "text": "ok"
    }
  ]
}
```

Notes:

- `resources` may be empty.
- v1 supports inline `text` payloads.
