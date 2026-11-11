# GPU host capacity — subscribed-region discovery

Observed November 11, 2026, 21:03:15–21:03:22 UTC using the DEFAULT profile and the combined native Terraform discovery stack. All 16 READY subscribed regions and 26 ADs were inspected. Terraform created 19 capacity reports plus 19 local bookkeeping resources; no GPU hosts were allocated.

There were 37 positive shape/AD observations and 23 out-of-host-capacity observations. Seven ADs listed no GPU shapes; that is an unknown physical inventory observation, not a zero-capacity report. Counts below are **instances**, not GPUs. AD labels are relative to this tenancy; prefixes/OCIDs are omitted. Results change with time and do not reserve hardware or establish RDMA placement.

Quota/headroom is separate: 1,226 supported resource-availability queries completed. Eleven regions have complete selected entitlement observations; Frankfurt, London, Ashburn, Chicago and Phoenix are partial because the default 100-query budget per region omitted 98 further limit/AD checks each. Those omitted values remain unknown. Entitlement was checked at root, not a selected deployment compartment.

The Qwen/Qwen2.5-0.5B-Instruct model lookup returned 988,065,536 declared weight bytes and a 3.729 GiB aggregate estimate at 4096 tokens × four sequences, including assumed runtime/margin. This does not establish a per-GPU layout or production throughput.

## Reported shape capacity

Different shapes can draw from overlapping host inventory; their available counts must not be added as independent supply.

