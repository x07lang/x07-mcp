# Why Postgres first

M2 deliberately focuses on one flagship server so the public beta story is concrete and evidence-backed instead of a broad catalog.

Postgres is the first flagship because it is:

- easy to understand (query/inspect/migrate is a familiar demo shape),
- easy to run locally and in Codespaces,
- enterprise-relevant without OAuth-heavy setup,
- a good fit for “repeatable verification artifacts” (conformance, replay, trust, bundle validation).

Kubernetes and GitHub remain on the shortlist, but the public beta wedge needs one hero path that runs end-to-end and is easy to reproduce.
