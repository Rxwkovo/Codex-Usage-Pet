function Convert-Usage($response) {
 $bucket = $null
 if ($null -ne $response.rateLimitsByLimitId) { $bucket = $response.rateLimitsByLimitId.codex }
 if ($null -eq $bucket -and ($null -eq $response.rateLimits.limitId -or $response.rateLimits.limitId -eq 'codex')) { $bucket = $response.rateLimits }
 $result = @{fiveHour=$null;weekly=$null;updatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();status='ok'}
 foreach ($w in @($bucket.primary,$bucket.secondary)) {
  if ($null -eq $w -or $null -eq $w.usedPercent) { continue }
  $value = @{remaining=[Math]::Max(0,[Math]::Min(100,100-[double]$w.usedPercent));resetsAt=$w.resetsAt}
  if ($w.windowDurationMins -eq 300) { $result.fiveHour=$value }
  if ($w.windowDurationMins -eq 10080) { $result.weekly=$value }
 }
 return $result
}
