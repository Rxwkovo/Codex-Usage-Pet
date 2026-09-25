function Get-PolicyValue($Source,[string[]]$Names,$Default) {
 if($null -eq $Source){return $Default}
 foreach($name in $Names) {
  if($Source -is [Collections.IDictionary] -and $Source.Contains($name)){return $Source[$name]}
  $property=$Source.PSObject.Properties[$name]
  if($null -ne $property){return $property.Value}
 }
 return $Default
}
function ConvertTo-PolicyNumber($Value,[string]$Name) {
 if($Value -is [bool] -or $Value -is [string]){throw "$Name must be a finite number"}
 $number=0.0
 $text=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
 if(-not [double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)){throw "$Name must be a finite number"}
 return $number
}
function Get-UsagePolicy($Preferences=$null) {
 $policy=@{
  refreshSeconds=60
  staleSeconds=120
  clockSkewToleranceSeconds=5
  happyMinRemaining=50
  worriedMaxRemaining=20
  exhaustedMaxRemaining=0
 }
 if($null -ne $Preferences) {
  $policy.refreshSeconds=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('refreshSeconds') 60) 'refreshSeconds'
  $policy.staleSeconds=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('staleSeconds') 120) 'staleSeconds'
  $policy.clockSkewToleranceSeconds=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('clockSkewToleranceSeconds') 5) 'clockSkewToleranceSeconds'
  $policy.happyMinRemaining=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('happyMinRemaining','happyThreshold') 50) 'happyMinRemaining'
  $policy.worriedMaxRemaining=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('worriedMaxRemaining','worriedThreshold') 20) 'worriedMaxRemaining'
  $policy.exhaustedMaxRemaining=ConvertTo-PolicyNumber (Get-PolicyValue $Preferences @('exhaustedMaxRemaining') 0) 'exhaustedMaxRemaining'
 }
 if($policy.refreshSeconds -lt 30 -or $policy.refreshSeconds -gt 600){throw 'refreshSeconds is out of range (30..600)'}
 if($policy.staleSeconds -lt 60 -or $policy.staleSeconds -gt 3600 -or $policy.staleSeconds -lt $policy.refreshSeconds+30){throw 'staleSeconds is out of range or below refreshSeconds+30'}
 if($policy.clockSkewToleranceSeconds -ne 5){throw 'clockSkewToleranceSeconds must equal 5'}
 if($policy.happyMinRemaining -lt 1 -or $policy.happyMinRemaining -gt 100){throw 'happyMinRemaining is out of range (1..100)'}
 if($policy.worriedMaxRemaining -lt 0 -or $policy.worriedMaxRemaining -gt 99 -or $policy.worriedMaxRemaining -ge $policy.happyMinRemaining){throw 'worriedMaxRemaining is invalid'}
 if($policy.exhaustedMaxRemaining -ne 0){throw 'exhaustedMaxRemaining must equal 0'}
 return $policy
}

function Set-UsageContract($Data,$Policy=$null) {
 if ($null -eq $Data) { return $Data }
 $policy=Get-UsagePolicy $Policy
 if ($Data -is [Collections.IDictionary]) {
  $Data['protocolVersion']=2
  $Data['policy']=$policy
 } else {
  $Data | Add-Member -NotePropertyName protocolVersion -NotePropertyValue 2 -Force
  $Data | Add-Member -NotePropertyName policy -NotePropertyValue $policy -Force
 }
 return $Data
}

function Convert-Usage($response,$Policy=$null) {
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
 return (Set-UsageContract $result $Policy)
}

function ConvertTo-UsageNumber($Value,[switch]$Integer) {
 if($null -eq $Value -or $Value -is [bool] -or $Value -is [string]){return $null}
 $number=0.0
 $text=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
 if(-not [double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)){return $null}
 if($Integer -and [Math]::Truncate($number) -ne $number){return $null}
 return $number
}

function Get-UsageMood($Data,[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(),[double]$StaleSeconds=120,[double]$HappyThreshold=50,[double]$WorriedThreshold=20,$Policy=$null) {
 $unknown=@{name='unknown';remaining=$null;limiting=$null}
 $effective=if($null -ne $Policy){Get-UsagePolicy $Policy}else{Get-UsagePolicy @{refreshSeconds=60;staleSeconds=$StaleSeconds;happyThreshold=$HappyThreshold;worriedThreshold=$WorriedThreshold}}
 $stamp=if($null -eq $Data){$null}else{ConvertTo-UsageNumber $Data.updatedAt -Integer}
 if ($null -eq $Data -or $Data.status -ne 'ok' -or $null -eq $stamp -or $Now-$stamp -ge $effective.staleSeconds -or $stamp -gt $Now+$effective.clockSkewToleranceSeconds) { return $unknown }
 $lowest=101.0; $limiting=$null
 foreach ($key in @('fiveHour','weekly')) {
  $window=$Data.$key
  if ($null -eq $window -or $null -eq $window.remaining) { return $unknown }
  $reset=ConvertTo-UsageNumber $window.resetsAt -Integer
  $r=ConvertTo-UsageNumber $window.remaining
  if ($null -eq $reset -or $reset -le $Now -or $null -eq $r -or $r -lt 0 -or $r -gt 100) { return $unknown }
  if ($r -lt $lowest) { $lowest=$r; $limiting=$key }
 }
 $name=if ($lowest -le $effective.exhaustedMaxRemaining) {'exhausted'} elseif ($lowest -le $effective.worriedMaxRemaining) {'worried'} elseif ($lowest -ge $effective.happyMinRemaining) {'happy'} else {'calm'}
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
