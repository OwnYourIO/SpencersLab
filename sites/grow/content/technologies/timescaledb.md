---
title: "TimescaleDB"
weight: 4
---

TimescaleDB extends PostgreSQL with time-series superpowers, and it is where all SFF sensor data lives long-term. While Home Assistant keeps a short rolling history for dashboards and automations, TimescaleDB retains every reading at full resolution -- sometimes for years. This makes it possible to compare this week's lettuce growth curve against the same week last year, correlate yield drops with subtle environmental shifts, or train models that predict harvest dates. Continuous aggregates handle the heavy lifting of downsampling, so queries over months of data return in milliseconds. Because it is just Postgres under the hood, the entire ecosystem of SQL tooling, backup strategies, and replication patterns applies out of the box.
