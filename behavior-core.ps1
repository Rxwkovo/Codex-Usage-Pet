# Pure pose sampling: all movement is based on elapsed time, not frame count.
function Get-PetPose([string]$Action, [double]$Age, [double]$Duration) {
 $enter = [Math]::Max(0,[Math]::Min(1,$Age/1.1))
 $leave = [Math]::Max(0,[Math]::Min(1,($Duration-$Age)/1.1))
 $blend = [Math]::Min($enter*$enter*(3-2*$enter),$leave*$leave*(3-2*$leave))
 $pose = @{x=0.0;y=0.0;angle=0.0;sx=1.0;sy=1.0;foot=0.0;arm=0.0;sleep=0.0;eye=1.0;progress=0.0}
 switch ($Action) {
  'walk' {
   $pose.y = -[Math]::Abs([Math]::Sin($Age*7))*5*$blend
   $pose.angle = [Math]::Sin($Age*7)*4*$blend
   $pose.foot = [Math]::Sin($Age*7)*24*$blend
   $pose.arm = -[Math]::Sin($Age*7)*13*$blend
   $p = [Math]::Max(0,[Math]::Min(1,$Age/[Math]::Max(0.01,$Duration)))
   $pose.progress = $p*$p*(3-2*$p)
  }
  'sit' {
   $pose.sx = 1+0.09*$blend; $pose.sy = 1-0.22*$blend
   $pose.foot = 27*$blend; $pose.arm = 16*$blend
   $pose.y = [Math]::Sin($Age*1.6)*1.3*$blend
  }
  'sleep' {
   $pose.sx = 1-0.16*$blend; $pose.sy = 1-0.21*$blend
   $pose.angle = 76*$blend; $pose.y = -5*$blend+[Math]::Sin($Age*1.5)*1.2*$blend
   $pose.eye = 1-0.92*$blend; $pose.sleep=$blend; $pose.arm=12*$blend
  }
  'stretch' {
   $pose.sx = 1-0.07*$blend; $pose.sy = 1+0.08*$blend
   $pose.arm = -38*$blend; $pose.eye = 1-0.55*$blend
   $pose.angle = [Math]::Sin($Age*1.5)*3*$blend
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
