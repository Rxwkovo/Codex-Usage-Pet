$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'preferences-core.ps1')
. (Join-Path (Split-Path $PSScriptRoot) 'behavior-core.ps1')
function Assert($c,$m){if(-not $c){throw $m}}
$p=Get-DefaultPreferences
Assert ($null -eq (Test-Preferences $p)) 'Defaults must validate'
Assert ($p.actionMin -eq 60 -and $p.actionMax -eq 120) 'Default random activity must be 1-2 minutes apart'
foreach($value in @('NaN','Infinity','hello',0,3601)) {$bad=$p.Clone(); $bad.actionMin=$value; Assert ($null -ne (Test-Preferences $bad)) 'Invalid input must be rejected'}
$bad=$p.Clone(); $bad.actionMin=300; Assert ($null -ne (Test-Preferences $bad)) 'Reversed range must fail'
$text=$p.Clone(); $text.happyThreshold='100'; $text.worriedThreshold='20'; Assert ($null -eq (Test-Preferences $text)) 'Form inputs must compare numerically'
$bad=$p.Clone(); $bad.refreshSeconds=180; Assert ($null -ne (Test-Preferences $bad)) 'Refresh and expiry cannot conflict'
foreach($a in @('walk','sit','sleep','stretch','wave')) {$p[$a+'Weight']=0}; $p.waveWeight=1
foreach($n in 1..30) {Assert ((Get-WeightedAction $p 'wave') -eq 'wave') 'A single enabled action must work even if repeated'}
$p.waveWeight=0; Assert ($null -ne (Test-Preferences $p)) 'All-zero weights must fail'
$from=Get-PetPose 'sleep' 4 18
$to=Get-PetPose 'idle' 0 0
$start=Merge-PetPose $from $to 0; $end=Merge-PetPose $from $to 1
foreach($key in $from.Keys) {if($key -ne 'progress'){Assert ([Math]::Abs($start[$key]-$from[$key]) -lt 0.00001) 'Interruption must preserve current pose'; Assert ([Math]::Abs($end[$key]-$to[$key]) -lt 0.00001) 'Transition must reach target'}}
$previous=$from.angle
foreach($frame in 0..60){$pose=Merge-PetPose $from $to ($frame/60.0); Assert ([Math]::Abs($pose.angle-$previous) -lt 2.5) 'Interrupted sleep must not snap upright'; $previous=$pose.angle}
foreach($n in 1..100){$r=Get-RandomRange 60 120; Assert ($r -ge 60 -and $r -le 120) 'Scheduling must respect configured range'}
'PASS: defaults, numeric validation, range and expiry checks, disabled actions, interruption blending and scheduling'
