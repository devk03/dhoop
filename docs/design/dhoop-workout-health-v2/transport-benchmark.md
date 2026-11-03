# Isolated response-read comparison

The existing public `WorkoutSyncTransport.send` boundary read the same 256 KiB synthetic JSON body
through a local URLProtocol fixture, three consecutive times. Values below are milliseconds.
There was no DNS, TLS, server work, real account data or UI interaction in this measurement.

| Reader | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Original asynchronous byte iteration | 19.856 | 13.533 | 13.539 |
| Bounded delegate chunk collection | 0.324 | 0.255 | 0.243 |

Repeat with the DhoopGoalTests scheme and
`-only-testing:DhoopGoalTests/WorkoutSyncTransportTests/testLargeDashboardReadPreservesBodyAndReportsLocalReadTime`.
The test checks byte identity and reports timings; it does not assert machine-dependent wall-clock
thresholds. This is evidence of lower response-processing overhead, not proof of end-to-end API
latency, the 100 ms UI feedback goal, or physical iPhone performance.

The transport suite also checks actual body-size limits without Content-Length, cancellation of an
unfinished response, reviewed conflict codes, authentication headers, MIME rejection and redirect
refusal. Full app builds and runtime UI checks are separate requirements.
