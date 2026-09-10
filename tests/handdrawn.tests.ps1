$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -Path (Join-Path $root 'sprite-player.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
Add-Type @'
public static class RasterCheck {
 public static bool Valid(byte[] p){int opaque=0;for(int i=3;i<p.Length;i+=4){if(p[i]>240)opaque++;if(p[i-1]>p[i]||p[i-2]>p[i]||p[i-3]>p[i])return false;}return opaque>4000&&p[3]==0&&p[p.Length-1]==0;}
 public static bool SameAlpha(byte[] a,byte[] b){for(int i=3;i<a.Length;i+=4)if(a[i]!=b[i])return false;return true;}
 public static double PanelFraction(bool[] mask,byte[] p){int face=0,body=0;for(int i=0;i<mask.Length;i++){if(mask[i])face++;if(p[i*4+3]>240)body++;}return (double)face/body;}
}
'@
. (Join-Path $root 'sprite-core.ps1')
. (Join-Path $root 'preferences-core.ps1')
function Assert($c,$m){if(-not $c){throw $m}}
$p=Get-DefaultPreferences
$view=New-Object PetSpriteView
$view.Load((Join-Path $root 'assets/flat'))
Assert ($view.PixelWidth -eq 440 -and $view.PixelHeight -eq 420) 'High-resolution backing must preserve the logical display size'
$flags=[Reflection.BindingFlags]'NonPublic,Instance'
$regions=$view.GetType().GetField('screens',$flags).GetValue($view)
Assert ($view.FrameCount -eq 72) 'Expected 72 full-body raster cels'
$count=0
foreach($action in @('walk','sit','sleep','stretch','wave','compact','moods')){
 $expected=if($action -in @('stretch','wave')){16}else{8}
 Assert ($view.GetFrameCount($action) -eq $expected) "Wrong frame count: $action"
 foreach($frame in 0..($expected-1)){
  $alpha=$null;$hashes=New-Object 'System.Collections.Generic.HashSet[string]'
  foreach($mood in 0..3){foreach($closed in @($false,$true)){
   $view.SetExpression($mood,$closed);$view.SetFrame($action,$frame,$false,100,0,0,-1,0)
   $pixels=$view.GetPixels();Assert ([RasterCheck]::Valid($pixels)) "Invalid raster: $action/$frame/$mood/$closed"
   Assert ([RasterCheck]::PanelFraction($regions[$action][$frame].mask,$pixels) -lt 0.55) "Face detection included body outlines: $action/$frame"
   if($null -eq $alpha){$alpha=$pixels}else{Assert ([RasterCheck]::SameAlpha($alpha,$pixels)) 'Expressions must preserve the full-body silhouette'}
   [void]$hashes.Add([Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($pixels)))
   $count++
  }}
  Assert ($hashes.Count -ge 4) 'Every action cel must display four distinct quota moods'
 }
}
foreach($action in @('wave','stretch')){
 $s=Get-SpriteSample $action 12 12 140 0 0 'happy' $false $p
 Assert ($s.frame -eq 15) 'The complete 16-frame gesture must play'
}
"PASS: $count action/frame/expression combinations, transparency, silhouette preservation, quota moods and full gesture timelines"
