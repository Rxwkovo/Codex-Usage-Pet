$ErrorActionPreference = 'Stop'
function Assert($condition, [string]$message) { if (-not $condition) { throw $message } }

$root = Split-Path $PSScriptRoot
$sandbox = Join-Path $env:TEMP ('CodexPet-persistent-test-' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $sandbox 'bin'
[void][IO.Directory]::CreateDirectory($bin)
$fakeExe = Join-Path $bin 'codex.exe'
$starts = Join-Path $sandbox 'starts.txt'
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;

public class FakeCodex {
    public static void Main(string[] args) {
        File.AppendAllText(Environment.GetEnvironmentVariable("FAKE_STARTS"), Process.GetCurrentProcess().Id + "\n");
        string mode = Environment.GetEnvironmentVariable("FAKE_MODE") ?? "ok";
        if (mode == "hang") { Thread.Sleep(30000); return; }
        string line;
        while ((line = Console.ReadLine()) != null) {
            Match id = Regex.Match(line, "\\\"id\\\"\\s*:\\s*(\\d+)");
            if (line.Contains("\"method\":\"initialize\"")) {
                if (mode == "malformed") { Console.WriteLine("{broken"); continue; }
                Console.WriteLine("{\"id\":" + id.Groups[1].Value + ",\"result\":{}}");
            } else if (line.Contains("\"method\":\"account/rateLimits/read\"")) {
                Console.WriteLine("{\"method\":\"account/updated\",\"params\":{}}");
                Console.WriteLine("{\"id\":999,\"result\":{}}");
                Console.WriteLine("{\"id\":" + id.Groups[1].Value + ",\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"windowDurationMins\":300,\"usedPercent\":25,\"resetsAt\":9999999999},\"secondary\":{\"windowDurationMins\":10080,\"usedPercent\":60,\"resetsAt\":9999999999}}}}");
            }
        }
    }
}
'@

function Start-FakeWorker([string]$mode) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $sandbox 'read-usage.ps1') + '" -Persistent -DirectOnly'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.EnvironmentVariables['PATH'] = $bin + ';C:\Windows\System32'
    $info.EnvironmentVariables['LOCALAPPDATA'] = $sandbox
    $info.EnvironmentVariables['FAKE_STARTS'] = $starts
    $info.EnvironmentVariables['FAKE_MODE'] = $mode
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    return $process
}

function Refresh-FakeWorker($process, [int]$timeoutMs) {
    $reply = $process.StandardOutput.ReadLineAsync()
    $process.StandardInput.WriteLine('refresh')
    Assert ($reply.Wait($timeoutMs)) 'The quota worker did not acknowledge a bounded refresh'
    Assert ($reply.Result -eq 'done') ('Unexpected quota worker reply: ' + $reply.Result)
    $usage = Get-Content -LiteralPath (Join-Path $sandbox 'usage.json') -Raw | ConvertFrom-Json
    return $usage
}

function Stop-FakeWorker($process) {
    $process.StandardInput.WriteLine('stop')
    Assert ($process.WaitForExit(5000)) 'The persistent worker did not exit after stop'
    $process.Dispose()
    if (Test-Path -LiteralPath $starts) {
        foreach ($pidText in @(Get-Content -LiteralPath $starts)) {
            if (-not $pidText) { continue }
            $alive = $false
            try { $child = [Diagnostics.Process]::GetProcessById([int]$pidText); $alive = -not $child.HasExited; $child.Dispose() } catch { }
            Assert (-not $alive) ('Fake app-server child survived worker stop: ' + $pidText)
        }
    }
}

try {
    Add-Type -TypeDefinition $source -OutputAssembly $fakeExe -OutputType ConsoleApplication
    Copy-Item -LiteralPath (Join-Path $root 'read-usage.ps1') -Destination $sandbox
    Copy-Item -LiteralPath (Join-Path $root 'usage-core.ps1') -Destination $sandbox

    $worker = Start-FakeWorker 'ok'
    try {
        $one = Refresh-FakeWorker $worker 10000
        $two = Refresh-FakeWorker $worker 10000
        Assert ($one.status -eq 'ok' -and $two.status -eq 'ok') 'Both refreshes must succeed'
        Assert ($two.fiveHour.remaining -eq 75 -and $two.weekly.remaining -eq 40) 'Quota windows must remain separate'
        Assert (@(Get-Content -LiteralPath $starts).Count -eq 1) 'Two refreshes must reuse a single app-server process'
    } finally { Stop-FakeWorker $worker }

    Remove-Item -LiteralPath $starts -Force
    $worker = Start-FakeWorker 'malformed'
    try {
        $failed = Refresh-FakeWorker $worker 10000
        Assert ($failed.status -eq 'stale' -and $failed.failureCount -eq 1) 'Malformed JSON must retain stale data'
    } finally { Stop-FakeWorker $worker }

    Remove-Item -LiteralPath $starts -Force
    $worker = Start-FakeWorker 'hang'
    try {
        $timedOut = Refresh-FakeWorker $worker 17000
        Assert ($timedOut.status -eq 'stale' -and $timedOut.failureCount -eq 2) 'Timed-out initialization must preserve stale data'
    } finally { Stop-FakeWorker $worker }

    'PASS: persistent reuse, ID/notification filtering, malformed response, timeout, and child cleanup'
} finally {
    $safeRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    $safeTarget = [IO.Path]::GetFullPath($sandbox)
    if ($safeTarget.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($safeTarget).StartsWith('CodexPet-persistent-test-') -and
        (Test-Path -LiteralPath $safeTarget)) {
        Remove-Item -LiteralPath $safeTarget -Recurse -Force
    }
}