| Region | AD label | Shape | GPUs per instance | Available instances | Report status |
|---|---|---|---:|---:|---|
| ap-chennai-1 | AP-CHENNAI-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| ap-delhi-1 | AP-DELHI-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| ap-hyderabad-1 | AP-HYDERABAD-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| ap-melbourne-1 | AP-MELBOURNE-1-AD-1 | BM.GPU.A10.4 | 4 | 6 | AVAILABLE |
| ap-melbourne-1 | AP-MELBOURNE-1-AD-1 | BM.GPU.B4.8 | 8 | 0 | OUT_OF_HOST_CAPACITY |
| ap-melbourne-1 | AP-MELBOURNE-1-AD-1 | BM.GPU4.8 | 8 | 0 | OUT_OF_HOST_CAPACITY |
| ap-melbourne-1 | AP-MELBOURNE-1-AD-1 | VM.GPU.A10.1 | 1 | 0 | OUT_OF_HOST_CAPACITY |
| ap-melbourne-1 | AP-MELBOURNE-1-AD-1 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| ap-mumbai-1 | AP-MUMBAI-1-AD-1 | BM.GPU.A10.4 | 4 | 4 | AVAILABLE |
| ap-mumbai-1 | AP-MUMBAI-1-AD-1 | BM.GPU4.8 | 8 | 1 | AVAILABLE |
| ap-mumbai-1 | AP-MUMBAI-1-AD-1 | VM.GPU.A10.1 | 1 | 108 | AVAILABLE |
| ap-mumbai-1 | AP-MUMBAI-1-AD-1 | VM.GPU.A10.2 | 2 | 44 | AVAILABLE |
| ap-osaka-1 | AP-OSAKA-1-AD-1 | BM.GPU.B4.8 | 8 | 2 | AVAILABLE |
| ap-osaka-1 | AP-OSAKA-1-AD-1 | BM.GPU4.8 | 8 | 1 | AVAILABLE |
| ap-sydney-1 | AP-SYDNEY-1-AD-1 | BM.GPU.A10.4 | 4 | 3 | AVAILABLE |
| ap-sydney-1 | AP-SYDNEY-1-AD-1 | VM.GPU.A10.1 | 1 | 4 | AVAILABLE |
| ap-sydney-1 | AP-SYDNEY-1-AD-1 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| ca-montreal-1 | CA-MONTREAL-1-AD-1 | BM.GPU.A10.4 | 4 | 35 | AVAILABLE |
| ca-montreal-1 | CA-MONTREAL-1-AD-1 | VM.GPU.A10.1 | 1 | 4 | AVAILABLE |
| ca-montreal-1 | CA-MONTREAL-1-AD-1 | VM.GPU.A10.2 | 2 | 1 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-1 | BM.GPU.A10.4 | 4 | 3 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-1 | BM.GPU.B4.8 | 8 | 0 | OUT_OF_HOST_CAPACITY |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-1 | BM.GPU4.8 | 8 | 2 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-1 | VM.GPU.A10.1 | 1 | 8 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-1 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-2 | BM.GPU.A10.4 | 4 | 2 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-2 | VM.GPU.A10.1 | 1 | 1 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-2 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-3 | BM.GPU.A10.4 | 4 | 2 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-3 | VM.GPU.A10.1 | 1 | 2 | AVAILABLE |
| eu-frankfurt-1 | EU-FRANKFURT-1-AD-3 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| eu-paris-1 | EU-PARIS-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| me-dubai-1 | ME-DUBAI-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| sa-saopaulo-1 | SA-SAOPAULO-1-AD-1 | BM.GPU.A10.4 | 4 | 3 | AVAILABLE |
| sa-saopaulo-1 | SA-SAOPAULO-1-AD-1 | VM.GPU.A10.1 | 1 | 5 | AVAILABLE |
| sa-saopaulo-1 | SA-SAOPAULO-1-AD-1 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| uk-london-1 | UK-LONDON-1-AD-1 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| uk-london-1 | UK-LONDON-1-AD-1 | VM.GPU.A10.1 | 1 | 3 | AVAILABLE |
| uk-london-1 | UK-LONDON-1-AD-1 | VM.GPU.A10.2 | 2 | 1 | AVAILABLE |
| uk-london-1 | UK-LONDON-1-AD-2 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| uk-london-1 | UK-LONDON-1-AD-2 | VM.GPU.A10.1 | 1 | 15 | AVAILABLE |
| uk-london-1 | UK-LONDON-1-AD-2 | VM.GPU.A10.2 | 2 | 5 | AVAILABLE |
| uk-london-1 | UK-LONDON-1-AD-3 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| uk-london-1 | UK-LONDON-1-AD-3 | VM.GPU.A10.1 | 1 | 2 | AVAILABLE |
| uk-london-1 | UK-LONDON-1-AD-3 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| us-ashburn-1 | US-ASHBURN-AD-1 | BM.GPU.A10.4 | 4 | 2 | AVAILABLE |
| us-ashburn-1 | US-ASHBURN-AD-1 | VM.GPU.A10.1 | 1 | 7 | AVAILABLE |
| us-ashburn-1 | US-ASHBURN-AD-1 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| us-ashburn-1 | US-ASHBURN-AD-2 | BM.GPU4.8 | 8 | 1 | AVAILABLE |
| us-ashburn-1 | US-ASHBURN-AD-3 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| us-ashburn-1 | US-ASHBURN-AD-3 | VM.GPU.A10.1 | 1 | 0 | OUT_OF_HOST_CAPACITY |
| us-ashburn-1 | US-ASHBURN-AD-3 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| us-chicago-1 | US-CHICAGO-1-AD-1 | — | — | unknown | no_gpu_shapes_listed |
| us-chicago-1 | US-CHICAGO-1-AD-2 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| us-chicago-1 | US-CHICAGO-1-AD-2 | VM.GPU.A10.1 | 1 | 0 | OUT_OF_HOST_CAPACITY |
| us-chicago-1 | US-CHICAGO-1-AD-2 | VM.GPU.A10.2 | 2 | 0 | OUT_OF_HOST_CAPACITY |
| us-chicago-1 | US-CHICAGO-1-AD-3 | — | — | unknown | no_gpu_shapes_listed |
| us-phoenix-1 | PHX-AD-1 | BM.GPU.A10.4 | 4 | 1 | AVAILABLE |
| us-phoenix-1 | PHX-AD-1 | VM.GPU.A10.1 | 1 | 35 | AVAILABLE |
| us-phoenix-1 | PHX-AD-1 | VM.GPU.A10.2 | 2 | 15 | AVAILABLE |
| us-phoenix-1 | PHX-AD-2 | BM.GPU.A10.4 | 4 | 0 | OUT_OF_HOST_CAPACITY |
| us-phoenix-1 | PHX-AD-2 | VM.GPU.A10.1 | 1 | 9 | AVAILABLE |
| us-phoenix-1 | PHX-AD-2 | VM.GPU.A10.2 | 2 | 2 | AVAILABLE |
| us-phoenix-1 | PHX-AD-3 | BM.GPU.A10.4 | 4 | 3 | AVAILABLE |
| us-phoenix-1 | PHX-AD-3 | BM.GPU.B4.8 | 8 | 0 | OUT_OF_HOST_CAPACITY |
| us-phoenix-1 | PHX-AD-3 | VM.GPU.A10.1 | 1 | 38 | AVAILABLE |
| us-phoenix-1 | PHX-AD-3 | VM.GPU.A10.2 | 2 | 16 | AVAILABLE |

## Local evidence

Full discovery JSON: `work/rms-discovery-result.json` (ignored; includes tenancy-specific metadata). Plan/apply logs and state are local. Run a new RMS apply with a changed `observation_id` before selecting a deployment; rerunning refresh with the same ID preserves report snapshots. The RMS service itself has not yet been tested.
