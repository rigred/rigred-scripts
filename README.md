# Rigo's Scripts Collection

This is a curated suite of **shell diagnostics** and **performance-tuning** tools for Linux.  
Every script follows the same pattern:

* `#!/usr/bin/env bash` with `set -Eeuo pipefail`
* Self-documenting `-h/--help`, `-o/--output FILE` flags
* Graceful degradation when optional utilities are missing
* Clear, sectioned output ready for pasting into tickets or ChatGPT

All scripts are developed in the open under MIT License.

---

## Quick start

### One-shot bundle

```bash
curl -LO https://raw.githubusercontent.com/rigred/rigred-scripts/refs/heads/main/diagnostics/collect-support-bundle.sh
chmod +x collect-support-bundle.sh
sudo ./collect-support-bundle.sh         # produces support-bundle-<host>-<date>.tar.gz
````

### Single script

```bash
wget https://raw.githubusercontent.com/rigred/rigred-scripts/refs/heads/main/diagnostics/get-numa-info.sh
chmod +x get-numa-info.sh
sudo ./get-numa-info.sh -o numa.txt
```

---

## Repository layout

```
diagnostics/   # Hardware + OS snapshots (NUMA, GPU, I/O, security, …)
networking/    # Net-tuning helpers (irqbalance, RSS, bpf, …)
hardware/      # Low-level flash / microcode tools
utils/         # Small one-liners, colour log helpers, etc.
```

---

## Script index

| Category           | Script                                                            | Purpose / Highlight                                                 |
| ------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Meta**           | `collect-support-bundle.sh`                                       | Run every helper available, redact host/IP, output a single tarball |
| **CPU & Memory**   | `get-cpu-info.sh` <br> `get-numa-info.sh` <br> `get-mem-usage.sh` | Micro-code & flags, NUMA topology, high-res mem pressure            |
| **I/O & Storage**  | `get-io-profile.sh` <br> `get-storage-health.sh`                  | Live `iostat/pidstat` hot-spots, SMART/NVMe/RAID health             |
| **PCIe**           | `get-pcie-topology.sh`                                            | Tree view + link speed/width, AER/ACS flags                         |
| **Network**        | `get-net-info.sh`                                                 | Link state, offload flags, IRQ/RSS affinity                         |
| **Security**       | `get-security-posture.sh`                                         | SELinux/AppArmor, nftables, lockdown, encrypted disks               |
| **Kernel tune**    | `get-sysctl-diff.sh`                                              | Diff running sysctl vs distro defaults                              |
| **Firmware**       | `get-firmware-versions.sh`                                        | Motherboard/BMC/NIC/drive FW audit                                  |
| **Virtualisation** | `detect-virtualization.sh`                                        | Hypervisor, nested-virt flags, hosted VMs / containers              |
| **GPU**            | `get-gpu-info.sh`                                                 | PCIe link, VRAM, temps, full `nvidia-smi` / ROCm / intel            |
| **Compute APIs**   | `get-compute-api-info.sh`                                         | CUDA, ROCm/HIP, OpenCL, SYCL, Vulkan-compute                        |
| **Graphics APIs**  | `get-rendering-api-info.sh`                                       | OpenGL/GLX, EGL/Wayland, Vulkan-graphics                            |
| **AI/ML stack**    | `get-ml-stack-info.sh`                                            | HW accelerator match, cuDNN/oneDNN libs, TF/PyTorch versions        |

*All scripts live in **diagnostics/** and are self-contained Bash; no Python deps except the optional framework probe in `get-ml-stack-info.sh`.*

---

## Contributing

1. Fork
2. `git checkout -b feature/amazing-script`
3. `git commit -s -m 'feat(diag): add amazing-script'`
4. `git push`
5. Open a PR 🙌

---

## License

[MIT](LICENSE)