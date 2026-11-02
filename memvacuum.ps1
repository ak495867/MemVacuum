param(
    [int]$ThresholdMB = 1536,
    [int]$Interval = 2,
    [switch]$PurgeNow
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($ThresholdMB) { $argList += " -ThresholdMB $ThresholdMB" }
    if ($Interval) { $argList += " -Interval $Interval" }
    if ($PurgeNow) { $argList += " -PurgeNow" }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeMemOps {
    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

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

if ($PurgeNow) {
    [NativeMemOps]::FlushStandbyList()
    exit 0
}

$thresholdBytes = [ulong]($ThresholdMB * 1024 * 1024)

while ($true) {
    $avail = [NativeMemOps]::GetAvailPhysBytes()
    if ($avail -gt 0 -and $avail -lt $thresholdBytes) {
        [NativeMemOps]::FlushStandbyList()
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Seconds $Interval
}
