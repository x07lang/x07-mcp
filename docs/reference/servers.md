# Reference servers

`x07-mcp` ships these publish-ready reference servers:

- [`github-mcp`](../../servers/github-mcp/README.md) — `github.list_repos`, `github.get_issue`
- [`slack-mcp`](../../servers/slack-mcp/README.md) — `slack.list_channels`, `slack.post_message`
- [`jira-mcp`](../../servers/jira-mcp/README.md) — `jira.search_issues`, `jira.get_issue`
- [`postgres-mcp`](../../servers/postgres-mcp/README.md) — `db.ping`, `db.query`
- [`redis-mcp`](../../servers/redis-mcp/README.md) — `redis.ping`, `redis.get`
- [`s3-mcp`](../../servers/s3-mcp/README.md) — `s3.list_buckets`, `s3.get_object`
- [`kubernetes-mcp`](../../servers/kubernetes-mcp/README.md) — `k8s.list_pods`, `k8s.get_pod`
- [`stripe-mcp`](../../servers/stripe-mcp/README.md) — `stripe.list_customers`, `stripe.get_customer`
- [`smtp-mcp`](../../servers/smtp-mcp/README.md) — `smtp.send`, `smtp.preview`
- [`http-proxy-mcp`](../../servers/http-proxy-mcp/README.md) — `http.get_json`, `http.post_json`

Each server includes:

- stdio + HTTP configs (`config/mcp.server*.json`)
- OAuth fixture config (`config/mcp.oauth.json`)
- resources/prompts manifests (`config/mcp.resources.json`, `config/mcp.prompts.json`)
- replay tests (`tests/mcp_http_replay.x07.json`)
- publish recipe (`publish/build_mcpb.sh`)
