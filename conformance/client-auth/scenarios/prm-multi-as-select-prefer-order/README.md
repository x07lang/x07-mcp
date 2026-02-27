# prm-multi-as-select-prefer-order

This scenario validates governed selection when PRM lists multiple authorization servers.

- PRM lists: [as2, as1]
- Policy allows both, prefers as1
- Expected selection: as1 (deterministic, order-independent)

Also validates:

- issuer format checks
- fail_closed behavior when no allowed issuer
