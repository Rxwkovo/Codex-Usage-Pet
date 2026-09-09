$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'behavior-core.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
foreach ($action in @('walk','sit','sleep','stretch')) {
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
Assert ($sit.sy -lt 0.85 -and $sit.foot -gt 20) 'Sitting must lower the body and splay feet'
$previous=0
foreach ($age in 0..8) {
 $p=Get-PetPose 'walk' $age 8
 Assert ($p.progress -ge $previous -and $p.progress -le 1) 'Walk must advance monotonically'
 $previous=$p.progress
}
Assert ((Get-WalkTarget 1620 280 0 1920 1 150) -eq 1470) 'Turn inward near right edge'
Assert ((Get-WalkTarget 10 280 0 1920 -1 150) -eq 160) 'Turn inward near left edge'
Assert ((Get-WalkTarget 0 280 0 280 1 150) -eq 0) 'No movement when screen is too narrow'
'PASS: pose continuity, sleep and sit poses, walking bounds and monotonic movement'
