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
    def __init__(self, free_threshold_mb=1536, check_interval_sec=2):
        self.free_threshold_bytes = free_threshold_mb * 1024 * 1024
        self.interval = check_interval_sec
        self.running = True
        self.advapi32 = ctypes.windll.advapi32
        self.kernel32 = ctypes.windll.kernel32
        self.ntdll = ctypes.windll.ntdll
        self.enable_privilege("SeProfileSingleProcessPrivilege")
        self.enable_privilege("SeIncreaseQuotaPrivilege")

    def enable_privilege(self, priv_name):
        token = wintypes.HANDLE()
        if self.advapi32.OpenProcessToken(self.kernel32.GetCurrentProcess(), 0x0028, ctypes.byref(token)):
            luid = LUID()
            if self.advapi32.LookupPrivilegeValueW(None, priv_name, ctypes.byref(luid)):
                tp = TOKEN_PRIVILEGES(1, (LUID_AND_ATTRIBUTES(luid, 2),))
                self.advapi32.AdjustTokenPrivileges(token, False, ctypes.byref(tp), 0, None, None)
            self.kernel32.CloseHandle(token)

    def get_available_phys_memory(self):
        stat = MEMORYSTATUSEX()
        stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if self.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
            return stat.ullAvailPhys
        return 0

    def purge_standby_list(self):
        cmd = ctypes.c_int(4)
        res = self.ntdll.NtSetSystemInformation(80, ctypes.byref(cmd), ctypes.sizeof(cmd))
        return res == 0

    def purge_working_sets(self):
        cmd = ctypes.c_int(2)
        res = self.ntdll.NtSetSystemInformation(80, ctypes.byref(cmd), ctypes.sizeof(cmd))
        return res == 0

    def execute_purge(self):
        s1 = self.purge_standby_list()
        s2 = self.purge_working_sets()
        return s1 or s2

    def run(self):
        while self.running:
            avail = self.get_available_phys_memory()
            if avail > 0 and avail < self.free_threshold_bytes:
                self.execute_purge()
                time.sleep(2)
            time.sleep(self.interval)

def main():
    parser = argparse.ArgumentParser(prog="MemVacuum", description="Standby RAM and Working Set Micro-Stutter Purger")
    parser.add_argument("--threshold", type=int, default=1536, help="Available RAM threshold in MB to trigger purge")
    parser.add_argument("--interval", type=int, default=2, help="Memory sampling interval in seconds")
    parser.add_argument("--purge-now", action="store_true", help="Execute immediate memory purge and exit")
    args = parser.parse_args()
    engine = MemVacuumEngine(free_threshold_mb=args.threshold, check_interval_sec=args.interval)
    if args.purge_now:
        engine.execute_purge()
        return
    engine.run()

if __name__ == "__main__":
    main()
