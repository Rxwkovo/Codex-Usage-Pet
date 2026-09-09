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
$cached=Sample 0 0; $cached.status='stale'; Assert-Mood $cached unknown
$missing=Sample 90 80; $missing.weekly=$null; Assert-Mood $missing unknown
$expired=Sample 0 80; $expired.fiveHour.resetsAt=1000; Assert-Mood $expired unknown
Assert-Mood $null unknown
Assert-Mood (Sample -5 80) unknown
$tight=Get-UsageMood (Sample 80 5) 1000
if ($tight.limiting -ne 'weekly') { throw 'Weekly must control expression when tighter' }
Assert-Mood (Sample 90 80) happy
'PASS: mood thresholds, limiting window, recovery, expired and unavailable data'
