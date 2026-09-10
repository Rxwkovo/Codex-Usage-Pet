$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -Path (Join-Path $root 'sprite-player.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
Add-Type @'
public static class SpritePixels {
 public static bool Valid(byte[] p){int opaque=0;for(int i=3;i<p.Length;i+=4){if(p[i]>240)opaque++;if(p[i-1]>p[i]||p[i-2]>p[i]||p[i-3]>p[i])return false;}return opaque>4000;}
}
'@
. (Join-Path $root 'sprite-core.ps1')
. (Join-Path $root 'preferences-core.ps1')
function Assert($c,$m){if(-not $c){throw $m}}
$p=Get-DefaultPreferences
$view=New-Object PetSpriteView
$view.Load((Join-Path $root 'assets/flat'))
Assert ($view.FrameCount -eq 72) 'Five eight-frame and two sixteen-frame sheets'
foreach($action in @('walk','sit','sleep','stretch','wave','compact','moods')){
 foreach($frame in 0..($view.GetFrameCount($action)-1)){
  $view.SetFrame($action,$frame,$false,100,0,0,-1,0)
  $pixels=$view.GetPixels()
  Assert ($pixels[3] -eq 0 -and $pixels[$pixels.Length-1] -eq 0) 'Image background corners must be transparent'
  Assert ([SpritePixels]::Valid($pixels)) 'Matte processing must preserve the character body and valid premultiplied alpha'
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
'PASS: 72 raster frames, transparency, body preservation, premultiplied alpha, transition endpoints, compact pose and quota expressions'
