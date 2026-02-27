# Trust Policy Registry (local fixtures)

This directory contains a static registry layout used by replay tests.
In production, host the same structure behind HTTPS (for example, internal NGINX).

The runtime never trusts on first use:
all remote content is pinned by trust.lock.json plus bundle signature statements.
