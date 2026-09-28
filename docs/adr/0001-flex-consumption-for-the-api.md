# 1. Flex Consumption for the API

- Status: accepted
- Date: 2026-09-28

## Context

The API is one HTTP endpoint with sporadic traffic. It should cost nothing while idle, start fast enough
for a human visitor, authenticate to its dependencies without secrets, and have a hard ceiling on spend.

## Options

| Plan | Idle cost | Cold start | Identity-based host storage | Cost ceiling |
|---|---|---|---|---|
| Consumption (Linux, legacy) | none | yes | partial | none (scales freely) |
| Flex Consumption | none | yes, mitigable with always-ready instances | yes | `maximumInstanceCount` + per-instance concurrency |
| Premium (EP1) | always-on instance | no | yes | instance limits, but pays 24/7 |
| App Service plan | always-on VM | no | yes | fixed, pays 24/7 |

## Decision

Flex Consumption, 512 MB instances, `maximumInstanceCount = 1`, HTTP concurrency 10.

## Consequences

- Scale to zero; the first request after idle pays a cold start (about a second). Acceptable for a resume.
- Throughput is bounded (measured: about 12 requests/s), which bounds compute cost.
- Executions are still billed per million and are not bounded by the scale caps: covered by the kill switch (ADR 4).
