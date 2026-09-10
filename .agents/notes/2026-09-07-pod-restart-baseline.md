# Pod restart baseline — 2026-09-07

Record for comparing restart counts tomorrow (~24h window).

- **Reset time:** 2026-09-07 ~18:20 UTC — 146 pods deleted across 6 clusters
  (criterion: restarts > 10; infra excluded per user).
- **Baseline snapshot:** 2026-09-07 ~18:33 UTC (post-reset state, below).
- **How to use tomorrow:** re-list pods on each cluster; any pod whose RESTARTS
  grew significantly vs. the baseline column is a genuine churner. Note that
  pods recreated at reset time have their whole count accumulated in <24h.

## Known root causes (from this session's investigation)

| Pod | Cluster | Root cause |
|---|---|---|
| gpu-supabase → kong container | gpu | OOMKilled at 1Gi limit every ~2–3h (needs higher limit) |
| mailcow-exporter | monitoring | exit code 2 (Error) every ~3h — app-level fatal during mail.spencerslab.com scrapes |
| proxy-local-qbittorrent | proxy-local | torrent I/O errors: "Bad address" + resume data not writable (storage backend issue) |
| helm-install-traefik job | proxy-local (kube-system) | traefik 40.1.3 install fails: "Required CRDs are missing" (traefik-crd job never runs there); running traefik is still 39.0.9 |
| bitwarden-cli (grow/media/monitoring/proxy-local) | various | transient DNS failures to vault.bitwarden.com (EAI_AGAIN) → "not logged in" → restart |
| external-dns-external | proxy-local | chronic restarter; crash cause not visible at log tail |
| seaweedfs-csi-driver-controller | gpu/infra/media/proxy-local | systemic across clusters; graceful stops |
| alloy-operator | all clusters | leader-lease loss during API-server timeout episodes → exit |
| cloudnative-pg | gpu/grow/home/infra | crashed during API-server unresponsive windows (lease update timeouts) |

## Part 1 — Pods deleted at reset (pre-deletion restart counts)

### gpu (27)
| namespace | pod | restarts before |
|---|---|---|
| default | amd-gpu-device-plugin-daemonset-tck44 | 57 |
| default | argocd-dex-server-5977cfb588-ts2bm | 23 |
| default | argocd-notifications-controller-5f7dfbd785-jnw6j | 28 |
| default | gpu-archon-cbcc695cc-h7xrv | 19 |
| default | gpu-cert-manager-749f876c78-mcbpf | 60 |
| default | gpu-cert-manager-cainjector-6bb4dc6d64-ckjd5 | 58 |
| default | gpu-cloudnative-pg-79c887d747-nt4lw | 718 |
| default | gpu-external-secrets-bitwarden-cert-controller-6d4585766c-kc2rl | 23 |
| default | gpu-external-secrets-bitwarden-webhook-f67dd85f7-q4ccx | 65 |
| default | gpu-k8s-monitoring-alloy-logs-wvw9p | 46 |
| default | gpu-k8s-monitoring-alloy-operator-75c9847c79-k4r9c | 688 |
| default | gpu-k8s-monitoring-alloy-singleton-66ddff6f67-cg2wq | 46 |
| default | gpu-k8s-monitoring-kube-state-metrics-5b7dd85d84-rb2tf | 135 |
| default | gpu-k8s-monitoring-node-exporter-pkwq4 | 78 |
| default | gpu-open-webui-tika-75998f8c94-pvpjz | 23 |
| default | gpu-seaweedfs-csi-driver-controller-587c596784-2wvbn | 286 |
| default | gpu-supabase-6bd48dbf85-bgknr | 450 |
| default | pg-coder-1 | 73 |
| default | pg-flowise-1 | 83 |
| default | pg-langflow-1 | 86 |
| default | pg-n8n-1 | 71 |
| default | pg-open-webui-1 | 68 |
| default | pg-supabase-1 | 71 |
| default | smtp-relay-mail-0 | 114 |
| default | toolhive-operator-57cd5fcdcb-tbg67 | 127 |
| kube-system | metrics-server-786d997795-42r29 | 91 |
| system-upgrade | system-upgrade-controller-564c989b9c-sfk7r | 27 |

### grow (12)
| namespace | pod | restarts before |
|---|---|---|
| default | argocd-dex-server-5977cfb588-2p4jm | 105 |
| default | argocd-notifications-controller-5f7dfbd785-bmcsv | 120 |
| default | grow-cloudnative-pg-5b5cf5699b-ldngt | 244 |
| default | grow-k8s-monitoring-alloy-logs-rjhss | 166 |
| default | grow-k8s-monitoring-alloy-operator-7689749478-44pqz | 236 |
| default | grow-k8s-monitoring-alloy-singleton-98555bd48-9c5x5 | 166 |
| default | grow-k8s-monitoring-kube-state-metrics-ff97d4d87-7w7gh | 135 |
| default | grow-k8s-monitoring-node-exporter-bvtq8 | 74 |
| default | pg-grow-assistant-1 | 72 |
| default | pg-grow-assistant-sensors-1 | 72 |
| kube-system | metrics-server-786d997795-bttjr | 77 |
| system-upgrade | system-upgrade-controller-564c989b9c-bdpzc | 133 |

