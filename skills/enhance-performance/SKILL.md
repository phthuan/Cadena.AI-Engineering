---
name: enhance-performance
description: Analyze and optimize application performance, slow methods, SQL queries, database calls, CPU, memory and latency.
---

# Enhance Performance

1. Inspect the target method and trace its callers and callees.
2. Read applicable shared rules under rules/common/ and rules/performance/.
3. Identify exact methods, SQL queries, stored procedures and repeated database calls.
4. Distinguish measured facts from assumptions; do not invent bottlenecks.
5. Explain the root cause before proposing changes.
6. Make minimal changes while preserving business behavior.
7. Consider SQL I/O, N+1 queries, batching, allocations and resource lifetime.
8. Add or update tests where practical.
9. Run relevant checks when possible.
10. Report evidence, files changed, risks and actual test results.
