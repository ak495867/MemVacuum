import sys
import os
import time
import ctypes
from ctypes import wintypes
import argparse

def ensure_elevation():
    if any(arg in sys.argv for arg in ["-h", "--help"]):
        return
    try:
        if not ctypes.windll.shell32.IsUserAnAdmin():
            params = " ".join([f'"{arg}"' for arg in sys.argv])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, params, None, 1)
            sys.exit(0)
    except Exception:
        pass

ensure_elevation()

class LUID(ctypes.Structure):
    _fields_ = [("LowPart", wintypes.DWORD), ("HighPart", wintypes.LONG)]

class LUID_AND_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Luid", LUID), ("Attributes", wintypes.DWORD)]

class TOKEN_PRIVILEGES(ctypes.Structure):
    _fields_ = [("PrivilegeCount", wintypes.DWORD), ("Privileges", LUID_AND_ATTRIBUTES * 1)]

class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [
        ("dwLength", wintypes.DWORD),
        ("dwMemoryLoad", wintypes.DWORD),
        ("ullTotalPhys", ctypes.c_uint64),
        ("ullAvailPhys", ctypes.c_uint64),
        ("ullTotalPageFile", ctypes.c_uint64),
        ("ullAvailPageFile", ctypes.c_uint64),
        ("ullTotalVirtual", ctypes.c_uint64),
        ("ullAvailVirtual", ctypes.c_uint64),
        ("ullAvailExtendedVirtual", ctypes.c_uint64),
    ]

