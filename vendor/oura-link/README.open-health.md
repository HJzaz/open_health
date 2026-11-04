# Local history-drain policy patch

Copied from Th0rgal/open_oura at
`4f7957d3304c4084f0e1e703f3d84606bf10b781` (MIT; see LICENSE).

Only the manifest and client history policy are changed. The protocol dependency
still uses that exact upstream revision. The root Cargo patch selects this copy.

The upstream drain sends `28 01 00` before every batch as a data flush. The
protocol also defines those same bytes as a non-forced sleep-analysis request.
The iPhone's six-hour request policy therefore did not cover all occurrences.
This finding does not establish the opcode's firmware behavior or battery cost.

`drain_events` preserves upstream behavior for the CLI and other existing callers.
`drain_events_without_flush` uses the same history retrieval, parsing, checkpoint,
tail and fallback logic, but omits that command. The native core uses it for
normal drains, recovery drains and cursor-marker probes. Only the separately
throttled explicit sleep request sends the opcode in the native sync path.

Tests exercise extended multi-batch downloads and legacy fallback with no flush,
while the existing upstream tests retain the default policy. Compatibility with
the physical ring and any effect on battery consumption require device testing.
No feature modes, raw sampling, authentication keys or ring data are changed by
this patch.
