---
title: "ESPHome"
weight: 3
---

ESPHome is the firmware layer that turns inexpensive ESP32 microcontrollers into reliable sensor nodes and actuator controllers. Each node is defined in a simple YAML configuration file, compiled over-the-air, and automatically discovered by Home Assistant. In a typical SFF deployment, ESPHome nodes handle temperature, humidity, EC, pH, dissolved oxygen, and light level readings -- plus relay control for pumps, solenoids, and grow lights. The YAML-driven approach means every sensor configuration lives in version control alongside the rest of the infrastructure, making it trivial to replicate a working setup across multiple grow sites or roll back a bad change.
