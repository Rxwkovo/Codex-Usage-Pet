param([Parameter(Mandatory=$true)][string]$WindowsSource)
$ErrorActionPreference='Stop'
$root=(Resolve-Path $WindowsSource).Path
$dest=(Resolve-Path (Join-Path $PSScriptRoot "app/src/main/assets/pet")).Path
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -Path "$root/sprite-player.cs" -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
$player=New-Object PetSpriteView
$player.Load("$root/assets/flat")
$count=0
foreach($key in @('walk','sit','sleep','stretch','wave','compact','moods')) {
 foreach($i in 0..($player.GetFrameCount($key)-1)) {
  # The moods sheet is its own face atlas: cell i already holds the face that the app
  # asks for by index, so it must be exported with its OWN expression. Pinning this to
  # 0 (as it was) made Compose() wipe each cell's face and paint cell 0 over all of
  # them, so the shipped moods_0..7 were eight copies of the calm open-eyed face: idle
  # blinking did nothing and all four quota moods looked identical on the phone.
  $expressions=if($key -eq 'moods'){@($i)}else{@(0..7)}
  foreach($expression in $expressions){
   $player.SetExpression(($expression%4),($expression -ge 4))
   $player.SetFrame($key,$i,$false,100,0,0,-1,0)
   $bitmap=[Windows.Media.Imaging.BitmapSource]::Create($player.PixelWidth,$player.PixelHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32,$null,$player.GetPixels(),($player.PixelWidth*4))
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
   $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
   $name=if($key -eq 'moods'){"${key}_${i}.png"}else{"${key}_${i}_${expression}.png"}
   $stream=[IO.File]::Create((Join-Path $dest $name))
   try {$encoder.Save($stream)} finally {$stream.Dispose()}
   $count++
  }
 }
}
"Exported $count HD frames from Windows v2.1.2"
