$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'behavior-core.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
foreach ($action in @('walk','sit','sleep','stretch','wave')) {
 foreach ($age in @(0,0.1,1.1,3,8.9,10)) {
  $p=Get-PetPose $action $age 10
  foreach ($value in $p.Values) { Assert (-not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)) 'Pose must be finite' }
  Assert ($p.sx -gt 0 -and $p.sy -gt 0) 'Pose must not invert'
 }
 foreach ($age in @(0,10)) {
  $p=Get-PetPose $action $age 10
  Assert ($p.sx -eq 1 -and $p.sy -eq 1 -and $p.angle -eq 0 -and $p.eye -eq 1) 'Actions must start and finish standing'
 }
}
$sleep=Get-PetPose 'sleep' 4 18
Assert ($sleep.angle -gt 60 -and $sleep.eye -lt 0.2 -and $sleep.sleep -gt 0.9) 'Sleeping must lie down and close eyes'
$sit=Get-PetPose 'sit' 4 12
Assert ($sit.sy -ge 0.97 -and $sit.y -gt 10 -and $sit.sitFeet -gt 0.9 -and $sit.sitHands -gt 0.9) 'Sitting must lower an intact body and use dedicated forward feet and relaxed hands'
$earlySit=Get-PetPose 'sit' 0.45 12
Assert ($earlySit.sitFeet -gt $earlySit.sit -and $earlySit.sitFeet -gt $earlySit.sitHands) 'Feet should reach before the body settles and hands relax'
foreach ($age in @(0,12)) {
 $p=Get-PetPose 'sit' $age 12
 Assert ($p.sitFeet -eq 0 -and $p.sitHands -eq 0 -and $p.ground -eq 0) 'Standing endpoints must not retain sitting layers'
}
$movingAtOneSecond=Get-PetPose 'walk' 1 8
Assert ($movingAtOneSecond.progress -gt 0.01 -and $movingAtOneSecond.progress -lt 0.1) 'Walking should already travel during the first second'
$halfBlend=Get-PetPose 'sleep' 0.5 12
Assert ($halfBlend.angle -gt 1 -and $halfBlend.angle -lt 60) 'Pose blending must preserve fractional progress'
$previous=0
$distinctPositions=@{}
foreach ($frame in 0..240) {
 $age=$frame/30.0
 $p=Get-PetPose 'walk' $age 8
 Assert ($p.progress -ge $previous -and $p.progress -le 1) 'Walk must advance monotonically'
 Assert (($p.progress-$previous) -le 0.007) 'Walk must not jump between desktop positions'
 $distinctPositions[[string]$p.progress]=$true
 $previous=$p.progress
}
Assert ($distinctPositions.Count -gt 230) 'Walking requires continuously changing positions, not in-place steps'
Assert ((Get-WalkTarget 1620 280 0 1920 1 150) -eq 1470) 'Turn inward near right edge'
Assert ((Get-WalkTarget 10 280 0 1920 -1 150) -eq 160) 'Turn inward near left edge'
Assert ((Get-WalkTarget 0 280 0 280 1 150) -eq 0) 'No movement when screen is too narrow'
'PASS: pose continuity, sleep and sit poses, walking bounds and monotonic movement'
