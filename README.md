# MemVacuum: Autonomous Standby RAM and Working Set Micro-Stutter Purger

MemVacuum is an autonomous Windows memory optimization daemon designed to eliminate micro-stutters, frame time spikes, and paging latency during gaming and heavy compute workloads. It actively monitors unallocated physical memory and automatically purges the Windows Standby Cache and bloated working sets before Windows is forced into high-latency pagefile writeouts.

---

## The Technical Problem: Why Games Micro-Stutter

Windows employs an aggressive file-caching policy known as the Standby List. Every executable, texture, video file, or web asset loaded into memory remains cached in physical RAM even after the application closes.

In competitive gaming (titles such as Call of Duty: Warzone, Rust, Counter-Strike 2, and Escape from Tarkov), asset-streaming engines demand massive blocks of contiguous, unallocated physical memory. When available free RAM drops below 1 GB to 1.5 GB, the Windows Memory Manager encounters page allocation bottlenecks. It must synchronously flush and repage dirty standby cache blocks to the storage drive (NVMe SSD or pagefile) before granting memory to the active game process.

This synchronous blocking operation results in noticeable 50ms to 200ms frame time spikes and micro-stutters, despite Task Manager displaying high overall RAM allocation.

MemVacuum solves this by monitoring available physical pages in real-time and proactively clearing the Standby List via native Windows NT kernel APIs before allocation starvation occurs.

---

## How It Works

### 1. Real-Time Memory Sampling
MemVacuum utilizes `GlobalMemoryStatusEx` to continuously sample `ullAvailPhys` (unallocated physical memory) at a configurable polling interval (default: 2 seconds) with negligible CPU impact.

### 2. Privilege Escalation
To purge the global operating system Standby List, the calling process must hold `SeProfileSingleProcessPrivilege` and `SeIncreaseQuotaPrivilege`. MemVacuum automatically adjusts its process token via `OpenProcessToken` and `AdjustTokenPrivileges`.

### 3. Native NT Kernel Information Commands
When unallocated physical RAM falls below the threshold (default: 1536 MB), MemVacuum invokes:
* `NtSetSystemInformation` with `SystemMemoryListInformation = 80` and command `MemoryPurgeStandbyList = 4`.
* `NtSetSystemInformation` with command `MemoryEmptyWorkingSets = 2`.

This flushes all cached standby file pages back to the free page pool in less than 5 milliseconds, keeping frame times perfectly smooth and consistent.

---

## Directory Structure

* `memvacuum.py` - Core cross-platform Python implementation with ctypes Windows NT kernel integration.
* `memvacuum.ps1` - Pure native PowerShell implementation compiling C# interop on the fly.
* `install_memvacuum.bat` - Automated one-click background task installer running with elevated privileges at logon.
* `uninstall_memvacuum.bat` - Clean remover script to stop and delete the scheduled task.

---

## Installation and Usage

### One-Click Background Service
Right-click `install_memvacuum.bat` and select "Run as administrator" (or double-click to accept the auto-elevation UAC prompt). It registers and runs `MemVacuumSentinel` as a hidden background task.

### Manual Console Mode (PowerShell)
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1
```

To configure custom thresholds:
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1 -ThresholdMB 2048 -Interval 1
```

### Instant Emergency Purge
To instantly clear all standby cache and working sets immediately:
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1 -PurgeNow
```
Or via Python:
```bash
python memvacuum.py --purge-now
```

---

## Uninstallation

To remove the background task, run:
```bat
.\uninstall_memvacuum.bat
```
