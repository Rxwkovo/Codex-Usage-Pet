function Get-SpriteSample([string]$Action,[double]$Age,[double]$Duration,[double]$Distance,[double]$Progress,[double]$Compact,[string]$Mood,[bool]$Left,$Preferences) {
 $sample=@{key='moods';frame=0.0;mirror=$false;alternate=-1;mix=0.0}
 if($Compact -gt 0.001 -and $Action -eq 'idle'){$sample.key='compact';$sample.frame=7*$Compact;return $sample}
 switch($Action){
  'walk' {$sample.key='walk';$sample.frame=(($Progress*$Distance/$Preferences.strideLength)*8)%8; if($sample.frame -gt 7){$sample.frame=7};$sample.mirror=$Left}
  {$_ -in @('sit','sleep')} {$sample.key=$Action;$phase=[Math]::Max(0.0,[Math]::Min(1.0,[Math]::Min($Age,$Duration-$Age)/[Math]::Min($Preferences.poseEase,$Duration/2)));$sample.frame=7*$phase*$phase*(3-2*$phase)}
  {$_ -in @('stretch','wave')} {$sample.key=$Action;$sample.frame=7*[Math]::Max(0.0,[Math]::Min(1.0,$Age/[Math]::Max(0.1,$Duration)))}
  default {$sample.frame=switch($Mood){'happy'{1.0}'worried'{2.0}'exhausted'{3.0}default{0.0}}}
 }
 return $sample
}
