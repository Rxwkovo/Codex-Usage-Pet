$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -Path (Join-Path $root 'sprite-player.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
. (Join-Path $root 'sprite-core.ps1')
. (Join-Path $root 'preferences-core.ps1')
function Assert($c,$m){if(-not $c){throw $m}}
$p=Get-DefaultPreferences
$view=New-Object PetSpriteView
$view.Load((Join-Path $root 'assets/flat'))
Assert ($view.FrameCount -eq 56) 'All seven sheets must contain eight frames'
foreach($action in @('walk','sit','sleep','stretch','wave','compact','moods')){
 foreach($frame in 0..7){
  $view.SetFrame($action,$frame,$false,100,0,0,-1,0)
  $pixels=$view.GetPixels()
  Assert ($pixels[3] -eq 0 -and $pixels[$pixels.Length-1] -eq 0) 'Image background corners must be transparent'
  $opaque=0
  for($i=3;$i -lt $pixels.Length;$i+=4){if($pixels[$i] -gt 240){$opaque++};Assert ($pixels[$i-1] -le $pixels[$i] -and $pixels[$i-2] -le $pixels[$i] -and $pixels[$i-3] -le $pixels[$i]) 'Frame must use valid premultiplied alpha'}
  Assert ($opaque -gt 4000) 'Matte processing must preserve the character body'
 }
}
foreach($action in @('sit','sleep')){
 $begin=Get-SpriteSample $action 0 12 140 0 0 'happy' $false $p
 $middle=Get-SpriteSample $action 6 12 140 0 0 'happy' $false $p
 $end=Get-SpriteSample $action 12 12 140 0 0 'happy' $false $p
 Assert ($begin.frame -eq 0 -and $middle.frame -eq 7 -and $end.frame -eq 0) 'Resting actions must enter, hold and return through drawn frames'
}
$compact=Get-SpriteSample 'idle' 0 0 0 0 1 'happy' $false $p
Assert ($compact.key -eq 'compact' -and $compact.frame -eq 7) 'Compact mode must use a tucked drawing'
foreach($mood in @('happy','worried','exhausted')){$s=Get-SpriteSample 'idle' 0 0 0 0 0 $mood $false $p;Assert ($s.key -eq 'moods' -and $s.frame -gt 0) 'Quota must select a drawn expression'}
'PASS: 56 raster frames, transparency, body preservation, premultiplied alpha, transition endpoints, compact pose and quota expressions'