### home (36)
| namespace | pod | restarts before |
|---|---|---|
| default | argocd-dex-server-657f5854c4-wtqsb | 41 |
| default | argocd-notifications-controller-799d98bf9f-w2t5s | 87 |
| default | home-cloudnative-pg-74ff96cffd-z968j | 345 |
| default | home-external-secrets-bitwarden-cert-controller-6d79f9c54bh48gw | 159 |
| default | home-external-secrets-bitwarden-webhook-57c4bb7f8-k7m4r | 159 |
| default | home-immich-machine-learning-86d7c5cd98-mwf9h | 86 |
| default | home-immich-server-55b4c6d48-xvpl7 | 70 |
| default | home-immich-valkey-74b6476689-cb96b | 85 |
| default | home-k8s-monitoring-alloy-logs-2qwbj | 166 |
| default | home-k8s-monitoring-alloy-operator-6fd4d99cbb-qm77d | 302 |
| default | home-k8s-monitoring-alloy-singleton-5bfd5b4784-zn6n7 | 166 |
| default | home-k8s-monitoring-kube-state-metrics-77bb589c75-8gbb8 | 132 |
| default | home-k8s-monitoring-node-exporter-8qrxt | 70 |
| default | home-karakeep-575495bf99-zfggq | 11 |
| default | home-logitech-media-server-65444b987-g85zx | 42 |
| default | home-mosquitto-5ccf557597-4bzgx | 174 |
| default | home-paperless-main-6bc647754b-lxgq4 | 45 |
| default | home-postiz-temporal-admintools-5bf94d6785-dfwjz | 81 |
| default | home-postiz-temporal-frontend-b8bd4789c-rlrbh | 224 |
| default | home-postiz-temporal-history-6b9d99cfbc-wr66v | 226 |
| default | home-postiz-temporal-matching-c98955688-wlpqs | 227 |
| default | home-postiz-temporal-worker-d87d58b95-nkh88 | 228 |
| default | home-privatebin-5676fb479f-knmr9 | 65 |
| default | home-seaweedfs-csi-driver-controller-7865fb44d4-9kpwd | 19 |
| default | home-seaweedfs-csi-driver-mount-v766z | 72 |
| default | home-snapcast-5f846cf696-pt9p8 | 11 |
| default | pg-home-rallly-1 | 71 |
| default | pg-immich-1 | 71 |
| default | pg-immich-dev-1 | 71 |
| default | pg-paperless-1 | 71 |
| default | pg-postiz-1 | 71 |
| default | pg-temporal-1 | 71 |
| default | pg-temporal-visibility-1 | 71 |
| default | smtp-relay-mail-0 | 83 |
| kube-system | metrics-server-786d997795-xkmfg | 69 |
| system-upgrade | system-upgrade-controller-79b7cb4856-gswxf | 174 |

### media (25)
| namespace | pod | restarts before |
|---|---|---|
| default | argocd-dex-server-847d9d6b84-hv28s | 121 |
| default | argocd-notifications-controller-54b4b9db6-d266t | 121 |
| default | bitwarden-cli-f9d48dc89-x5c4l | 383 |
| default | media-audiobookshelf-556d5959f6-q9hg7 | 13 |
| default | media-external-secrets-bitwarden-77fb6c76b-rdlb2 | 129 |
| default | media-external-secrets-bitwarden-cert-controller-5fff95878hlsql | 129 |
| default | media-external-secrets-bitwarden-webhook-59cbc7df67-cfqgj | 129 |
| default | media-jellyfin-555c496978-2p2k7 | 67 |
| default | media-jellyseerr-584fb47479-4lgl5 | 28 |
| default | media-k8s-monitoring-alloy-logs-2fzlw | 198 |
| default | media-k8s-monitoring-alloy-operator-7cf4c4c846-z79mh | 266 |
| default | media-k8s-monitoring-alloy-singleton-54fcfdbb58-mf776 | 198 |
| default | media-k8s-monitoring-kube-state-metrics-7b6f7cf59f-794f2 | 119 |
| default | media-k8s-monitoring-node-exporter-9sjsd | 89 |
| default | media-lidarr-7b6dd9d467-h5nd4 | 122 |
| default | media-prowlarr-5cf45459f5-ls2wr | 227 |
| default | media-radarr-67fffb6f66-46pqg | 112 |
| default | media-readarr-dd8556f9d-hx5hh | 117 |
| default | media-seaweedfs-csi-driver-controller-68f97bb688-gvkhc | 343 |
| default | media-seaweedfs-csi-driver-mount-bzs7g | 22 |
| default | media-seaweedfs-csi-driver-node-ccv68 | 66 |
| default | media-sonarr-55f89bb55-z67h6 | 125 |
| default | smtp-relay-mail-0 | 101 |
| kube-system | metrics-server-786d997795-5f7h2 | 88 |
| system-upgrade | system-upgrade-controller-79b7cb4856-t8wz5 | 186 |

### monitoring (23)
| namespace | pod | restarts before |
|---|---|---|
| default | alertmanager-monitoring-kube-prometheus-alertmanager-0 | 114 |
| default | argocd-dex-server-59546996c4-r2kv7 | 59 |
| default | argocd-notifications-controller-6d6cfbd5b4-gd75n | 59 |
| default | bitwarden-cli-f9d48dc89-zpqwd | 75 |
| default | mailcow-exporter-7448d685b9-74xdh | 2227 |
| default | monitoring-exporter-mikrotik-6cd8bc49df-bc85d | 57 |
| default | monitoring-external-secrets-bitwarden-596b55b4d4-288pf | 59 |
| default | monitoring-external-secrets-bitwarden-cert-controller-c9f8wvps8 | 59 |
| default | monitoring-external-secrets-bitwarden-webhook-7c655d6545-czr8g | 59 |
| default | monitoring-k8s-monitoring-alloy-logs-h8wg5 | 90 |
| default | monitoring-k8s-monitoring-alloy-operator-77f59b7f9d-744vv | 182 |
| default | monitoring-k8s-monitoring-alloy-singleton-687c648bf4-wj5cs | 90 |
| default | monitoring-k8s-monitoring-kube-state-metrics-69c967c7c7-tggmq | 62 |
| default | monitoring-k8s-monitoring-node-exporter-pgdb4 | 36 |
| default | monitoring-kube-prometheus-operator-6cd8475886-79gjc | 58 |
| default | monitoring-kube-prometheus-stack-kube-state-metrics-b6786dbp4c7 | 73 |
| default | monitoring-loki-chunks-cache-0 | 70 |
| default | monitoring-loki-gateway-7f59f986b9-7vjqw | 82 |
| default | monitoring-loki-results-cache-0 | 70 |
| default | prometheus-monitoring-kube-prometheus-prometheus-0 | 114 |
| default | smtp-relay-mail-0 | 47 |
| kube-system | metrics-server-786d997795-wg4pn | 34 |
| system-upgrade | system-upgrade-controller-564c989b9c-46sww | 58 |

