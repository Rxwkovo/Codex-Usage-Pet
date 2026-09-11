$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -Path (Join-Path $root 'sprite-player.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
Add-Type @'
public static class RasterCheck {
 public static bool Valid(byte[] p){int opaque=0;for(int i=3;i<p.Length;i+=4){if(p[i]>240)opaque++;if(p[i-1]>p[i]||p[i-2]>p[i]||p[i-3]>p[i])return false;}return opaque>4000&&p[3]==0&&p[p.Length-1]==0;}
 public static bool SameAlpha(byte[] a,byte[] b){for(int i=3;i<a.Length;i+=4)if(a[i]!=b[i])return false;return true;}
 public static double PanelFraction(bool[] mask,byte[] p){int face=0,body=0;for(int i=0;i<mask.Length;i++){if(mask[i])face++;if(p[i*4+3]>240)body++;}return (double)face/body;}
 public static double ChangedPanel(bool[] mask,byte[] a,byte[] b){int count=0,changed=0;for(int i=0;i<mask.Length;i++)if(mask[i]){count++;if(System.Math.Abs(a[i*4]-b[i*4])>2||System.Math.Abs(a[i*4+1]-b[i*4+1])>2||System.Math.Abs(a[i*4+2]-b[i*4+2])>2)changed++;}return (double)changed/count;}
 public static bool ClearEdge(byte[] p,int width,int height){for(int y=0;y<height;y++)for(int x=0;x<width;x++)if((x<8||y<8||x>=width-8||y>=height-8)&&p[(y*width+x)*4+3]>24)return false;return true;}
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
$raw=$view.GetType().GetField('sheets',$flags).GetValue($view)
Assert ($view.FrameCount -eq 72) 'Expected 72 full-body raster cels'
$count=0
foreach($action in @('walk','sit','sleep','stretch','wave','compact','moods')){
 $expected=if($action -in @('stretch','wave')){16}else{8}
 Assert ($view.GetFrameCount($action) -eq $expected) "Wrong frame count: $action"
 foreach($frame in 0..($expected-1)){
  Assert ([RasterCheck]::ClearEdge($raw[$action][$frame],$view.PixelWidth,$view.PixelHeight)) "Pose clipped against canvas: $action/$frame"
  $alpha=$null;$hashes=New-Object 'System.Collections.Generic.HashSet[string]'
  foreach($mood in 0..3){foreach($closed in @($false,$true)){
   $view.SetExpression($mood,$closed);$view.SetFrame($action,$frame,$false,100,0,0,-1,0)
   $pixels=$view.GetPixels();Assert ([RasterCheck]::Valid($pixels)) "Invalid raster: $action/$frame/$mood/$closed"
   Assert ([RasterCheck]::PanelFraction($regions[$action][$frame].mask,$pixels) -lt 0.55) "Face detection included body outlines: $action/$frame"
   Assert ([RasterCheck]::ChangedPanel($regions[$action][$frame].mask,$raw[$action][$frame],$pixels) -lt 0.72) "Expression replaced the panel texture: $action/$frame"
   if($null -eq $alpha){$alpha=$pixels}else{Assert ([RasterCheck]::SameAlpha($alpha,$pixels)) 'Expressions must preserve the full-body silhouette'}
   [void]$hashes.Add([Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($pixels)))
   $count++
  }}
  Assert ($hashes.Count -ge 4) 'Every action cel must display four distinct quota moods'
 }
}
$ink=New-Object 'int[]' 1200
foreach($span in @(@(20,290),@(320,580),@(620,880),@(900,1170))){foreach($y in $span[0]..$span[1]){$ink[$y]=50}}
$method=$view.GetType().GetMethod('FindCuts',[Reflection.BindingFlags]'NonPublic,Static')
$arguments=New-Object 'object[]' 2;$arguments[0]=[int[]]$ink;$arguments[1]=[int]4
$cuts=$method.Invoke($null,$arguments)
Assert ($cuts[3] -gt 880 -and $cuts[3] -lt 900) 'Uneven sprite rows must be cut in the blank gutter, not through the sprout'
$mid=Get-SpriteSample 'stretch' 2.7 5 0 0 0 'calm' $false $p
Assert ($mid.frame -eq 9) 'Stretch must pause at its drawn peak'
foreach($action in @('wave','stretch')){
 $s=Get-SpriteSample $action 12 12 140 0 0 'happy' $false $p
 Assert ($s.frame -eq 15) 'The complete 16-frame gesture must play'
}
"PASS: $count action/frame/expression combinations, adaptive gutters, pose margins, retained panel texture, quota moods and timed stretch peak"
