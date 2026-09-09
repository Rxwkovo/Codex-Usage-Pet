$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'usage-core.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$normal = Convert-Usage ([pscustomobject]@{rateLimits=@{primary=@{windowDurationMins=300;usedPercent=25;resetsAt=123};secondary=@{windowDurationMins=10080;usedPercent=90;resetsAt=456}}})
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
'PASS: 8 usage assertions'