### proxy-local (23)
| namespace | pod | restarts before |
|---|---|---|
| default | argocd-dex-server-5977cfb588-7khsk | 151 |
| default | argocd-notifications-controller-5f7dfbd785-6qhqj | 156 |
| default | bitwarden-cli-675959f956-l78f6 | 145 |
| default | proxy-local-backup-gpu-qbittorrent-6bc7b98b46-z6rv9 | 18 |
| default | proxy-local-external-dns-external-547b97577-bbsnn | 2091 |
| default | proxy-local-k8s-monitoring-alloy-logs-ph2xh | 232 |
| default | proxy-local-k8s-monitoring-alloy-operator-779d867574-n648q | 385 |
| default | proxy-local-k8s-monitoring-alloy-singleton-795bb4f598-jsfxn | 232 |
| default | proxy-local-k8s-monitoring-kube-state-metrics-75f8778cbc-xpxf8 | 188 |
| default | proxy-local-k8s-monitoring-node-exporter-dswvc | 103 |
| default | proxy-local-metube-7f6b9868cf-df7kl | 45 |
| default | proxy-local-pinchflat-b5b954765-6hddf | 18 |
| default | proxy-local-qbittorrent-69cc5486c7-pgnsd | 466 |
| default | proxy-local-seaweedfs-csi-driver-controller-5bb79bdc65-2z569 | 530 |
| default | proxy-local-seaweedfs-csi-driver-mount-bjngg | 107 |
| default | proxy-local-seaweedfs-csi-driver-node-wpf8d | 89 |
| default | smtp-relay-mail-0 | 116 |
| kube-system | bitwarden-cli-675959f956-5hrst | 184 |
| kube-system | helm-install-traefik-6h94n | 203 |
| kube-system | metrics-server-786d997795-bm4lk | 102 |
| kube-system | proxy-local-traefik-agent-lgb7g | 29 |
| kube-system | proxy-local-traefik-lapi-5c8fc7fb6f-bl8zh | 29 |
| system-upgrade | system-upgrade-controller-6ddd46bf8d-9tbsh | 219 |

### infra — NOT deleted (report-only), counts as of snapshot
| namespace | pod | restarts |
|---|---|---|
| default | infra-seaweedfs-csi-driver-controller-5b8d5ff9b-q2sb8 | 397 |
| default | infra-cloudnative-pg-6b76dc9b55-xgxpx | 66 |
| default | infra-seaweedfs-csi-driver-node-mf68n | 44 |
| default | infra-seaweedfs-csi-driver-mount-7v5bw | 34 |
| kube-system | metrics-server-786d997795-87fsm | 34 |
| default | infra-k8s-monitoring-alloy-operator-576d5cd494-27s4g | 29 |

## Part 2 — Full baseline snapshot, 2026-09-07 ~18:33 UTC (post-reset)

Format: `pod | status | restarts | age`. ⚠ = anomaly observed right after reset.

### gpu
```
default/amd-gpu-device-plugin-daemonset-4jvlj            Running    0   11m
default/argocd-application-controller-0                   Running    2   50d
default/argocd-applicationset-controller-7c4c7f4b8c-rsqdp Running   2   50d
default/argocd-dex-server-5977cfb588-pj5qg                Running    0   11m
default/argocd-notifications-controller-5f7dfbd785-s6pwz  Running    0   11m
default/argocd-redis-6d58776fc8-x745r                     Running    2   51d
default/argocd-repo-server-fcbc98899-qrpzg                Running    6   50d
default/argocd-server-64976455f6-rvgf2                    Running    2   50d
default/bitwarden-cli-f9d48dc89-475lt                     Running    0   107m
default/coder-7d4c9d9ffb-csdkk                            Running    3   52d
default/coder-9539094a-…-67c9c4f46c-lj9v8                 Running    0   4h47m
default/gpu-archon-cbcc695cc-jp6tk                        Running    1   11m   ⚠ 1 restart since recreation
default/gpu-cert-manager-749f876c78-bs6lg                 Running    0   11m
default/gpu-cert-manager-cainjector-6bb4dc6d64-qpdsk      Running    0   11m
default/gpu-cert-manager-webhook-5bb659549-z98wx          Running    2   50d
default/gpu-cloudnative-pg-79c887d747-wjxdn               Running    0   11m
default/gpu-docling-7bbcf6bf68-wcvdm                      Running    3   52d
default/gpu-drawio-85c55fd89-bh5fm                        Running    9   52d
default/gpu-external-secrets-bitwarden-765d6fd89b-bz452   Running    0   117m
default/gpu-external-secrets-bitwarden-cert-controller-…x6cqx Running 0 11m
default/gpu-external-secrets-bitwarden-webhook-…v8rbs     Running    0   11m
default/gpu-flowise-686d8b89cd-24bwd                      Running    6   52d
default/gpu-k8s-monitoring-alloy-logs-6l2r4               Running    0   11m
default/gpu-k8s-monitoring-alloy-metrics-0                Running    0   91m
default/gpu-k8s-monitoring-alloy-operator-75c9847c79-vfzt5 Running  0   11m
default/gpu-k8s-monitoring-alloy-singleton-66ddff6f67-8mqzp Running 0  11m
default/gpu-k8s-monitoring-kube-state-metrics-…bl8fn      Running    0   11m
default/gpu-k8s-monitoring-node-exporter-m87q2            Running    0   11m
default/gpu-langflow-7bf6796b78-sl9gl                     Running    2   52d
default/gpu-llama-swap-74ff6d54fc-z84jf                   Running    0   17h
default/gpu-n8n-bc7f8c7c7-chdrm                           Running    6   52d
default/gpu-open-webui-0                                  Running    3   52d
default/gpu-open-webui-pipelines-7c7f98c848-zdksk         Running    6   57d
default/gpu-open-webui-redis-696cfd7f6d-7jn9k             Running    6   57d
default/gpu-open-webui-tika-75998f8c94-l855q              Running    0   11m
default/gpu-searxng-645d7cc6c6-6vlwd                      Running    0   16h
default/gpu-seaweedfs-csi-driver-controller-587c596784-z98h9 Running 0 10m
default/gpu-seaweedfs-csi-driver-mount-92wlv              Running    3   54d
default/gpu-seaweedfs-csi-driver-node-xtvtc               Running    9   54d
default/gpu-supabase-6bd48dbf85-vxkzz                     Running    0   10m   (kong OOM cycle expected to resume ~2-3h)
default/mcp-grafana-admin-0                               Running    0   121m
default/mcp-grafana-admin-f648d967f-lpn72                 Running    2   121m
default/mcp-grafana-readonly-0                            Running    0   121m
default/mcp-grafana-readonly-5b7d6b76ff-zms8q             Running    0   121m
default/mcp-homeassistant-admin-0                         Running    0   121m
default/mcp-homeassistant-admin-7fcfb775d9-vbt62          Running    0   121m
default/mcp-homeassistant-readonly-0                      Running    0   121m
default/mcp-homeassistant-readonly-5766dfb9f4-8rm44       Running    0   121m
default/mcp-kubernetes-admin-0                            Running    1   17h
default/mcp-kubernetes-admin-8b4d46cb4-7sh87              Running    1   17h
default/mcp-kubernetes-readonly-0                         Running    1   17h
default/mcp-kubernetes-readonly-6b74dd687b-65v5k          Running    1   17h
default/mcp-playwright-0                                  Running    1   17h
default/mcp-playwright-76bbc75cf7-xjvkp                   Running    1   17h
default/mcp-postgres-coder-0                              Running    1   17h
default/mcp-postgres-coder-56b4b8859-6gjv7                Running    1   17h
default/mcp-postgres-flowise-0                            Running    1   17h
default/mcp-postgres-flowise-6bcbc49b59-psmwm             Running    1   17h
default/mcp-postgres-langflow-0                           Running    1   17h
default/mcp-postgres-langflow-df974c76f-q4smj             Running    1   17h
default/mcp-postgres-n8n-0                                Running    2   17h
default/mcp-postgres-n8n-c6b8f96d8-8mfj6                  Running    1   17h
default/mcp-postgres-open-webui-0                         Running    1   17h
default/mcp-postgres-open-webui-5d64755bdd-6x8bm          Running    1   17h
default/mcp-postgres-supabase-0                           Running    2   17h
default/mcp-postgres-supabase-5b5dcddcc4-8mltq            Running    1   17h
default/mcp-renovate-0                                    Running    0   16h
default/mcp-renovate-5f4cc6d785-hds5f                     Running    0   16h
default/mcp-searxng-0                                     Running    1   17h
default/mcp-searxng-795f4dc765-ch59l                      Running    1   17h
default/mcp-wekan-admin-0                                 Running    0   106m
default/mcp-wekan-admin-97d79f6f7-4kbjg                   Running    3   110m
default/mcp-wekan-readonly-0                              Running    0   106m
default/mcp-wekan-readonly-5f68d5d9c-bxj58                Running    3   110m
default/pg-coder-1                                        Running    0   7m25s
default/pg-flowise-1                                      Running    0   7m25s
default/pg-langflow-1                                     Running    0   7m24s
default/pg-n8n-1                                          Running    0   7m25s
default/pg-open-webui-1                                   Running    0   7m24s
default/pg-supabase-1                                     Running    0   10m
default/smtp-relay-mail-0                                 Running    0   10m
default/toolhive-operator-57cd5fcdcb-zprrs                Running    0   10m
kube-system/coredns-5f5694d56b-27jvr                      Running    3   51d
kube-system/helm-install-traefik-54f7j                    Completed  0   51d
kube-system/helm-install-traefik-crd-6hg5w                Completed  0   51d
kube-system/local-path-provisioner-58d557dc48-6dmxq       Running    3   51d
kube-system/metrics-server-786d997795-cd85d               Running    0   10m
kube-system/svclb-traefik-931db8f4-mkc77                  Running    9   51d
kube-system/traefik-7fc777cc94-wbt2h                      Running    2   51d
system-upgrade/system-upgrade-controller-564c989b9c-px67n Running   0   10m
```

