function Convert-Usage($response) {
 $bucket = $null
 if ($null -ne $response.rateLimitsByLimitId) { $bucket = $response.rateLimitsByLimitId.codex }
 if ($null -eq $bucket -and ($null -eq $response.rateLimits.limitId -or $response.rateLimits.limitId -eq 'codex')) { $bucket = $response.rateLimits }
 $result = @{fiveHour=$null;weekly=$null;updatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();status='ok'}
 $windows=@()
 foreach ($w in @($bucket.primary,$bucket.secondary)) {
  if ($null -eq $w -or $null -eq $w.usedPercent) { continue }
  $value = @{remaining=[Math]::Max(0.0,[Math]::Min(100.0,100-[double]$w.usedPercent));resetsAt=$w.resetsAt}
  if ($w.windowDurationMins -eq 300) { $result.fiveHour=$value }
  if ($w.windowDurationMins -eq 10080) { $result.weekly=$value }
  $windows+=@{mins=[double]$w.windowDurationMins;value=$value}
 }
 # The service is free to rename its windows. If neither documented length came back,
 # keep working by treating the shorter window as the short one instead of reporting
 # "unknown" forever with no trace. Only ordered when both are present, so a genuinely
 # missing window still reads as unknown (covered by usage.tests.ps1).
 if ($null -eq $result.fiveHour -and $null -eq $result.weekly -and $windows.Count -ge 2) {
  $ordered=$windows | Sort-Object { $_.mins }
  $result.fiveHour=$ordered[0].value
  $result.weekly=$ordered[-1].value
  # Written to usage.json so an unrecognised window length is diagnosable.
  $result.unmappedDurationMins=@($ordered | ForEach-Object { $_.mins })
 }
 return $result
}

function Get-UsageMood($Data,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(),[double]$StaleSeconds=120,[double]$HappyThreshold=50,[double]$WorriedThreshold=20) {
 $unknown=@{name='unknown';remaining=$null;limiting=$null}
 if ($null -eq $Data -or $Data.status -ne 'ok' -or $null -eq $Data.updatedAt -or $Now-$Data.updatedAt -ge $StaleSeconds -or $Data.updatedAt -gt $Now+5) { return $unknown }
 $lowest=101.0; $limiting=$null
 foreach ($key in @('fiveHour','weekly')) {
  $window=$Data.$key
  if ($null -eq $window -or $null -eq $window.remaining) { return $unknown }
  if ($null -ne $window.resetsAt -and $window.resetsAt -le $Now) { return $unknown }
  $r=[double]$window.remaining
  if ([double]::IsNaN($r) -or [double]::IsInfinity($r) -or $r -lt 0 -or $r -gt 100) { return $unknown }
  if ($r -lt $lowest) { $lowest=$r; $limiting=$key }
 }
 $name=if ($lowest -le 0) {'exhausted'} elseif ($lowest -le $WorriedThreshold) {'worried'} elseif ($lowest -ge $HappyThreshold) {'happy'} else {'calm'}
 return @{name=$name;remaining=$lowest;limiting=$limiting}
}

# A quota worker that outlives this is wedged, not slow: read-usage.ps1 gives up after
# 12 seconds directly and 25 seconds through the Codex proxy, so a worker still alive at
# 90 seconds is ignoring its own timeouts. Refresh-Usage in pet.ps1 uses this to reap it
# and start a fresh one - without it, one wedged worker silenced quota refresh for the
# rest of the session, because the refresh guard only ever asked "is it still running?".
function Test-UsageWorkerStale([DateTime]$StartedAt,[DateTime]$Now,[double]$TimeoutSeconds=90.0) {
 # An unset stamp (MinValue) means "not recorded yet", the same convention
 # Get-MobileStatus uses for its startup deadline: never reap on a missing stamp.
 $ageSeconds=if ($StartedAt -eq [DateTime]::MinValue) { 0.0 } else { ($Now-$StartedAt).TotalSeconds }
 return $ageSeconds -ge $TimeoutSeconds
}
