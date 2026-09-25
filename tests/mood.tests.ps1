$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'usage-core.ps1')
function Sample($a,$b) { return @{status='ok';updatedAt=1000;fiveHour=@{remaining=$a;resetsAt=3000};weekly=@{remaining=$b;resetsAt=5000}} }
function Assert-Mood($data,$expected,[long]$now=1000) {
 $actual=Get-UsageMood $data $now
 if ($actual.name -ne $expected) { throw "Expected $expected, got $($actual.name)" }
}
Assert-Mood (Sample 90 70) happy
Assert-Mood (Sample 50 50) happy
Assert-Mood (Sample 49.9 80) calm
Assert-Mood (Sample 20.1 90) calm
Assert-Mood (Sample 20 80) worried
Assert-Mood (Sample 100 0.1) worried
Assert-Mood (Sample 0 90) exhausted
Assert-Mood (Sample 90 0) exhausted
Assert-Mood (Sample 90 80) unknown 1120
Assert-Mood (Sample 90 80) happy 1119
$futureEdge=Sample 90 80; $futureEdge.updatedAt=1005; Assert-Mood $futureEdge happy 1000
$futureBad=Sample 90 80; $futureBad.updatedAt=1006; Assert-Mood $futureBad unknown 1000
$cached=Sample 0 0; $cached.status='stale'; Assert-Mood $cached unknown
$missing=Sample 90 80; $missing.weekly=$null; Assert-Mood $missing unknown
$expired=Sample 0 80; $expired.fiveHour.resetsAt=1000; Assert-Mood $expired unknown
$missingReset=Sample 90 80; $missingReset.fiveHour.Remove('resetsAt'); Assert-Mood $missingReset unknown
$stringReset=Sample 90 80; $stringReset.fiveHour.resetsAt='3000'; Assert-Mood $stringReset unknown
$stringRemaining=Sample 90 80; $stringRemaining.weekly.remaining='80'; Assert-Mood $stringRemaining unknown
$stringStamp=Sample 90 80; $stringStamp.updatedAt='1000'; Assert-Mood $stringStamp unknown
$fractionalReset=Sample 90 80; $fractionalReset.fiveHour.resetsAt=3000.5; Assert-Mood $fractionalReset unknown
Assert-Mood $null unknown
Assert-Mood (Sample -5 80) unknown
$custom=Get-UsagePolicy @{refreshSeconds=300;staleSeconds=360;happyThreshold=80;worriedThreshold=20}
$customSample=Sample 60 60
$customMood=Get-UsageMood $customSample 1180 -Policy $custom
if($customMood.name -ne 'calm'){throw 'Validated 300/360/80/20 desktop settings must produce calm at age 180'}
$defaultMood=Get-UsageMood $customSample 1180
if($defaultMood.name -ne 'unknown'){throw 'The same age-180 snapshot must be stale under defaults'}
$customSample.policy=@{staleSeconds=999999;happyMinRemaining=1}
if((Get-UsageMood $customSample 1180 -Policy $custom).name -ne 'calm'){throw 'Snapshot policy must not override validated desktop settings'}
$tight=Get-UsageMood (Sample 80 5) 1000
if ($tight.limiting -ne 'weekly') { throw 'Weekly must control expression when tighter' }
Assert-Mood (Sample 90 80) happy
'PASS: mood thresholds, validated custom policy, strict time fields and unavailable data'
