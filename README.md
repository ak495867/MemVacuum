# MemVacuum: Autonomous Standby RAM Purger, Background Bloat Trimmer, and 0.5ms Timer Resolution Engine

MemVacuum is an autonomous Windows performance daemon engineered to eliminate micro-stutters, frame pacing spikes, and paging latency during gaming and intensive workloads. It continuously monitors physical memory thresholds, purges bloated Windows Standby Caches before allocation bottlenecks occur, selectively trims dormant background electron bloatware, protects active foreground games, and clamps the Windows kernel scheduler to an ultra-low latency 0.5ms timer resolution.

---

## Technical Overview: The Dual Causes of Micro-Stutters

### 1. The Standby List Allocation Bottleneck
Windows caches previously executed binaries, textures, and assets in an aggressive memory pool called the Standby List. In competitive gaming (Call of Duty: Warzone, Rust, Counter-Strike 2, Apex Legends), game engines stream gigabytes of map assets into RAM on the fly.

When available unallocated memory drops below 1 GB to 1.5 GB, the Windows Memory Manager encounters a synchronous allocation block. It pauses the active application thread while flushing dirty standby pages to storage or the pagefile, causing visible 50ms to 200ms frame time spikes.

### 2. Dormant Background Working Set Bloat
Modern background applications (Discord, Chrome, Edge, Spotify, Steam Web Helper) are built on Chromium and Electron frameworks that hold gigabytes of private working sets in RAM even when minimized. When gaming, these dormant pages occupy physical memory that should belong to the active game engine.

### 3. Default 15.6ms Windows Scheduler Jitter
The default Windows kernel timer resolution is 15.625ms (64 Hz). For high refresh rate gaming (144Hz, 240Hz, 360Hz) and high-polling mice (1000Hz - 8000Hz), this coarse timer causes input sampling delays and frame pacing jitter.

MemVacuum solves all three issues simultaneously: it purges the Standby List via native NT APIs in under 5 milliseconds, selectively vacates background bloat working sets without closing them, and locks the kernel timer resolution to 0.5ms (500 microseconds).

---

## Core Capabilities

1. Real-Time Memory Sampling: Evaluates physical memory via GlobalMemoryStatusEx with zero measurable CPU overhead.
2. Kernel Privilege Management: Dynamically acquires SeProfileSingleProcessPrivilege, SeIncreaseQuotaPrivilege, and SeDebugPrivilege within the process token.
3. Native NT Standby Purge: Issues NtSetSystemInformation commands (MemoryPurgeStandbyList = 4 and MemoryEmptyWorkingSets = 2) directly to ntdll.
4. Selective Background Bloat Trimming: Enumerates processes and uses EmptyWorkingSet to recover 1 GB to 3 GB of private memory from idle background applications (Chrome, Discord, Edge, Spotify, Steam) during memory constraints.
5. Active Foreground Game Protection: Queries the foreground window via GetForegroundWindow and GetWindowThreadProcessId to ensure active games are never trimmed or interrupted.
6. High-Priority Scheduler Execution: Boosts its own process priority to HIGH_PRIORITY_CLASS to prevent thread starvation under 100% CPU load.
7. High-Precision 0.5ms Timer Resolution: Calls NtSetTimerResolution(5000, 1) to reduce system scheduling latency from 15.6ms down to 0.5ms.
8. Thrashing Prevention: Implements a 10-second rate-limiting cooldown between purge events to protect storage I/O and CPU queues.
9. Zero-Comment Architecture: Entire codebase is 100% comment-free for direct execution flow and minimal footprint.

---

## Directory Structure

* `memvacuum.py` - Core Python engine with native ctypes interop, timer resolution tuning, bloat trimming, and CLI arguments.
* `memvacuum.ps1` - Pure native PowerShell daemon compiling C# memory structs on the fly with zero external dependencies.
* `install_memvacuum.bat` - One-click background task installer running with elevated privileges at logon.
* `uninstall_memvacuum.bat` - Clean remover script to stop and delete the scheduled task.

---

## Installation and Usage

### One-Click Background Service
Right-click `install_memvacuum.bat` and select "Run as administrator" (or double-click to accept the auto-elevation UAC prompt). It registers and runs `MemVacuumSentinel` as a hidden background task.

### Display Real-Time System Stats
To view total RAM, available RAM, active foreground PID, and current timer resolution:
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1 -Stats
```
Or via Python:
```bash
python memvacuum.py --stats
```

### Instant Emergency Purge and Bloat Trim
To instantly clear all standby cache and trim background memory:
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1 -PurgeNow
```
Or via Python:
```bash
python memvacuum.py --purge-now
```

### Manual Console Mode
```powershell
powershell -ExecutionPolicy Bypass -File .\memvacuum.ps1 -ThresholdMB 2048 -Interval 1
```

---

## Uninstallation

To remove the background task, run:
```bat
.\uninstall_memvacuum.bat
```
