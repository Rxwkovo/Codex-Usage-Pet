function Convert-Usage($response) {
 $bucket = $null
 if ($null -ne $response.rateLimitsByLimitId) { $bucket = $response.rateLimitsByLimitId.codex }
 if ($null -eq $bucket -and ($null -eq $response.rateLimits.limitId -or $response.rateLimits.limitId -eq 'codex')) { $bucket = $response.rateLimits }
 $result = @{fiveHour=$null;weekly=$null;updatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();status='ok'}
 foreach ($w in @($bucket.primary,$bucket.secondary)) {
  if ($null -eq $w -or $null -eq $w.usedPercent) { continue }
  $value = @{remaining=[Math]::Max(0.0,[Math]::Min(100.0,100-[double]$w.usedPercent));resetsAt=$w.resetsAt}
  if ($w.windowDurationMins -eq 300) { $result.fiveHour=$value }
  if ($w.windowDurationMins -eq 10080) { $result.weekly=$value }
 }
 return $result
}

function Get-UsageMood($Data,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
 $unknown=@{name='unknown';remaining=$null;limiting=$null}
 if ($null -eq $Data -or $Data.status -ne 'ok' -or $null -eq $Data.updatedAt -or $Now-$Data.updatedAt -ge 120 -or $Data.updatedAt -gt $Now+5) { return $unknown }
 $lowest=101.0; $limiting=$null
 foreach ($key in @('fiveHour','weekly')) {
  $window=$Data.$key
  if ($null -eq $window -or $null -eq $window.remaining) { return $unknown }
  if ($null -ne $window.resetsAt -and $window.resetsAt -le $Now) { return $unknown }
  $r=[double]$window.remaining
  if ([double]::IsNaN($r) -or [double]::IsInfinity($r) -or $r -lt 0 -or $r -gt 100) { return $unknown }
  if ($r -lt $lowest) { $lowest=$r; $limiting=$key }
 }
 $name=if ($lowest -le 0) {'exhausted'} elseif ($lowest -le 20) {'worried'} elseif ($lowest -ge 50) {'happy'} else {'calm'}
 return @{name=$name;remaining=$lowest;limiting=$limiting}
}
