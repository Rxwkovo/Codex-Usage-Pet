param(
    [switch]$DirectOnly,
    [switch]$Persistent,
    [double]$RefreshSeconds = 60,
    [double]$StaleSeconds = 120,
    [double]$HappyThreshold = 50,
    [double]$WorriedThreshold = 20
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'usage-core.ps1')

$policy = Get-UsagePolicy @{
    refreshSeconds = $RefreshSeconds
    staleSeconds = $StaleSeconds
    happyThreshold = $HappyThreshold
    worriedThreshold = $WorriedThreshold
}
$outputPath = Join-Path $PSScriptRoot 'usage.json'

$script:currentSession = $null

function Get-CodexExe {
    $codex = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($null -eq $codex) {
        $codex = Get-ChildItem -Path "$env:LOCALAPPDATA/OpenAI/Codex/bin/*/codex.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $exe = $codex.FullName
    } else {
        $exe = $codex.Source
    }
    if (-not $exe) { throw 'Codex CLI unavailable' }
    return $exe
}

function Start-CodexProcess([bool]$direct) {
    $exe = Get-CodexExe
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = 'app-server'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true

    if ($direct) {
        foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')) {
            $info.EnvironmentVariables.Remove($key)
        }
        $info.EnvironmentVariables['NO_PROXY'] = '*'
    } elseif (-not $info.EnvironmentVariables['HTTPS_PROXY']) {
        # Honor the Windows proxy setting when Explorer did not inherit proxy variables.
        $destination = [Uri]'https://chatgpt.com'
        $proxy = [Net.WebRequest]::GetSystemWebProxy().GetProxy($destination)
        if ($proxy -and $proxy.AbsoluteUri -ne $destination.AbsoluteUri) {
            $info.EnvironmentVariables['HTTPS_PROXY'] = $proxy.AbsoluteUri
        }
    }

    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $started = $false
    try {
        [void]$proc.Start()
        $started = $true
        # Drain redirected stderr asynchronously to prevent pipe deadlocks.
        # Never surface its contents: the CLI may include account details.
        $stderrTask = $proc.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    } catch {
        if ($started) {
            try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
        }
        $proc.Dispose()
        throw
    }

    return @{
        Process = $proc
        Direct = $direct
        StderrTask = $stderrTask
        Initialized = $false
        NextRequestId = 1
    }
}

function Stop-CodexSession($session) {
    if ($null -eq $session) { return }
    $proc = $session.Process
    if ($null -ne $proc) {
        try {
            if (-not $proc.HasExited) {
                $proc.Kill()
                [void]$proc.WaitForExit(2000)
            }
        } catch { }
        try {
            $proc.Dispose()
        } catch { }
    }
}

function Read-CodexResponse($session, [long]$expectedId, [DateTime]$deadline, [string]$actionName) {
    $proc = $session.Process
    $pending = $proc.StandardOutput.ReadLineAsync()
    while ([DateTime]::UtcNow -lt $deadline -and -not $proc.HasExited) {
        if (-not $pending.IsCompleted) {
            Start-Sleep -Milliseconds 50
            continue
        }
        $line = $pending.Result
        if ($null -eq $line) {
            break
        }

        # Reject malformed JSON
        $message = $null
        try {
            $message = $line | ConvertFrom-Json
        } catch {
            throw 'Malformed JSON received from Codex CLI'
        }
        if ($null -eq $message) {
            throw 'Malformed JSON received from Codex CLI'
        }

        # Ignore unrelated notifications and IDs
        $msgId = $null
        if ($message -is [Collections.IDictionary] -and $message.Contains('id')) {
            $msgId = $message['id']
        } elseif ($null -ne $message.PSObject.Properties['id']) {
            $msgId = $message.id
        }

        if ($null -ne $msgId -and "$msgId" -eq "$expectedId") {
            # Check for error
            $hasError = $false
            if ($message -is [Collections.IDictionary] -and $message.Contains('error') -and $null -ne $message['error']) {
                $hasError = $true
            } elseif ($null -ne $message.PSObject.Properties['error'] -and $null -ne $message.error) {
                $hasError = $true
            }
            if ($hasError) {
                if ($actionName -eq 'initialize') {
                    throw 'Initialization failed'
                } else {
                    throw 'Sign in to Codex with ChatGPT and retry'
                }
            }

            # Check for result
            $hasResult = $false
            $resVal = $null
            if ($message -is [Collections.IDictionary] -and $message.Contains('result')) {
                $hasResult = $true
                $resVal = $message['result']
            } elseif ($null -ne $message.PSObject.Properties['result']) {
                $hasResult = $true
                $resVal = $message.result
            }

            if (-not $hasResult -or $null -eq $resVal) {
                throw "Usage response missing result for $actionName"
            }

            return $resVal
        }

        $pending = $proc.StandardOutput.ReadLineAsync()
    }

    if ($proc.HasExited) {
        throw ('Codex CLI exited with code ' + $proc.ExitCode + ' before returning usage')
    }
    throw 'Usage request timed out'
}