### grow
```
default/argocd-application-controller-0                   Running    1   17h
default/argocd-applicationset-controller-5d87ff677f-dg2sv Running   1   17h
default/argocd-dex-server-5977cfb588-xg8x5                Running    0   10m
default/argocd-notifications-controller-5f7dfbd785-54dk9  Running    0   10m
default/argocd-redis-7df5dfd559-fzlxq                     Running    1   17h
default/argocd-repo-server-dcb544b9-58rk2                 Running    3   17h
default/argocd-server-858555c955-5fqfk                    Running    2   17h
default/bitwarden-cli-675959f956-rlkx8                    Running    0   18m
default/grow-cert-manager-6759dffc4f-qk7d2                Running    2   17h
default/grow-cert-manager-cainjector-56d8bbdc99-b2t24     Running    2   17h
default/grow-cert-manager-webhook-74c64cdfdb-7c45q        Running    2   17h
default/grow-cloudnative-pg-5b5cf5699b-nkd9p              Running    0   10m
default/grow-external-secrets-bitwarden-985c87cd-mxpb5    Running    0   18m
default/grow-external-secrets-bitwarden-cert-controller-…bszfw Running 0 18m
default/grow-external-secrets-bitwarden-webhook-…j477v    Running    0   17m
default/grow-k8s-monitoring-alloy-logs-n7jhq              Running    0   9m51s
default/grow-k8s-monitoring-alloy-metrics-0               Running    0   89m
default/grow-k8s-monitoring-alloy-operator-7689749478-vsxtm Running 0  10m
default/grow-k8s-monitoring-alloy-singleton-98555bd48-lmmhg Running 0  10m
default/grow-k8s-monitoring-kube-state-metrics-…bjgmn     Running    0   10m
default/grow-k8s-monitoring-node-exporter-t757d           Running    0   9m44s
default/mcp-kubernetes-admin-0                            Running    1   17h
default/mcp-kubernetes-admin-8b4d46cb4-9vp9b              Running    4   17h
default/mcp-kubernetes-readonly-0                         Running    1   17h
default/mcp-kubernetes-readonly-6b74dd687b-plfjh          Running    3   17h
default/mcp-postgres-grow-assistant-0                     Running    1   17h
default/mcp-postgres-grow-assistant-94b584b9d-2bp6z       Running    4   17h
default/mcp-postgres-grow-assistant-sensors-0             Running    2   17h
default/mcp-postgres-grow-assistant-sensors-596486d4c7-5s7mj Running 3 17h
default/pg-grow-assistant-1                               Running    0   6m36s
default/pg-grow-assistant-sensors-1                       Running    0   6m41s
default/toolhive-operator-547fbcb4d4-nx27w                Running    4   17h
kube-system/coredns-5f5694d56b-2ck4k                      Running    3   17h
kube-system/helm-install-traefik-8jv6d                    Completed  3   17h
kube-system/helm-install-traefik-crd-p8hxz                Completed  1   17h
kube-system/local-path-provisioner-58d557dc48-25x6l       Running    1   17h
kube-system/metrics-server-786d997795-d5c5f               Running    0   10m
kube-system/svclb-pg-grow-assistant-external-10cbeb5e-9cb76 Running 1  17h
kube-system/svclb-pg-grow-assistant-tsdb-external-7d4bf422-rnj6d Running 1 17h
kube-system/svclb-traefik-b81cd3ba-2pf8h                  Running    3   17h
kube-system/traefik-7fc777cc94-56k67                      Running    1   17h
system-upgrade/system-upgrade-controller-564c989b9c-h2pw7 Running   0   10m
```