class MemVacuumEngine:
    def __init__(self, free_threshold_mb=1536, check_interval_sec=2, enable_timer_res=True, trim_bloat=True):
        self.free_threshold_bytes = free_threshold_mb * 1024 * 1024
        self.interval = check_interval_sec
        self.enable_timer_res = enable_timer_res
        self.trim_bloat = trim_bloat
        self.running = True
        self.purge_count = 0
        self.last_purge_time = 0
        self.purge_cooldown = 10
        self.advapi32 = ctypes.windll.advapi32
        self.kernel32 = ctypes.windll.kernel32
        self.user32 = ctypes.windll.user32
        self.psapi = ctypes.windll.psapi
        self.ntdll = ctypes.windll.ntdll
        self.bloat_names = [
            "chrome.exe", "msedge.exe", "discord.exe", 
            "spotify.exe", "steamwebhelper.exe", "epicgameslauncher.exe"
        ]
        self.boost_process_priority()
        self.enable_privilege("SeProfileSingleProcessPrivilege")
        self.enable_privilege("SeIncreaseQuotaPrivilege")
        self.enable_privilege("SeDebugPrivilege")
        if self.enable_timer_res:
            self.set_timer_resolution(5000)

    def boost_process_priority(self):
        try:
            self.kernel32.SetPriorityClass(self.kernel32.GetCurrentProcess(), 0x00000080)
        except Exception:
            pass

    def set_timer_resolution(self, resolution_100ns=5000):
        cur = ctypes.c_ulong()
        try:
            self.ntdll.NtSetTimerResolution(resolution_100ns, 1, ctypes.byref(cur))
            return cur.value
        except Exception:
            return 0

    def get_timer_resolution(self):
        min_res = ctypes.c_ulong()
        max_res = ctypes.c_ulong()
        cur_res = ctypes.c_ulong()
        try:
            self.ntdll.NtQueryTimerResolution(ctypes.byref(min_res), ctypes.byref(max_res), ctypes.byref(cur_res))
            return cur_res.value / 10000.0
        except Exception:
            return 15.625

    def enable_privilege(self, priv_name):
        token = wintypes.HANDLE()
        if self.advapi32.OpenProcessToken(self.kernel32.GetCurrentProcess(), 0x0028, ctypes.byref(token)):
            luid = LUID()
            if self.advapi32.LookupPrivilegeValueW(None, priv_name, ctypes.byref(luid)):
                tp = TOKEN_PRIVILEGES(1, (LUID_AND_ATTRIBUTES(luid, 2),))
                self.advapi32.AdjustTokenPrivileges(token, False, ctypes.byref(tp), 0, None, None)
            self.kernel32.CloseHandle(token)

    def get_memory_stats(self):
        stat = MEMORYSTATUSEX()
        stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if self.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
            return stat.ullTotalPhys, stat.ullAvailPhys
        return 0, 0

    def get_foreground_pid(self):
        hwnd = self.user32.GetForegroundWindow()
        if not hwnd:
            return 0
        pid = wintypes.DWORD()
        self.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        return pid.value

    def purge_standby_list(self):
        cmd = ctypes.c_int(4)
        res = self.ntdll.NtSetSystemInformation(80, ctypes.byref(cmd), ctypes.sizeof(cmd))
        return res == 0

    def purge_working_sets(self):
        cmd = ctypes.c_int(2)
        res = self.ntdll.NtSetSystemInformation(80, ctypes.byref(cmd), ctypes.sizeof(cmd))
        return res == 0

    def trim_background_bloat(self):
        fg_pid = self.get_foreground_pid()
        pids = (wintypes.DWORD * 2048)()
        cb_needed = wintypes.DWORD()
        if not self.psapi.EnumProcesses(ctypes.byref(pids), ctypes.sizeof(pids), ctypes.byref(cb_needed)):
            return
        count = int(cb_needed.value / ctypes.sizeof(wintypes.DWORD))
        buf = (ctypes.c_wchar * 260)()
        for i in range(count):
            pid = pids[i]
            if pid <= 4 or pid == fg_pid or pid == os.getpid():
                continue
            h_proc = self.kernel32.OpenProcess(0x0400 | 0x0100, False, pid)
            if not h_proc:
                continue
            if self.psapi.GetProcessImageFileNameW(h_proc, buf, 260) > 0:
                name = os.path.basename(buf.value).lower()
                if any(target in name for target in self.bloat_names):
                    self.psapi.EmptyWorkingSet(h_proc)
            self.kernel32.CloseHandle(h_proc)

    def execute_purge(self):
        now = time.time()
        if now - self.last_purge_time < self.purge_cooldown:
            return False
        s1 = self.purge_standby_list()
        s2 = self.purge_working_sets()
        if self.trim_bloat:
            self.trim_background_bloat()
        if s1 or s2:
            self.purge_count += 1
            self.last_purge_time = now
            return True
        return False

    def print_stats(self):
        total, avail = self.get_memory_stats()
        timer_ms = self.get_timer_resolution()
        fg_pid = self.get_foreground_pid()
        print(f"Total Physical RAM: {round(total / (1024**3), 2)} GB")
        print(f"Available Physical RAM: {round(avail / (1024**3), 2)} GB")
        print(f"System Timer Resolution: {round(timer_ms, 3)} ms")
        print(f"Active Foreground PID: {fg_pid}")
        print(f"Total Purge Operations: {self.purge_count}")

    def run(self):
        while self.running:
            total, avail = self.get_memory_stats()
            if avail > 0 and avail < self.free_threshold_bytes:
                self.execute_purge()
            time.sleep(self.interval)

def main():
    parser = argparse.ArgumentParser(prog="MemVacuum", description="Autonomous Standby RAM Purger, Bloat Trimmer, and 0.5ms Timer Engine")
    parser.add_argument("--free-threshold", type=int, default=1536, help="Available RAM threshold in MB to trigger purge")
    parser.add_argument("--interval", type=int, default=2, help="Memory sampling interval in seconds")
    parser.add_argument("--disable-timer", action="store_true", help="Disable 0.5ms system timer resolution clamping")
    parser.add_argument("--disable-trim", action="store_true", help="Disable background bloatware working set trimming")
    parser.add_argument("--purge-now", action="store_true", help="Execute immediate memory purge and exit")
    parser.add_argument("--stats", action="store_true", help="Display memory statistics and exit")
    args = parser.parse_args()
    engine = MemVacuumEngine(
        free_threshold_mb=args.free_threshold,
        check_interval_sec=args.interval,
        enable_timer_res=not args.disable_timer,
        trim_bloat=not args.disable_trim
    )
    if args.stats:
        engine.print_stats()
        return
    if args.purge_now:
        engine.execute_purge()
        engine.print_stats()
        return
    engine.run()

if __name__ == "__main__":
    main()
