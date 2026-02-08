---
title: "Home Assistant"
weight: 2
---

Home Assistant serves as the central nervous system for every SFF grow site. It aggregates sensor data from ESPHome devices, manages automation rules, and provides the dashboard operators use day-to-day. When root zone EC drifts outside the target window, Home Assistant fires the nutrient dosing sequence. When ambient temperature spikes, it adjusts fan speeds and misting intervals. Because it runs locally on each site's hardware, there is no cloud dependency -- your farm keeps running even if your internet does not. We extend it with custom integrations for aeroponic-specific controls like spray timing, reservoir cycling, and pH drift correction.