### home
```
default/argocd-application-controller-0                   Running    2   18h
default/argocd-applicationset-controller-5d776b6f9-tsl2g  Running    2   18h
default/argocd-dex-server-657f5854c4-24ssp                Running    0   9m23s
default/argocd-notifications-controller-799d98bf9f-vmzqb  Running    0   9m23s
default/argocd-redis-5cff7869f-8l4dn                      Running    2   18h
default/argocd-repo-server-c7fbd8466-ckwbk                Running    2   18h
default/argocd-server-58dc58655c-h8zfg                    Running    2   18h
default/bitwarden-cli-f9d48dc89-sxkmn                     Running    9   33d
default/home-actualbudget-6498987498-2cmzb                Running    9   33d
default/home-boards-7495cb769f-p7fwn                      Running    2   15h
default/home-bri-budget-585b57f97d-rwsfn                  Running    9   33d
default/home-brother-ptouch-automation-7d9bd44766-xd5pm   Running    8   29d
default/home-cert-manager-cainjector-7c5699c459-79fjg     Running    3   18h
default/home-cert-manager-d6d684789-9jrf7                 Running    3   18h
default/home-cert-manager-webhook-bf6c58cdb-xpc59         Running    2   18h
default/home-cloudnative-pg-74ff96cffd-ck7r7              Running    0   9m23s
default/home-external-secrets-bitwarden-55b9db9579-55sdj  Running    9   33d
default/home-external-secrets-bitwarden-cert-controller-…ltn9q Running 0 9m22s
default/home-external-secrets-bitwarden-webhook-…cwggs    Running    0   9m21s
default/home-generic-device-plugin-595cb4d87b-j7tfp       Running    10  43d
default/home-hyperion-bd9bddbd7-dj87x                     Running    10  43d
default/home-immich-machine-learning-86d7c5cd98-tvs6g     Running    0   9m21s
default/home-immich-server-55b4c6d48-jqhlc                Running    0   9m20s
default/home-immich-valkey-74b6476689-cdsbl               Running    0   9m20s
default/home-k8s-monitoring-alloy-logs-ln67j              Running    0   9m5s
default/home-k8s-monitoring-alloy-metrics-0               Running    0   90m
default/home-k8s-monitoring-alloy-operator-6fd4d99cbb-wfdnd Running 0  9m19s
default/home-k8s-monitoring-alloy-singleton-5bfd5b4784-mrm7k Running 0 9m17s
default/home-k8s-monitoring-kube-state-metrics-…8w25s     Running    0   9m17s
default/home-k8s-monitoring-node-exporter-zb8b2           Running    0   9m9s
default/home-karakeep-575495bf99-vfp2k                    Running    0   9m16s
default/home-karakeep-chrome-659564b9c6-444jx             Running    10  43d
default/home-karakeep-meilisearch-67454c84c8-q7t8v        Running    10  43d
default/home-ledfx-7857cbfd56-hrr42                       Running    10  43d
default/home-logitech-media-server-65444b987-7xpbw        Running    0   9m16s
default/home-mongodb-0                                    Running    3   15h
default/home-mosquitto-5ccf557597-cvl9z                   Running    0   9m15s
default/home-paperless-main-6bc647754b-g6rfw              CreateContainerError 9 9m14s ⚠ 1/4 ready, 9 restarts in 9m — REGRESSION after reset (was 4/4)
default/home-paperless-samba-bc4484684-nrnfl              Running    10  43d
default/home-playsms-759fdf59b6-s74h7                     Running    0   4h31m
default/home-postiz-7fb47bd7cc-65ntl                      Running    4   25h
default/home-postiz-temporal-admintools-5bf94d6785-98pw9  Running    0   9m14s
default/home-postiz-temporal-frontend-b8bd4789c-79fgp     Running    2   8m59s ⚠ startup churn
default/home-postiz-temporal-history-6b9d99cfbc-rstjk     Running    3   8m59s ⚠ startup churn
default/home-postiz-temporal-matching-c98955688-b4hxr     Running    2   8m58s ⚠ startup churn
default/home-postiz-temporal-schema-1-r4ggz               Completed  0   48m
default/home-postiz-temporal-worker-d87d58b95-wn9cw       Running    3   8m57s ⚠ startup churn
default/home-privatebin-5676fb479f-tc7fx                  Running    0   8m57s
default/home-pt750-7875864d6c-vhv6h                       Running    2   25h
default/home-rallly-66c69d9b5c-fzz9k                      Running    6   25h
default/home-seaweedfs-csi-driver-controller-7865fb44d4-mqlvd Running 0 8m55s
default/home-seaweedfs-csi-driver-mount-ksmgh             Running    0   8m12s
default/home-seaweedfs-csi-driver-node-wlkm6              Running    6   25h
default/home-snapcast-5f846cf696-wbzv6                    Running    0   8m54s
default/home-wekan-6fb9d9c6f9-knlrl                       Running    2   15h
default/home-zigbee2mqtt-coord-8547d8b5bf-mdtbh           Running    4   25h
default/mcp-kubernetes-admin-0                            Running    2   17h
default/mcp-kubernetes-admin-8b4d46cb4-f2n79              Running    2   17h
default/mcp-kubernetes-readonly-0                         Running    2   17h
default/mcp-kubernetes-readonly-6b74dd687b-tcc75          Running    2   17h
default/mcp-postgres-home-rallly-0                        Running    2   17h
default/mcp-postgres-home-rallly-7f844f8486-2cpxz         Running    2   17h
default/mcp-postgres-immich-0                             Running    2   17h
default/mcp-postgres-immich-fdfbfd4d6-sd562               Running    2   17h
default/mcp-postgres-paperless-0                          Running    2   17h
default/mcp-postgres-paperless-5fd9bc54c7-p7l5w           Running    2   17h
default/mcp-postgres-postiz-0                             Running    3   17h
default/mcp-postgres-postiz-7fc78c6894-mskw7              Running    3   17h
default/pg-home-rallly-1                                  Running    0   5m37s
default/pg-immich-1                                       Running    0   8m24s
default/pg-immich-dev-1                                   Running    0   8m20s
default/pg-paperless-1                                    Running    0   8m10s
default/pg-postiz-1                                       Running    0   5m35s
default/pg-temporal-1                                     Running    0   7m48s
default/pg-temporal-visibility-1                          Running    0   7m45s
default/smtp-relay-mail-0                                 Running    0   8m25s
default/toolhive-operator-b8cd58648-2mw4t                 Running    5   18h
kube-system/coredns-5f5694d56b-s68rw                      Running    2   18h
kube-system/local-path-provisioner-58d557dc48-lt8g6       Running    2   18h
kube-system/metrics-server-786d997795-fmzpx               Running    0   8m49s
kube-system/svclb-home-paperless-samba-282ea9f1-pvhcs     Running    4   18h
kube-system/svclb-home-snapcast-ad788c70-nkrfh            Running    6   18h
kube-system/svclb-home-snapcast-roc-streaming-6d4660e1-tdkk9 Running 6 18h
kube-system/svclb-home-snapcast-snapcast-http-004f1389-k88b9 Running 2 18h
kube-system/svclb-traefik-b974a857-hsl9t                  Running    6   18h
kube-system/traefik-65bf7bcbd4-x8r9b                      Running    2   18h
system-upgrade/system-upgrade-controller-79b7cb4856-dn7ks Running   0   8m49s
```

