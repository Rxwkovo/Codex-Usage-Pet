$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'usage-core.ps1')
. (Join-Path (Split-Path $PSScriptRoot) 'preferences-core.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$normal = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=300;usedPercent=25;resetsAt=123};secondary=@{windowDurationMins=10080;usedPercent=90;resetsAt=456}}})
Assert ($normal.protocolVersion -eq 2) 'Desktop quota output uses protocol v2'
Assert ($normal.policy.refreshSeconds -eq 60 -and $normal.policy.staleSeconds -eq 120) 'Desktop quota output carries the shared validity policy'
Assert ($normal.policy.clockSkewToleranceSeconds -eq 5) 'Desktop quota output carries the clock-skew tolerance'
Assert ($normal.policy.happyMinRemaining -eq 50 -and $normal.policy.worriedMaxRemaining -eq 20 -and $normal.policy.exhaustedMaxRemaining -eq 0) 'Desktop quota output carries the shared mood thresholds'
$preferences=Get-DefaultPreferences
$preferences.refreshSeconds=300; $preferences.staleSeconds=360; $preferences.happyThreshold=80; $preferences.worriedThreshold=20
Assert ($null -eq (Test-Preferences $preferences)) 'The real settings schema accepts the custom quota policy'
$customPolicy=Get-UsagePolicy $preferences
$custom=Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=300;usedPercent=40;resetsAt=3000};secondary=@{windowDurationMins=10080;usedPercent=40;resetsAt=5000}}}) $customPolicy
Assert ($custom.policy.refreshSeconds -eq 300 -and $custom.policy.staleSeconds -eq 360) 'Validated refresh and stale settings enter the published contract'
Assert ($custom.policy.happyMinRemaining -eq 80 -and $custom.policy.worriedMaxRemaining -eq 20) 'Validated mood settings enter the published contract'
$fractionalPreferences=$preferences.Clone();$fractionalPreferences.refreshSeconds=300.5;$fractionalPreferences.staleSeconds=360.5
Assert ($null -eq (Test-Preferences $fractionalPreferences)) 'Existing fractional-second settings remain valid'
$fractionalPolicy=Get-UsagePolicy $fractionalPreferences
Assert ($fractionalPolicy.refreshSeconds -eq 300.5 -and $fractionalPolicy.staleSeconds -eq 360.5) 'Fractional timing settings must not be rounded or replaced by defaults'
$badPolicy=$false; try {[void](Get-UsagePolicy @{refreshSeconds=300;staleSeconds=329;happyThreshold=80;worriedThreshold=20})} catch {$badPolicy=$true}
Assert $badPolicy 'Invalid policy relationships must be rejected before publishing'
Assert ($normal.fiveHour.remaining -eq 75) 'Five-hour remaining conversion'
Assert ($normal.weekly.remaining -eq 10) 'Weekly remaining conversion'
$swapped = Convert-Usage ([pscustomobject]@{rateLimitsByLimitId=@{codex=@{secondary=@{windowDurationMins=300;usedPercent=120};primary=@{windowDurationMins=10080;usedPercent=-5}}};rateLimits=@{primary=@{windowDurationMins=300;usedPercent=50}}})
Assert ($swapped.fiveHour.remaining -eq 0) 'Bucket precedence, duration mapping, upper clamp'
Assert ($swapped.weekly.remaining -eq 100) 'Lower clamp'
$missing = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=10080;usedPercent=0}}})
Assert ($null -eq $missing.fiveHour) 'Absent window must remain unknown'
Assert ($missing.weekly.remaining -eq 100) 'Zero usage is valid'
$nullValue = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=300;usedPercent=$null}}})
Assert ($null -eq $nullValue.fiveHour) 'Null usage must remain unknown'
$other = Convert-Usage ([pscustomobject]@{rateLimits=@{limitId='other';primary=@{windowDurationMins=300;usedPercent=20}}})
Assert ($null -eq $other.fiveHour) 'Do not substitute another bucket'
# The service is free to rename its windows. Unknown lengths must fall back to
# shorter=5h / longer=weekly instead of reporting "unknown" forever with no trace,
# and a single unrecognised window must still stay unknown rather than be guessed.
$renamed = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=120;usedPercent=10;resetsAt=700};secondary=@{windowDurationMins=20160;usedPercent=40;resetsAt=800}}})
Assert ($renamed.fiveHour.remaining -eq 90) 'Unknown shorter window becomes the five-hour slot'
Assert ($renamed.weekly.remaining -eq 60) 'Unknown longer window becomes the weekly slot'
Assert (($renamed.unmappedDurationMins -join ',') -eq '120,20160') 'Unmapped lengths must be recorded for diagnosis'
$oneUnknown = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=777;usedPercent=10;resetsAt=700}}})
Assert ($null -eq $oneUnknown.fiveHour -and $null -eq $oneUnknown.weekly) 'A single unknown window must remain unknown'
$knownOnly = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=300;usedPercent=10;resetsAt=700}}})
Assert ($knownOnly.fiveHour.remaining -eq 90) 'A recognised length still maps on its own'
Assert ($null -eq $knownOnly.weekly -and $null -eq $knownOnly.unmappedDurationMins) 'A recognised length must not trigger the fallback'
# The wedged-worker watchdog. Refresh-Usage used to ask only "is the worker still
# running?", so a worker that ignored its own 12s/25s timeouts silenced quota refresh
# for the rest of the session. Test-UsageWorkerStale is the decision pet.ps1 now
# consults, and it has to draw the line where the worker's own timeouts already gave up.
$t0=[DateTime]::UtcNow
Assert (-not (Test-UsageWorkerStale $t0 $t0)) 'A worker that just started is not stale'
Assert (-not (Test-UsageWorkerStale $t0 $t0.AddSeconds(89))) 'A slow but living worker must be left alone'
Assert (Test-UsageWorkerStale $t0 $t0.AddSeconds(90)) 'The watchdog fires at its own deadline'
Assert (Test-UsageWorkerStale $t0 $t0.AddSeconds(91)) 'A wedged worker must be reaped'
Assert (-not (Test-UsageWorkerStale $t0 $t0.AddSeconds(-30))) 'A backwards clock must not reap a fresh worker'
Assert (-not (Test-UsageWorkerStale ([DateTime]::MinValue) $t0)) 'An unset stamp means not recorded, not stale'
Assert (Test-UsageWorkerStale $t0 $t0.AddSeconds(12) 12.0) 'The deadline must be a parameter'
'PASS: usage conversion, protocol v2 policy and worker watchdog'
