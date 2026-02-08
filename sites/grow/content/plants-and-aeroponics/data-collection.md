---
title: "Data Collection"
weight: 2
---

Every SFF grow site is instrumented from day one. ESPHome sensor nodes sample environmental conditions every few seconds -- air temperature, relative humidity, root zone temperature, electrical conductivity, pH, dissolved oxygen, CO2 concentration, and photosynthetically active radiation. This telemetry flows through Home Assistant into TimescaleDB, building a continuous record of everything the plants experience throughout their lifecycle. Over time, this dataset becomes the most valuable asset in the operation. It reveals which environmental profiles produce the best yields, which nutrient formulations reduce tip burn, and how seasonal changes in ambient conditions propagate through the system. Data collection is not an afterthought bolted onto the farm -- it is the foundation that makes every other optimization possible.
