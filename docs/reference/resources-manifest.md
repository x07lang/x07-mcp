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
      "description": "About this server",
      "mimeType": "text/plain",
      "size": 2,
      "text": "ok"
    }
  ]
}
```

Notes:

- `resources` may be empty.
- v1 supports inline `text` payloads.
- `size` is optional; when present it is returned in `resources/list` items (bytes).