### infra (untouched by reset)
```
default/argocd-application-controller-0                   Running    0   17h
default/argocd-applicationset-controller-5cfdbfc76b-vrr66 Running   0   17h
default/argocd-dex-server-5977cfb588-nvnrl                Running    4   19d
default/argocd-notifications-controller-5f7dfbd785-rcgng  Running    4   19d
default/argocd-redis-c94466746-tpnbl                      Running    0   17h
default/argocd-repo-server-559cfc6b98-bs4tq               Running    0   17h
default/argocd-server-59f6b8c85-qpnvh                     Running    0   17h
default/bitwarden-cli-675959f956-vlr8m                    Running    5   19d
default/infra-389ds-5d5bf9bb88-6jbdn                      Running    0   17h
default/infra-cert-manager-557fd7f84b-hr629               Running    9   17h
default/infra-cert-manager-cainjector-6589765c44-w8cb2    Running    5   17h
default/infra-cert-manager-webhook-58ff5cf6b9-rpfgx       Running    0   17h
default/infra-cloudnative-pg-6b76dc9b55-xgxpx             Running    66  52d
default/infra-external-secrets-bitwarden-58889bdcd5-z669t Running    4   19d
default/infra-external-secrets-bitwarden-cert-controller-68f8bb8f4nsfr9 Running 4 19d
default/infra-external-secrets-bitwarden-webhook-5bcdb9cdb6-cqtfh Running 4 19d
default/infra-k8s-monitoring-alloy-logs-rrl9b             Running    6   18d
default/infra-k8s-monitoring-alloy-metrics-0              Running    0   91m
default/infra-k8s-monitoring-alloy-operator-576d5cd494-27s4g Running 29 19d
default/infra-k8s-monitoring-alloy-singleton-7f8fc77778-8jd4t Running 8 19d
default/infra-k8s-monitoring-kube-state-metrics-57c785f695-stjj5 Running 9 19d
default/infra-k8s-monitoring-node-exporter-6r8hj          Running    9   51d
default/infra-keycloakx-0                                 Running    2   17d
default/infra-samba-6b8fd94f4c-cwnkn                      Running    3   19d
default/infra-seaweedfs-csi-driver-controller-5b8d5ff9b-q2sb8 Running 397 75d
default/infra-seaweedfs-csi-driver-mount-7v5bw            Running    34  201d
default/infra-seaweedfs-csi-driver-node-mf68n             Running    44  75d
default/mcp-kubernetes-admin-0                            Running    0   17h
default/mcp-kubernetes-admin-8b4d46cb4-t5nhb              Running    0   17h
default/mcp-kubernetes-readonly-0                         Running    0   17h
default/mcp-kubernetes-readonly-6b74dd687b-ktmqn          Running    0   17h
default/mcp-postgres-keycloak-0                           Running    0   65m
default/mcp-postgres-keycloak-cc9b9c86-fm9p7              Running    1   17h
default/pg-keycloak-1                                     Running    3   18d
default/seaweedfs-admin-0                                 Running    4   19d
default/seaweedfs-filer-0                                 Running    7   19d
default/seaweedfs-filer-1                                 Running    6   19d
default/seaweedfs-filer-2                                 Running    10  19d
default/seaweedfs-filer-3                                 Running    7   19d
default/seaweedfs-filer-4                                 Running    5   19d
default/seaweedfs-master-0                                Running    4   19d
default/seaweedfs-s3-c8c4b78f8-d85sw                      Running    4   18d
default/seaweedfs-volume-0 … volume-7                     Running    2-4 15-19d
default/smtp-relay-mail-0                                 Running    4   19d
default/toolhive-operator-54bfb5d87c-7dwzq                Running    6   17h
default/whoami-697f8c6cbc-jgrpd                           Running    9   52d
kube-system/coredns-5f5694d56b-kcrqp                      Running    0   17h
kube-system/local-path-provisioner-58d557dc48-2hh2r       Running    0   17h
kube-system/metrics-server-786d997795-87fsm               Running    34  201d
kube-system/svclb-infra-samba-9e2351c6-gmh9k              Running    0   17h
kube-system/svclb-seaweedfs-filer-0…4 (5 pods)            Running    0   17h
kube-system/svclb-traefik-072ae627-449b4                  Running    0   17h
kube-system/traefik-5d485d94d8-255b2                      Running    0   17h
system-upgrade/system-upgrade-controller-79b7cb4856-jc5z9 Running   9   52d
```

