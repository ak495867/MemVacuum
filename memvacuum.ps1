param(
    [int]$ThresholdMB = 1536,
    [int]$Interval = 2,
    [switch]$DisableTimer,
    [switch]$PurgeNow,
    [switch]$Stats
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($ThresholdMB) { $argList += " -ThresholdMB $ThresholdMB" }
    if ($Interval) { $argList += " -Interval $Interval" }
    if ($DisableTimer) { $argList += " -DisableTimer" }
    if ($PurgeNow) { $argList += " -PurgeNow" }
    if ($Stats) { $argList += " -Stats" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeMemOps {
    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

    [DllImport("ntdll.dll")]
    public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);

    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, int DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    public static void EnablePrivilege(string privilege) {
        IntPtr hToken;
        if (OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x0028, out hToken)) {
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Attributes = 0x00000002;
            LookupPrivilegeValue(null, privilege, out tp.Luid);
            AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }

    public static ulong GetAvailPhysBytes() {
        MEMORYSTATUSEX stat = new MEMORYSTATUSEX();
        stat.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (GlobalMemoryStatusEx(ref stat)) {
            return stat.ullAvailPhys;
        }
        return 0;
    }

    public static ulong GetTotalPhysBytes() {
        MEMORYSTATUSEX stat = new MEMORYSTATUSEX();
        stat.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (GlobalMemoryStatusEx(ref stat)) {
            return stat.ullTotalPhys;
        }
        return 0;
    }

    public static double GetCurrentTimerResolutionMs() {
        uint min, max, cur;
        if (NtQueryTimerResolution(out min, out max, out cur) == 0) {
            return cur / 10000.0;
        }
        return 15.625;
    }

    public static void SetHighPrecisionTimer() {
        uint cur;
        NtSetTimerResolution(5000, true, out cur);
    }

    public static void FlushStandbyList() {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        EnablePrivilege("SeIncreaseQuotaPrivilege");
        int cmd = 4;
        IntPtr pCmd = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(pCmd, cmd);
        NtSetSystemInformation(80, pCmd, 4);
        Marshal.FreeHGlobal(pCmd);

        int cmdWs = 2;
        IntPtr pCmdWs = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(pCmdWs, cmdWs);
        NtSetSystemInformation(80, pCmdWs, 4);
        Marshal.FreeHGlobal(pCmdWs);
    }
}
"@

if (-not $DisableTimer) {
    [NativeMemOps]::SetHighPrecisionTimer()
}

if ($Stats) {
    $totalGb = [Math]::Round([NativeMemOps]::GetTotalPhysBytes() / 1GB, 2)
    $availGb = [Math]::Round([NativeMemOps]::GetAvailPhysBytes() / 1GB, 2)
    $timerMs = [Math]::Round([NativeMemOps]::GetCurrentTimerResolutionMs(), 3)
    Write-Host "Total Physical RAM: $totalGb GB"
    Write-Host "Available Physical RAM: $availGb GB"
    Write-Host "System Timer Resolution: $timerMs ms"
    exit 0
}

if ($PurgeNow) {
    [NativeMemOps]::FlushStandbyList()
    $availGb = [Math]::Round([NativeMemOps]::GetAvailPhysBytes() / 1GB, 2)
    Write-Host "Standby cache purged. Available RAM: $availGb GB"
    exit 0
}

$thresholdBytes = [ulong]($ThresholdMB * 1024 * 1024)
$lastPurge = [DateTime]::MinValue

while ($true) {
    $avail = [NativeMemOps]::GetAvailPhysBytes()
    $now = [DateTime]::UtcNow
    if ($avail -gt 0 -and $avail -lt $thresholdBytes) {
        if (($now - $lastPurge).TotalSeconds -ge 10) {
            [NativeMemOps]::FlushStandbyList()
            $lastPurge = $now
        }
    }
    Start-Sleep -Seconds $Interval
}