function Start-And-Init-Session([bool]$direct) {
    $session = Start-CodexProcess $direct
    try {
        $proc = $session.Process
        $timeout = if ($direct) { 12 } else { 25 }
        $deadline = [DateTime]::UtcNow.AddSeconds($timeout)

        $initId = $session.NextRequestId++
        $initPayload = @{
            id = $initId
            method = 'initialize'
            params = @{
                clientInfo = @{
                    name = 'codex_pet'
                    title = 'Codex Pet'
                    version = '1.0.0'
                }
            }
        } | ConvertTo-Json -Compress -Depth 5
        $proc.StandardInput.WriteLine($initPayload)

        [void](Read-CodexResponse $session $initId $deadline 'initialize')

        $initializedPayload = @{
            method = 'initialized'
            params = @{}
        } | ConvertTo-Json -Compress -Depth 5
        $proc.StandardInput.WriteLine($initializedPayload)

        $session.Initialized = $true
        $session.FirstDeadline = $deadline
        return $session
    } catch {
        Stop-CodexSession $session
        throw
    }
}

function Request-RateLimits($session) {
    $proc = $session.Process
    $timeout = if ($session.Direct) { 12 } else { 25 }
    $deadline = if ($null -ne $session.FirstDeadline) {
        $first = $session.FirstDeadline
        $session.FirstDeadline = $null
        $first
    } else {
        [DateTime]::UtcNow.AddSeconds($timeout)
    }

    $reqId = $session.NextRequestId++
    $reqPayload = @{
        id = $reqId
        method = 'account/rateLimits/read'
        params = @{}
    } | ConvertTo-Json -Compress -Depth 5
    $proc.StandardInput.WriteLine($reqPayload)

    $rawResult = Read-CodexResponse $session $reqId $deadline 'account/rateLimits/read'
    $result = Convert-Usage $rawResult $policy
    if ($null -eq $result.fiveHour -and $null -eq $result.weekly) {
        throw 'Usage response contains no recognized quota windows'
    }
    if ($result -is [Collections.IDictionary]) {
        $result['route'] = $(if ($session.Direct) { 'direct' } else { 'system' })
    } else {
        $result | Add-Member -NotePropertyName route -NotePropertyValue $(if ($session.Direct) { 'direct' } else { 'system' }) -Force
    }
    return $result
}

function Invoke-UsageRefresh {
    $success = $false
    try {
        if ($null -ne $script:currentSession -and $script:currentSession.Process.HasExited) {
            Stop-CodexSession $script:currentSession
            $script:currentSession = $null
        }
        if ($null -ne $script:currentSession -and -not $script:currentSession.Process.HasExited) {
            try {
                $result = Request-RateLimits $script:currentSession
                $success = $true
            } catch {
                Stop-CodexSession $script:currentSession
                $script:currentSession = $null
            }
        }

        if (-not $success) {
            try {
                $script:currentSession = Start-And-Init-Session -Direct $true
                $result = Request-RateLimits $script:currentSession
                $success = $true
            } catch {
                if ($null -ne $script:currentSession) {
                    Stop-CodexSession $script:currentSession
                    $script:currentSession = $null
                }
                if ($DirectOnly) { throw }

                $script:currentSession = Start-And-Init-Session -Direct $false
                $result = Request-RateLimits $script:currentSession
                $success = $true
            }
        }

        if ($result -is [Collections.IDictionary]) {
            $result['failureCount'] = 0
        } else {
            $result | Add-Member -NotePropertyName failureCount -NotePropertyValue 0 -Force
        }
    } catch {
        if ($null -ne $script:currentSession) {
            Stop-CodexSession $script:currentSession
            $script:currentSession = $null
        }
        $result = @{status='unavailable';updatedAt=0;fiveHour=$null;weekly=$null}
        $previousFailures = 0
        if (Test-Path -LiteralPath $outputPath) {
            try {
                $cached = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
                if ($null -ne $cached.failureCount) {
                    $previousFailures = [Math]::Max(0, [int]$cached.failureCount)
                }
                $cached.status = 'stale'
                $result = $cached
            } catch { }
        }
        $nextFailures = [Math]::Min(999, $previousFailures + 1)
        $failStamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($result -is [Collections.IDictionary]) {
            $result['failureCount'] = $nextFailures
            $result['lastFailureAt'] = $failStamp
        } else {
            $result | Add-Member -NotePropertyName failureCount -NotePropertyValue $nextFailures -Force
            $result | Add-Member -NotePropertyName lastFailureAt -NotePropertyValue $failStamp -Force
        }
    }

    $result = Set-UsageContract $result $policy
    $temp = "$outputPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8
        Move-Item -LiteralPath $temp -Destination $outputPath -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
    return $result
}

try {
    if ($Persistent) {
        while ($true) {
            $cmdLine = [Console]::In.ReadLine()
            if ($null -eq $cmdLine) {
                break
            }
            $cmd = $cmdLine.Trim().ToLowerInvariant()
            if ($cmd -eq 'stop' -or $cmd -eq 'exit' -or $cmd -eq 'quit') {
                break
            }
            if ($cmd -eq 'refresh') {
                try {
                    [void](Invoke-UsageRefresh)
                    [Console]::Out.WriteLine('done')
                } catch {
                    [Console]::Out.WriteLine('failed')
                }
                [Console]::Out.Flush()
            }
        }
    } else {
        [void](Invoke-UsageRefresh)
    }
} finally {
    if ($null -ne $script:currentSession) {
        Stop-CodexSession $script:currentSession
        $script:currentSession = $null
    }
}