### media
```
default/argocd-application-controller-0                   Running    1   17h
default/argocd-applicationset-controller-7bf45c67dd-sbz6h Running   1   17h
default/argocd-dex-server-847d9d6b84-tg6hk                Running    0   8m36s
default/argocd-notifications-controller-54b4b9db6-nd8rs   Running    0   8m35s
default/argocd-redis-6c57965868-jxkgm                     Running    1   17h
default/argocd-repo-server-6c89b79699-6zgdp               Running    1   17h
default/argocd-server-5b55856676-fjpbw                    Running    1   17h
default/bitwarden-cli-f9d48dc89-t6jqc                     Running    0   8m35s
default/mcp-kubernetes-admin-0                            Running    1   17h
default/mcp-kubernetes-admin-8b4d46cb4-zt2t2              Running    1   17h
default/mcp-kubernetes-readonly-0                         Running    1   17h
default/mcp-kubernetes-readonly-6b74dd687b-r7tt2          Running    1   17h
default/media-audiobookshelf-556d5959f6-rptsh             Running    0   8m34s
default/media-cert-manager-56d68b9876-6z885               Running    7   17h
default/media-cert-manager-cainjector-654898854-z4swg     Running    5   17h
default/media-cert-manager-webhook-55d87d49d7-4hwlz       Running    1   17h
default/media-external-secrets-bitwarden-77fb6c76b-87cf7  Running    0   8m33s
default/media-external-secrets-bitwarden-cert-controller-…8jcpb Running 0 8m33s
default/media-external-secrets-bitwarden-webhook-…7k4lw   Running    0   8m32s
default/media-jellyfin-555c496978-2gflh                   Running    0   8m31s
default/media-jellyseerr-584fb47479-knzd5                 Running    0   8m31s
default/media-k8s-monitoring-alloy-logs-nsfwv             Running    0   8m22s
default/media-k8s-monitoring-alloy-metrics-0              Running    0   91m
default/media-k8s-monitoring-alloy-operator-7cf4c4c846-trt9d Running 0 8m31s
default/media-k8s-monitoring-alloy-singleton-54fcfdbb58-nb4bt Running 0 8m29s
default/media-k8s-monitoring-kube-state-metrics-…rgx67    Running    0   8m29s
default/media-k8s-monitoring-node-exporter-qs64d          Running    0   7m48s
default/media-lidarr-7b6dd9d467-77hss                     Running    2   8m15s ⚠ 2 restarts in first 8m
default/media-prowlarr-5cf45459f5-w5tlr                   Running    1   8m13s ⚠
default/media-radarr-67fffb6f66-hk5sk                     Running    1   8m13s ⚠
default/media-readarr-dd8556f9d-2m8zn                     Running    1   8m13s ⚠
default/media-seaweedfs-csi-driver-controller-68f97bb688-tc5dj Running 0 8m12s
default/media-seaweedfs-csi-driver-mount-4wlnk            Running    0   7m55s
default/media-seaweedfs-csi-driver-node-6j84d             Running    0   8m1s
default/media-sonarr-55f89bb55-fk758                      Running    1   8m11s ⚠
default/media-tvheadend-5c78644c4f-nv4cx                  Running    1   17h
default/smtp-relay-mail-0                                 Running    0   7m46s
default/toolhive-operator-7fb48cb8b6-dx2fx                Running    7   17h
kube-system/coredns-5f5694d56b-l6jbl                      Running    1   17h
kube-system/helm-install-traefik-crd-8mb2k                Completed  0   17h
kube-system/helm-install-traefik-kjrk4                    Completed  2   17h
kube-system/local-path-provisioner-58d557dc48-cmtrq       Running    1   17h
kube-system/metrics-server-786d997795-2mk6s               Running    0   8m9s
kube-system/svclb-traefik-7721ba2e-sc8v2                  Running    3   17h
kube-system/traefik-7fc777cc94-nz5zf                      Running    1   17h
system-upgrade/system-upgrade-controller-79b7cb4856-wggkv Running   0   8m8s
```

### monitoring
```
default/alertmanager-monitoring-kube-prometheus-alertmanager-0 Running 0 6m50s
default/argocd-application-controller-0                   Running    0   17h
default/argocd-applicationset-controller-66966fdd56-lvttc Running   0   17h
default/argocd-dex-server-59546996c4-66974                Running    0   7m50s
default/argocd-notifications-controller-6d6cfbd5b4-ckd9b  Running    0   7m50s
default/argocd-redis-b9b659d54-bchv5                      Running    0   17h
default/argocd-repo-server-8659dbcf6f-bc7hh               Running    1   17h
default/argocd-server-7c655d6545-2mh9j                    Running    0   17h
default/bitwarden-cli-f9d48dc89-sbtwp                     Running    1   7m49s ⚠ churn continues (1 restart in 8m)
default/loki-backend-0                                    Running    0   17h
default/loki-canary-jfw4s                                 Running    0   17h
default/loki-read-85f88b8b68-hxkhc                        Running    0   17h
default/loki-write-0                                      Running    0   17h
default/mailcow-exporter-7448d685b9-cd9t8                 Running    0   7m48s (exit-2 cycle expected ~3h)
default/mcp-kubernetes-admin-0                            Running    0   17h
default/mcp-kubernetes-admin-8b4d46cb4-jn252              Running    0   17h
default/mcp-kubernetes-readonly-0                         Running    0   17h
default/mcp-kubernetes-readonly-6b74dd687b-46zk2          Running    0   17h
default/monitoring-cert-manager-5659b798b-xp5rs           Running    0   17h
default/monitoring-cert-manager-cainjector-564c84cb6-678ch Running  0   17h
default/monitoring-cert-manager-webhook-5b88f787dc-8hm57  Running    0   17h
default/monitoring-exporter-mikrotik-6cd8bc49df-z2b69     Running    0   7m47s
default/monitoring-external-secrets-bitwarden-596b55b4d4-44dx5 Running 0 7m47s
default/monitoring-external-secrets-bitwarden-cert-controller-c9f84lf4h Running 0 7m46s
default/monitoring-external-secrets-bitwarden-webhook-…dzqrp Running 0  7m45s
default/monitoring-grafana-8476f99b78-67zll               Running    0   17h
default/monitoring-grafana-image-renderer-… (3 pods)      Running    0   17h
default/monitoring-k8s-monitoring-alloy-logs-hpxcv        Running    0   6m43s
default/monitoring-k8s-monitoring-alloy-metrics-0         Running    0   47m
default/monitoring-k8s-monitoring-alloy-operator-77f59b7f9d-h56hk Running 0 7m44s
default/monitoring-k8s-monitoring-alloy-singleton-687c648bf4-7qx9b Running 0 7m41s
default/monitoring-k8s-monitoring-kube-state-metrics-…qxnzx Running 0  7m25s
default/monitoring-k8s-monitoring-node-exporter-dhbbc     Running    0   6m59s
default/monitoring-kube-prometheus-operator-6cd8475886-2pg54 Running 0 7m24s
default/monitoring-kube-prometheus-stack-kube-state-metrics-b6786djkckd Running 0 7m23s
default/monitoring-loki-chunks-cache-0                    Running    0   6m42s
default/monitoring-loki-gateway-7f59f986b9-t6n94          Running    0   7m15s
default/monitoring-loki-results-cache-0                   Running    0   6m40s
default/prometheus-monitoring-kube-prometheus-prometheus-0 Running   0   6m38s
default/smtp-relay-mail-0                                 Running    0   6m32s
default/toolhive-operator-698696488f-ktsfn                Running    0   17h
kube-system/coredns-5f5694d56b-ss75d                      Running    0   17h
kube-system/helm-install-traefik-crd-98kkt                Completed  0   17h
kube-system/helm-install-traefik-dgbv8                    Completed  3   17h
kube-system/local-path-provisioner-58d557dc48-8ztvv       Running    0   17h
kube-system/metrics-server-786d997795-8kfqs               Running    0   7m11s
kube-system/svclb-traefik-178b60e4-q6dvc                  Running    0   17h
kube-system/traefik-7fc777cc94-7v7vw                      Running    0   17h
system-upgrade/system-upgrade-controller-564c989b9c-lr6p7 Running   0   7m10s
```

