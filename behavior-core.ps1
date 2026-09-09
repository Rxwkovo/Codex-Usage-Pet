# Pure pose sampling: all movement is based on elapsed time, not frame count.
function Get-PetPose([string]$Action, [double]$Age, [double]$Duration, [double]$Distance=140.0) {
 $enter = [Math]::Max(0.0,[Math]::Min(1.0,$Age/1.1))
 $leave = [Math]::Max(0.0,[Math]::Min(1.0,($Duration-$Age)/1.1))
 $blend = [Math]::Min($enter*$enter*(3-2*$enter),$leave*$leave*(3-2*$leave))
 $pose = @{x=0.0;y=0.0;angle=0.0;sx=1.0;sy=1.0;foot=0.0;arm=0.0;sleep=0.0;eye=1.0;progress=0.0;sit=0.0;sitFeet=0.0;sitHands=0.0;ground=0.0;leftStep=0.0;rightStep=0.0;wave=0.0}
 switch ($Action) {
  'walk' {
   $p = [Math]::Max(0.0,[Math]::Min(1.0,$Age/[Math]::Max(0.01,$Duration)))
   $pose.progress = $p*$p*(3-2*$p)
   # The stride follows distance travelled, including the ease-in/ease-out.
   $stride=[Math]::Sin($pose.progress*[Math]::Abs($Distance)/26.0*[Math]::PI*2)
   $pose.y=-[Math]::Abs($stride)*3.2*$blend
   $pose.angle=$stride*2.5*$blend
   $pose.foot=$stride*20*$blend; $pose.arm=-$stride*12*$blend
   $pose.leftStep=-[Math]::Max(0.0,$stride)*5*$blend
   $pose.rightStep=-[Math]::Max(0.0,-$stride)*5*$blend
  }
  'sit' {
   # Feet reach forward before the body settles; hands lower just afterwards.
   # Keep the head/face proportions intact instead of flattening the sprite.
   $phase=[Math]::Max(0.0,[Math]::Min($Age,$Duration-$Age))
   $bodyT=[Math]::Max(0.0,[Math]::Min(1.0,($phase-0.12)/1.15))
   $feetT=[Math]::Max(0.0,[Math]::Min(1.0,$phase/0.8))
   $handT=[Math]::Max(0.0,[Math]::Min(1.0,($phase-0.22)/0.9))
   $seat=$bodyT*$bodyT*(3-2*$bodyT)
   $pose.sit=$seat
   $pose.sitFeet=$feetT*$feetT*(3-2*$feetT)
   $pose.sitHands=$handT*$handT*(3-2*$handT)
   $pose.sx=1+0.015*$seat; $pose.sy=1-0.015*$seat
   $settle=0.0
   if ($Age -gt 1.1 -and $Age -lt 2.1) { $settle=[Math]::Sin(($Age-1.1)*[Math]::PI)*1.5 }
   $pose.y=12*$seat+$settle+([Math]::Sin($Age*1.5)*0.6*$seat)
   $pose.ground=12*$seat
   $pose.eye=1-0.08*$seat
  }
  'sleep' {
   $pose.sx = 1-0.16*$blend; $pose.sy = 1-0.21*$blend
   $pose.angle = 76*$blend; $pose.y = -5*$blend+[Math]::Sin($Age*1.5)*1.2*$blend
   $pose.eye = 1-0.92*$blend; $pose.sleep=$blend; $pose.arm=12*$blend
   $pose.sitHands=$blend; $pose.sitFeet=$blend
  }
  'stretch' {
   $pose.sx = 1-0.07*$blend; $pose.sy = 1+0.08*$blend
   $pose.arm = -38*$blend; $pose.eye = 1-0.55*$blend
   $pose.angle = [Math]::Sin($Age*1.5)*3*$blend
  }
  'wave' {
   $pose.wave=(-32+[Math]::Sin($Age*9)*15)*$blend
   $pose.angle=-3*$blend; $pose.y=-[Math]::Abs([Math]::Sin($Age*3))*1.5*$blend
  }
 }
 return $pose
}

function Get-WalkTarget([double]$Left,[double]$Width,[double]$AreaLeft,[double]$AreaRight,[int]$Direction,[double]$Distance) {
 $right = [Math]::Max($AreaLeft,$AreaRight-$Width)
 $target = $Left+$Direction*$Distance
 if ($target -lt $AreaLeft -or $target -gt $right) { $target=$Left-$Direction*$Distance }
 return [Math]::Max($AreaLeft,[Math]::Min($right,$target))
}