### proxy-local
```
default/argocd-application-controller-0                   Running    0   16h
default/argocd-applicationset-controller-5d647fff68-5pfrm Running   0   16h
default/argocd-dex-server-5977cfb588-zzd9c                Running    0   7m
default/argocd-notifications-controller-5f7dfbd785-rd6fn  Running    0   7m
default/argocd-redis-794b84566b-gll72                     Running    0   16h
default/argocd-repo-server-79b85689c-wntb4                Running    0   16h
default/argocd-server-89685f5c4-bx8vb                     Running    0   16h
default/bitwarden-cli-675959f956-mf2db                    Running    0   6m59s
default/mcp-kubernetes-admin-0                            Running    0   16h
default/mcp-kubernetes-admin-8b4d46cb4-7mzqr              Running    0   16h
default/mcp-kubernetes-readonly-0                         Running    0   16h
default/mcp-kubernetes-readonly-6b74dd687b-jfq42          Running    0   16h
default/proxy-local-autossh-89866577f-jp4cx               Running    9   16h
default/proxy-local-backup-gpu-qbittorrent-6bc7b98b46-xz8xh Running 0  6m59s
default/proxy-local-cert-manager-84d5bdd994-d4qxz         Running    1   16h
default/proxy-local-cert-manager-cainjector-997bb7b4d-fzldq Running  1   16h
default/proxy-local-cert-manager-webhook-b74dfb9cc-sc2c5  Running    0   16h
default/proxy-local-external-dns-external-547b97577-4bqjn Running   0   6m58s
default/proxy-local-external-secrets-bitwarden-b65cbdd5b-sfdgv Running 0 16h
default/proxy-local-external-secrets-bitwarden-cert-controller-9f9cpz57 Running 0 16h
default/proxy-local-external-secrets-bitwarden-webhook-…b65tk Running 0 16h
default/proxy-local-k8s-monitoring-alloy-logs-4mcdp       Running    0   6m26s
default/proxy-local-k8s-monitoring-alloy-metrics-0        Running    0   91m
default/proxy-local-k8s-monitoring-alloy-operator-779d867574-w84rw Running 0 6m57s
default/proxy-local-k8s-monitoring-alloy-singleton-795bb4f598-bbnnm Running 0 6m57s
default/proxy-local-k8s-monitoring-kube-state-metrics-…2g5hd Running 0 6m56s
default/proxy-local-k8s-monitoring-node-exporter-z7864    Running    0   6m53s
default/proxy-local-metube-7f6b9868cf-rrwvk               Running    0   6m55s
default/proxy-local-pinchflat-b5b954765-vznkm             Running    0   6m54s
default/proxy-local-qbittorrent-69cc5486c7-98ggw          Running    2   6m42s ⚠ churn continues (2 restarts in 7m)
default/proxy-local-seaweedfs-csi-driver-controller-5bb79bdc65-pqvtl Running 0 6m41s
default/proxy-local-seaweedfs-csi-driver-mount-gd5gr      Running    0   6m39s
default/proxy-local-seaweedfs-csi-driver-node-j2mfz       Running    0   6m37s
default/smtp-relay-mail-0                                 Running    0   6m37s
default/toolhive-operator-6bb48fbcc-74qr4                 Running    2   16h
kube-system/bitwarden-cli-675959f956-8pmxs                Running    0   6m39s
kube-system/coredns-5f5694d56b-28fpn                      Running    0   16h
kube-system/helm-install-traefik-hnh2r                    Error      6   6m38s ⚠ new job pod already failing (known missing-CRD issue)
kube-system/local-path-provisioner-58d557dc48-8mm55       Running    0   16h
kube-system/metrics-server-786d997795-9wkq7               Running    0   6m38s
kube-system/proxy-local-external-secrets-bitwarden-kube-system-66994fcgfzn4 Running 0 16h
kube-system/proxy-local-traefik-agent-7zgnb               Running    0   6m34s
kube-system/proxy-local-traefik-lapi-5c8fc7fb6f-jk4m9     Running    0   6m37s
kube-system/svclb-proxy-local-backup-gpu-qbittorrent-…-15ahxq6n Running 0 16h
kube-system/svclb-proxy-local-qbittorrent-bittorent-6b0b2637-5f28w Running 0 16h
kube-system/svclb-traefik-f6bbbe08-hkhrt                  Running    0   16h
kube-system/traefik-78f76fc9b9-2zkgv                      Running    0   16h
system-upgrade/system-upgrade-controller-6ddd46bf8d-9ngnt Running   0   6m37s
```

## Post-reset anomalies to check tomorrow

1. **home-paperless-main** — `CreateContainerError` 1/4 with 9 restarts in its
   first 9 minutes after recreation (it was 4/4 Running before the reset).
   Investigate first — possible regression from the restart.
2. **home-postiz-temporal-*** — frontend/history/matching/worker each restarted
   2–3× during startup; may be dependency-order settling, verify stable by tomorrow.
3. **media *arr stack** (lidarr 2, prowlarr/radarr/readarr/sonarr 1 each) —
   single startup restarts in the first 8 minutes; verify no accumulation.
4. **gpu-archon** — 1 restart in first 11 minutes.
5. **proxy-local helm-install-traefik** — recreated job pod already Erroring
   (known missing-CRD root cause; will keep failing until fixed).
6. **monitoring bitwarden-cli / proxy-local qbittorrent** — churn already
   resumed within minutes of reset (known root causes).
