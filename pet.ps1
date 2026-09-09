param([switch]$Preview,[switch]$Smoke,[ValidateSet('idle','walk','sit','sleep','stretch','wave')][string]$PreviewAction='idle',[double]$PreviewAge=3,[ValidateSet('unknown','happy','calm','worried','exhausted')][string]$PreviewMood='unknown')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'behavior-core.ps1')
. (Join-Path $PSScriptRoot 'usage-core.ps1')
$statePath = Join-Path $PSScriptRoot 'settings.json'
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="280" Height="430" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" FontFamily="Microsoft YaHei" UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="Grayscale" Title="码团 · Codex Pet">
 <Grid>
  <Border x:Name="Bubble" Background="#233231" BorderBrush="#447EAF9C" BorderThickness="1" CornerRadius="18" Margin="12,0,12,0" VerticalAlignment="Top" Padding="16,12" Visibility="Collapsed">
   <TextBlock x:Name="Speech" Foreground="#F1FFF7" FontSize="14" TextWrapping="Wrap" TextAlignment="Center"/>
  </Border>
  <Viewbox x:Name="Pet" Width="230" Height="220" VerticalAlignment="Bottom" Margin="0,0,0,154" Cursor="Hand" RenderTransformOrigin="0.5,0.85">
   <Viewbox.RenderTransform><ScaleTransform x:Name="Squish"/></Viewbox.RenderTransform>
   <Canvas Width="220" Height="210">
    <Ellipse Canvas.Left="42" Canvas.Top="187" Width="140" Height="13" Fill="#24000000"><Ellipse.RenderTransform><TranslateTransform x:Name="GroundShift"/></Ellipse.RenderTransform></Ellipse>
    <Canvas x:Name="Body" RenderTransformOrigin="0.5,0.5">
     <Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name="PoseScale" CenterX="110" CenterY="185"/><RotateTransform x:Name="PoseAngle" CenterX="110" CenterY="145"/><TranslateTransform x:Name="Float"/></TransformGroup></Canvas.RenderTransform>
     <Path x:Name="StandingLeftArm" Data="M 55,148 Q 9,140 24,114 Q 39,108 58,124" Fill="#87DEBF" Stroke="#367965" StrokeThickness="3"><Path.RenderTransform><RotateTransform x:Name="LeftArm" CenterX="55" CenterY="133"/></Path.RenderTransform></Path>
     <Path x:Name="StandingRightArm" Data="M 169,145 Q 207,125 202,105 Q 188,98 173,124" Fill="#87DEBF" Stroke="#367965" StrokeThickness="3"><Path.RenderTransform><RotateTransform x:Name="RightArm" CenterX="173" CenterY="133"/></Path.RenderTransform></Path>
     <Ellipse x:Name="StandingLeftFoot" Canvas.Left="65" Canvas.Top="167" Width="32" Height="23" Fill="#69BF9F" Stroke="#367965" StrokeThickness="3"><Ellipse.RenderTransform><TransformGroup><RotateTransform x:Name="LeftFoot" CenterX="16" CenterY="3"/><TranslateTransform x:Name="LeftStep"/></TransformGroup></Ellipse.RenderTransform></Ellipse>
     <Ellipse x:Name="StandingRightFoot" Canvas.Left="131" Canvas.Top="167" Width="32" Height="23" Fill="#69BF9F" Stroke="#367965" StrokeThickness="3"><Ellipse.RenderTransform><TransformGroup><RotateTransform x:Name="RightFoot" CenterX="16" CenterY="3"/><TranslateTransform x:Name="RightStep"/></TransformGroup></Ellipse.RenderTransform></Ellipse>
     <Path Data="M 111,46 Q 98,18 118,12 Q 142,19 122,42" Fill="#BCF5C4" Stroke="#367965" StrokeThickness="3"><Path.RenderTransform><RotateTransform x:Name="Leaf" CenterX="114" CenterY="46"/></Path.RenderTransform></Path>
     <Path Data="M 112,42 Q 90,29 83,40 Q 89,55 112,49" Fill="#7DDFB2" Stroke="#367965" StrokeThickness="3"/>
     <Border Canvas.Left="43" Canvas.Top="45" Width="140" Height="133" CornerRadius="56,56,48,48" BorderBrush="#367965" BorderThickness="3">
      <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0.4,1"><GradientStop Color="#D4FFE3" Offset="0"/><GradientStop Color="#88E0BB" Offset="1"/></LinearGradientBrush></Border.Background>
     </Border>
     <Ellipse Canvas.Left="59" Canvas.Top="61" Width="46" Height="16" Fill="#88FFFFFF" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><RotateTransform Angle="-20"/></Ellipse.RenderTransform></Ellipse>
     <Border Canvas.Left="61" Canvas.Top="86" Width="104" Height="57" CornerRadius="24" Background="#203E38"/>
     <Canvas x:Name="MoodFace"><Canvas.RenderTransform><TranslateTransform x:Name="Gaze"/></Canvas.RenderTransform>
     <Canvas x:Name="Eyes">
      <Canvas.RenderTransform><TransformGroup><ScaleTransform x:Name="Blink" CenterY="110"/><ScaleTransform x:Name="SleepEyes" CenterY="110"/></TransformGroup></Canvas.RenderTransform>
      <Canvas x:Name="OpenEyes"><Ellipse Canvas.Left="82" Canvas.Top="102" Width="10" Height="17" Fill="#C4FFE1"/>
      <Ellipse Canvas.Left="135" Canvas.Top="102" Width="10" Height="17" Fill="#C4FFE1"/></Canvas>
      <Path x:Name="HappyEyes" Data="M 81,111 Q 87,100 94,111 M 134,111 Q 141,100 147,111" Stroke="#D8FFE9" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0"/>
     </Canvas>
     <Path x:Name="MoodMouth" Data="M 106,123 L 120,123" Stroke="#C4FFE1" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"><Path.RenderTransform><ScaleTransform x:Name="Smile" CenterX="113" CenterY="120"/></Path.RenderTransform></Path>
     <Path x:Name="WorryBrows" Data="M 81,99 L 94,94 M 133,94 L 146,99" Stroke="#C4FFE1" StrokeThickness="2.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0"/>
     <Path x:Name="Tears" Data="M 144,119 Q 136,128 144,131 Q 152,128 144,119 Z" Fill="#91CDF6" Opacity="0"/>
     <Ellipse Canvas.Left="70" Canvas.Top="120" Width="13" Height="6" Fill="#CF91A1" Opacity="0.7"/>
     <Ellipse Canvas.Left="144" Canvas.Top="120" Width="13" Height="6" Fill="#CF91A1" Opacity="0.7"/>
     </Canvas>
     <TextBlock Canvas.Left="96" Canvas.Top="149" Text="&lt;/&gt;" FontFamily="Consolas" FontWeight="Bold" Foreground="#357D65" FontSize="18"/>
     <Canvas x:Name="SeatedHands" Opacity="0" IsHitTestVisible="False">
      <Canvas.RenderTransform><TranslateTransform x:Name="HandSettle"/></Canvas.RenderTransform>
      <Path Data="M 51,122 C 40,124 35,141 39,155 C 41,165 50,168 57,161 L 65,143" Fill="#89DFBC" Stroke="#367965" StrokeThickness="3" StrokeLineJoin="Round"/>
      <Path Data="M 174,122 C 185,124 190,141 186,155 C 184,165 175,168 168,161 L 160,143" Fill="#89DFBC" Stroke="#367965" StrokeThickness="3" StrokeLineJoin="Round"/>
      <Path Data="M 43,154 Q 48,157 53,153 M 172,153 Q 177,157 182,154" Stroke="#5DAA8D" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
     </Canvas>
     <Canvas x:Name="SeatedFeet" Opacity="0" IsHitTestVisible="False">
      <Canvas.RenderTransform><TranslateTransform x:Name="FootReach"/></Canvas.RenderTransform>
      <Path Data="M 79,155 C 59,153 47,162 49,177 C 51,191 72,195 91,183 L 101,167" Fill="#7BCCAB" Stroke="#367965" StrokeThickness="3" StrokeLineJoin="Round"/>
      <Path Data="M 145,155 C 165,153 177,162 175,177 C 173,191 152,195 133,183 L 123,167" Fill="#7BCCAB" Stroke="#367965" StrokeThickness="3" StrokeLineJoin="Round"/>
      <Ellipse Canvas.Left="49" Canvas.Top="158" Width="44" Height="35" Fill="#BDF0D2" Stroke="#367965" StrokeThickness="3" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><RotateTransform Angle="-18"/></Ellipse.RenderTransform></Ellipse>
      <Ellipse Canvas.Left="132" Canvas.Top="158" Width="44" Height="35" Fill="#BDF0D2" Stroke="#367965" StrokeThickness="3" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><RotateTransform Angle="18"/></Ellipse.RenderTransform></Ellipse>
      <Ellipse Canvas.Left="61" Canvas.Top="174" Width="19" Height="11" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="145" Canvas.Top="174" Width="19" Height="11" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="57" Canvas.Top="168" Width="5" Height="5" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="66" Canvas.Top="164" Width="5" Height="5" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="75" Canvas.Top="166" Width="5" Height="5" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="145" Canvas.Top="166" Width="5" Height="5" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="154" Canvas.Top="164" Width="5" Height="5" Fill="#83CFA9"/>
      <Ellipse Canvas.Left="163" Canvas.Top="168" Width="5" Height="5" Fill="#83CFA9"/>
     </Canvas>
    </Canvas>
    <TextBlock x:Name="SleepMark" Canvas.Left="166" Canvas.Top="65" Text="z Z" FontFamily="Segoe UI" FontSize="23" FontWeight="SemiBold" Foreground="#71AE97" Opacity="0" IsHitTestVisible="False"><TextBlock.RenderTransform><TranslateTransform x:Name="SleepFloat"/></TextBlock.RenderTransform></TextBlock>
   </Canvas>
  </Viewbox>
  <Border VerticalAlignment="Bottom" HorizontalAlignment="Stretch" Background="#233231" CornerRadius="16" Padding="16,12" Margin="12,0,12,4">
   <StackPanel>
    <TextBlock x:Name="Label" Text="码团  ·  陪你写点东西" Foreground="#DFF8EB" FontSize="13" Margin="0,0,0,8"/>
    <TextBlock x:Name="FiveText" Text="5 小时  ·  连接中" Foreground="#F5FFFA" FontSize="15" FontWeight="SemiBold"/>
    <ProgressBar x:Name="FiveBar" Height="4" Margin="0,5,0,8" Maximum="100" Background="#39534A" Foreground="#89E4B9" BorderThickness="0"/>
    <TextBlock x:Name="WeekText" Text="一周  ·  连接中" Foreground="#F5FFFA" FontSize="15" FontWeight="SemiBold"/>
    <ProgressBar x:Name="WeekBar" Height="4" Margin="0,5,0,6" Maximum="100" Background="#39534A" Foreground="#89BDF1" BorderThickness="0"/>
    <TextBlock x:Name="SyncText" Text="只读同步 · 每分钟刷新" Foreground="#C1D6CB" FontSize="11"/>
   </StackPanel>
  </Border>
 </Grid>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$pet = $window.FindName('Pet')
$squish = $window.FindName('Squish')
$float = $window.FindName('Float')
$bubble = $window.FindName('Bubble')
$speech = $window.FindName('Speech')
$eyes = $window.FindName('Eyes')
$blink = $window.FindName('Blink')
$leaf = $window.FindName('Leaf')
$label = $window.FindName('Label')
$poseScale = $window.FindName('PoseScale')
$poseAngle = $window.FindName('PoseAngle')
$leftFoot = $window.FindName('LeftFoot')
$rightFoot = $window.FindName('RightFoot')
$leftArm = $window.FindName('LeftArm')
$rightArm = $window.FindName('RightArm')
$sleepEyes = $window.FindName('SleepEyes')
$sleepMark = $window.FindName('SleepMark')
$sleepFloat = $window.FindName('SleepFloat')
$seatedHands=$window.FindName('SeatedHands')
$seatedFeet=$window.FindName('SeatedFeet')
$handSettle=$window.FindName('HandSettle')
$footReach=$window.FindName('FootReach')
$groundShift=$window.FindName('GroundShift')
$standingHands=@($window.FindName('StandingLeftArm'),$window.FindName('StandingRightArm'))
$standingFeet=@($window.FindName('StandingLeftFoot'),$window.FindName('StandingRightFoot'))
$leftStep=$window.FindName('LeftStep'); $rightStep=$window.FindName('RightStep')
$gaze=$window.FindName('Gaze'); $smile=$window.FindName('Smile')
$script:mood='unknown'
function Set-UsageMood($mood) {
 $text=switch ($mood.name) { 'happy' {'额度充足，元气满满'} 'calm' {'额度够用，安心陪伴'} 'worried' {'额度快用完了，有点担心'} 'exhausted' {'额度用完了，等重置再一起玩'} default {'额度尚未同步，保持中性表情'} }
 if ($null -ne $mood.remaining) { $text+='（'+$(if ($mood.limiting -eq 'weekly') {'一周'} else {'5 小时'})+'剩余 '+$mood.remaining+'%）' }
 $pet.ToolTip=$text
 if ($script:mood -eq $mood.name) { return }
 $script:mood=$mood.name
 $mouth=switch ($mood.name) { 'happy' {'M 102,119 Q 113,139 125,119'} 'calm' {'M 105,120 Q 113,128 122,120'} 'worried' {'M 105,126 Q 113,119 122,126'} 'exhausted' {'M 103,128 Q 113,116 124,128'} default {'M 106,123 L 120,123'} }
 $window.FindName('MoodMouth').Data=[Windows.Media.Geometry]::Parse($mouth)
 $window.FindName('HappyEyes').Opacity=$(if ($mood.name -eq 'happy') {1.0} else {0.0})
 $window.FindName('OpenEyes').Opacity=$(if ($mood.name -eq 'happy') {0.0} else {1.0})
 $window.FindName('WorryBrows').Opacity=$(if ($mood.name -in @('worried','exhausted')) {1.0} else {0.0})
 $window.FindName('Tears').Opacity=$(if ($mood.name -eq 'exhausted') {0.9} else {0.0})
 if (-not $Preview -and -not $script:quiet) {
  $a=New-Object Windows.Media.Animation.DoubleAnimation
  $a.From=0.55; $a.To=1; $a.Duration=[TimeSpan]::FromMilliseconds(350)
  $window.FindName('MoodFace').BeginAnimation([Windows.UIElement]::OpacityProperty,$a)
 }
}
$script:worker = $null
$script:nextRefresh = [DateTime]::MinValue
$script:usageStamp = ''
function Refresh-Usage {
 if ($Preview -or $Smoke) { return }
 if ($null -ne $script:worker -and -not $script:worker.HasExited) { return }
 $workerPath = Join-Path $PSScriptRoot 'read-usage.ps1'
 $script:worker = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$workerPath+'"') -WindowStyle Hidden -PassThru
 $script:nextRefresh = [DateTime]::Now.AddSeconds(60)
}
function Show-Usage {
 $path = Join-Path $PSScriptRoot 'usage.json'
 if (-not (Test-Path -LiteralPath $path)) { Set-UsageMood (Get-UsageMood $null); return }
 try {
  $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Set-UsageMood (Get-UsageMood $data)
  foreach ($entry in @(@('Five','5 小时',$data.fiveHour),@('Week','一周',$data.weekly))) {
   $text = $window.FindName($entry[0]+'Text'); $bar = $window.FindName($entry[0]+'Bar'); $w = $entry[2]
   if ($null -eq $w) {
    $text.Text = $entry[1]+'  ·  暂无数据'
    $bar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty,$null)
    $bar.Value=0; $bar.Tag=$null; $text.ToolTip='请先使用 ChatGPT 账户登录 Codex'; continue
   }
   $expired = $null -ne $w.resetsAt -and [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -ge $w.resetsAt
   $text.Text = $entry[1]+'  ·  剩余 '+$w.remaining+'%'
   $targetValue = $w.remaining
   if ($expired) { $text.Text = $entry[1]+'  ·  等待重置同步'; $targetValue=0 }
   if ($bar.Tag -ne [string]$targetValue) {
    $bar.Tag=[string]$targetValue
    $anim = New-Object Windows.Media.Animation.DoubleAnimation
    $anim.From=$bar.Value; $anim.To=$targetValue; $anim.Duration=[TimeSpan]::FromMilliseconds(700)
    $ease=New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode='EaseOut'; $anim.EasingFunction=$ease
    $bar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty,$anim)
   }
   $text.ToolTip='重置时间：暂无数据'
   if ($null -ne $w.resetsAt) { $text.ToolTip='重置时间：'+[DateTimeOffset]::FromUnixTimeSeconds($w.resetsAt).LocalDateTime.ToString('MM-dd HH:mm') }
  }
  $sync = $window.FindName('SyncText')
  if ($data.updatedAt -gt 0) {
   $stamp = [DateTimeOffset]::FromUnixTimeSeconds($data.updatedAt).LocalDateTime.ToString('HH:mm')
   $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-$data.updatedAt
   $route = $(if ($data.route -eq 'direct') {'直连'} else {'系统网络'})
   $sync.Text = $(if ($data.status -eq 'ok' -and $age -lt 120) {$route+' '+$stamp+' · 悬停查看重置'} else {'缓存 '+$stamp+' · 连接待恢复'})
  } else { $sync.Text='未连接 · 请登录 Codex 后刷新' }
 } catch { Set-UsageMood (Get-UsageMood $null) }
}
$script:quiet = $false
$script:scale = 1.0
$script:drag = $null
$script:moved = $false
$script:tick = 0
$script:bubbleUntil = [DateTime]::MinValue
$script:focusUntil = $null
$script:randomActions = $true
$script:action = 'idle'
$script:lastAction = ''
$script:actionStarted = [DateTime]::Now
$script:actionDuration = 0.0
$script:nextAction = [DateTime]::Now.AddSeconds(7)
$script:walkFrom = 0.0
$script:walkTo = 0.0
$script:clock = [Diagnostics.Stopwatch]::StartNew()
$script:nextBlink = 3.0
$script:lookX=0.0; $script:lookY=0.0; $script:nextLook=2.0
$script:doubleBlink=$false; $script:happyUntil=0.0; $script:frameAt=0.0
$script:renderedPose=$null; $script:fromPose=$null
function Apply-Pose($pose) {
 $script:renderedPose=$pose.Clone()
 $poseScale.ScaleX=$pose.sx; $poseScale.ScaleY=$pose.sy; $poseAngle.Angle=$pose.angle
 $float.X=$pose.x; $float.Y=$pose.y
 $leftFoot.Angle=$pose.foot; $rightFoot.Angle=-$pose.foot
 $leftArm.Angle=$pose.arm; $rightArm.Angle=-$pose.arm+$pose.wave
 $leftStep.Y=$pose.leftStep; $rightStep.Y=$pose.rightStep
 $sleepEyes.ScaleY=$pose.eye; $sleepMark.Opacity=$pose.sleep
 $seatedHands.Opacity=$pose.sitHands; $seatedFeet.Opacity=$pose.sitFeet
 foreach ($hand in $standingHands) { $hand.Opacity=1-$pose.sitHands }
 foreach ($foot in $standingFeet) { $foot.Opacity=1-$pose.sitFeet }
 $handSettle.Y=-8*(1-$pose.sitHands)
 $footReach.Y=-9*(1-$pose.sitFeet)
 $groundShift.Y=$pose.ground
}
function Set-PetAction([string]$action) {
 $script:fromPose=$script:renderedPose
 if ($action -ne 'idle') { $script:quiet=$false }
 $script:action=$action; $script:actionStarted=[DateTime]::Now
 $script:nextAction=[DateTime]::Now.AddSeconds((Get-Random -Minimum 12 -Maximum 25))
 $script:actionDuration = switch ($action) { 'walk' {8.0} 'sit' {12.0} 'sleep' {18.0} 'stretch' {5.0} 'wave' {3.8} default {0.0} }
 $blink.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$null)
 if ($action -eq 'walk') {
  $area=[Windows.SystemParameters]::WorkArea
  $script:walkFrom=$window.Left
  $script:walkTo=Get-WalkTarget $window.Left $window.Width $area.Left $area.Right (Get-Random -InputObject @(-1,1)) (Get-Random -Minimum 90 -Maximum 171)
 }
 if ($action -ne 'idle') { $script:lastAction=$action }
 if ($null -eq $script:focusUntil) {
  $label.Text = switch ($action) { 'walk' {'码团  ·  出门溜达一下'} 'sit' {'码团  ·  坐着陪你'} 'sleep' {'码团  ·  小憩一会儿'} 'stretch' {'码团  ·  伸个懒腰'} 'wave' {'码团  ·  嗨，我在呢'} default {'码团  ·  陪你写点东西'} }
 }
 if ($action -eq 'idle' -and $script:quiet) { Apply-Pose (Get-PetPose 'idle' 0 0); $gaze.X=0; $gaze.Y=0 }
}
function Update-Behavior {
 $now=[DateTime]::Now
 $t=$script:clock.Elapsed.TotalSeconds
 $dt=[Math]::Min(0.1,[Math]::Max(0.001,$t-$script:frameAt)); $script:frameAt=$t
 if ($script:quiet) { return }
 if ($script:action -eq 'idle' -and $script:randomActions -and $null -eq $script:focusUntil -and $null -eq $script:drag -and -not $menu.IsOpen -and -not $window.IsMouseOver -and $now -ge $script:nextAction) {
  $choices=@('walk','sit','sit','sleep','stretch','wave') | Where-Object { $_ -ne $script:lastAction }
  Set-PetAction (Get-Random -InputObject $choices)
 }
 $age=($now-$script:actionStarted).TotalSeconds
 if ($script:action -ne 'idle' -and $age -ge $script:actionDuration) {
  if ($script:action -eq 'walk') { $window.Left=$script:walkTo }
  $finished=$script:action
  if ($finished -eq 'sleep') { Set-PetAction 'stretch' } else { Set-PetAction 'idle' }
  $age=0.0
 }
 $pose=Get-PetPose $script:action $age $script:actionDuration ([Math]::Abs($script:walkTo-$script:walkFrom))
 if ($script:action -eq 'idle') {
  $breath=[Math]::Sin($t*1.65)
  $pose.y=-1.2*$breath; $pose.sy=1+0.009*$breath; $pose.sx=1-0.004*$breath
  $pose.angle=[Math]::Sin($t*0.53)*0.8+$gaze.X*0.32
  $pose.arm=[Math]::Sin($t*1.1)*2
 }
 if ($null -ne $script:fromPose -and $age -lt 0.36) {
  $f=[Math]::Min(1.0,[Math]::Max(0.0,$age/0.36)); $f=$f*$f*(3-2*$f)
  foreach ($key in @($pose.Keys)) { if ($key -ne 'progress') { $pose[$key]=$script:fromPose[$key]+($pose[$key]-$script:fromPose[$key])*$f } }
 }
 Apply-Pose $pose
 if ($script:action -eq 'walk') { $window.Left=$script:walkFrom+($script:walkTo-$script:walkFrom)*$pose.progress }
 $leafTarget=[Math]::Sin($t*1.7)*$(if ($script:action -eq 'sleep') {0.7} else {3.0})-$pose.angle*0.55
 $leaf.Angle+=($leafTarget-$leaf.Angle)*(1-[Math]::Exp(-5*$dt))
 $sleepFloat.Y=-[Math]::Sin($age*1.8)*4
 if (-not $pet.IsMouseOver -and $t -ge $script:nextLook) {
  $script:lookX=(Get-Random -Minimum -24 -Maximum 25)/10.0
  $script:lookY=(Get-Random -Minimum -12 -Maximum 13)/10.0
  $script:nextLook=$t+(Get-Random -Minimum 3 -Maximum 7)
 }
 if ($script:action -eq 'walk') { $script:lookX=[Math]::Sign($script:walkTo-$script:walkFrom)*3.0; $script:lookY=0.0 }
 if ($script:action -eq 'sleep') { $script:lookX=0.0; $script:lookY=0.0 }
 $gaze.X+=($script:lookX-$gaze.X)*(1-[Math]::Exp(-7*$dt))
 $gaze.Y+=($script:lookY-$gaze.Y)*(1-[Math]::Exp(-7*$dt))
 $smileTarget=$(if ($t -lt $script:happyUntil -and $script:mood -notin @('worried','exhausted')) {1.45} else {1.0})
 $smile.ScaleY+=($smileTarget-$smile.ScaleY)*(1-[Math]::Exp(-8*$dt))
 if ($t -ge $script:nextBlink -and $script:action -ne 'sleep') {
  $a=New-Object Windows.Media.Animation.DoubleAnimation
  $a.From=1; $a.To=0.09; $a.Duration=[TimeSpan]::FromMilliseconds((Get-Random -Minimum 80 -Maximum 111)); $a.AutoReverse=$true
  $blink.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$a)
  if (-not $script:doubleBlink -and (Get-Random -Minimum 0 -Maximum 6) -eq 0) { $script:nextBlink=$t+0.3; $script:doubleBlink=$true }
  else { $script:nextBlink=$t+(Get-Random -Minimum 28 -Maximum 66)/10.0; $script:doubleBlink=$false }
 }
}
$lines = @('我在。慢慢来，一起把它做好。','投喂一个好点子，我来长出代码。','正在收集你散落的灵感。','今天也要给自己留一点空白。','摸摸收到！灵感 +1。','小小一团，随叫随到。','写累了就看看远处吧。')
function Say([string]$message) {
 $script:happyUntil=$script:clock.Elapsed.TotalSeconds+1.8
 $speech.Text = $message
 $bubble.Visibility = 'Visible'
 if (-not $Preview -and -not $script:quiet) {
  $fade=New-Object Windows.Media.Animation.DoubleAnimation
  $fade.From=0; $fade.To=1; $fade.Duration=[TimeSpan]::FromMilliseconds(220)
  $bubble.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
 }
 $script:bubbleUntil = [DateTime]::Now.AddSeconds(6)
}
function Bounce([double]$x, [double]$y) {
 foreach ($pair in @(@([Windows.Media.ScaleTransform]::ScaleXProperty,$x),@([Windows.Media.ScaleTransform]::ScaleYProperty,$y))) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.From = $pair[1]; $a.To = 1; $a.Duration = [TimeSpan]::FromMilliseconds(430)
  $ease = New-Object Windows.Media.Animation.ElasticEase
  $ease.Oscillations = 2; $ease.Springiness = 5; $ease.EasingMode = 'EaseOut'; $a.EasingFunction = $ease
  $squish.BeginAnimation($pair[0], $a)
 }
}
function Save-State {
 @{left=$window.Left;top=$window.Top;scale=$script:scale;quiet=$script:quiet;topmost=$window.Topmost;randomActions=$script:randomActions} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}
function Clamp-Position {
 $area = [Windows.SystemParameters]::WorkArea
 $window.Left = [Math]::Max($area.Left,[Math]::Min($window.Left,$area.Right-$window.Width))
 $window.Top = [Math]::Max($area.Top,[Math]::Min($window.Top,$area.Bottom-$window.Height))
}
function Resize-Pet([double]$size) {
 Set-PetAction 'idle'
 $script:scale = $size; $window.Width = [Math]::Max(280,280*$size); $window.Height = 210+220*$size
 $pet.Width=230*$size; $pet.Height=220*$size
 Clamp-Position
}
$area = [Windows.SystemParameters]::WorkArea
$window.Left = $area.Right-300; $window.Top = $area.Bottom-450
if (-not $Preview -and -not $Smoke -and (Test-Path -LiteralPath $statePath)) {
 try {
  $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  $window.Left = [double]$saved.left; $window.Top = [double]$saved.top
  $script:quiet = [bool]$saved.quiet; $window.Topmost = [bool]$saved.topmost
  if ($null -ne $saved.randomActions) { $script:randomActions=[bool]$saved.randomActions }
  Resize-Pet ([Math]::Max(0.7,[Math]::Min(1.5,[double]$saved.scale)))
 } catch { }
}
Clamp-Position
$pet.Add_MouseLeftButtonDown({
 $script:wokeFromSleep=$script:action -eq 'sleep'
 Set-PetAction 'idle'
 $script:drag = $pet.PointToScreen($_.GetPosition($pet))
 $script:startLeft = $window.Left; $script:startTop = $window.Top; $script:moved = $false
 $squish.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty,$null)
 $squish.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$null)
 $squish.ScaleX = 1.08; $squish.ScaleY = 0.9
 [void]$pet.CaptureMouse(); $_.Handled = $true
})
$pet.Add_MouseMove({
 $local=$_.GetPosition($pet)
 $script:lookX=[Math]::Max(-3.5,[Math]::Min(3.5,($local.X/[Math]::Max(1.0,$pet.ActualWidth)-0.5)*9))
 $script:lookY=[Math]::Max(-2.0,[Math]::Min(2.0,($local.Y/[Math]::Max(1.0,$pet.ActualHeight)-0.5)*5))
 if ($null -eq $script:drag) { return }
 $p = $pet.PointToScreen($_.GetPosition($pet))
 $dpi = [Windows.PresentationSource]::FromVisual($window).CompositionTarget.TransformFromDevice
 $delta = $dpi.Transform([Windows.Vector]::new($p.X-$script:drag.X,$p.Y-$script:drag.Y))
 if ([Math]::Abs($delta.X)+[Math]::Abs($delta.Y) -gt 5) { $script:moved = $true }
 if ($script:moved) { $window.Left = $script:startLeft+$delta.X; $window.Top = $script:startTop+$delta.Y }
})
$pet.Add_MouseLeftButtonUp({
 if ($null -eq $script:drag) { return }
 $script:drag = $null; $pet.ReleaseMouseCapture(); Bounce 1.12 0.86
 if ($script:moved) {
  Clamp-Position
  $a = [Windows.SystemParameters]::WorkArea
  if ($window.Left-$a.Left -lt 45) { $window.Left = $a.Left }
  if ($a.Right-$window.Left-$window.Width -lt 45) { $window.Left = $a.Right-$window.Width }
  if ($window.Top-$a.Top -lt 45) { $window.Top = $a.Top }
  if ($a.Bottom-$window.Top-$window.Height -lt 45) { $window.Top = $a.Bottom-$window.Height }
  Save-State
 } else {
  if ($script:wokeFromSleep) { Set-PetAction 'stretch'; Say '唔，醒啦。伸个懒腰就来陪你。' }
  else { Say ($lines | Get-Random) }
 }
})
$pet.Add_LostMouseCapture({ $script:drag = $null; Bounce 1.06 0.94 })
$bubble.Add_MouseLeftButtonUp({ $bubble.Visibility = 'Collapsed' })
$menu = New-Object Windows.Controls.ContextMenu
function Add-Item([string]$title,[scriptblock]$action) {
 $item = New-Object Windows.Controls.MenuItem
 $item.Header = $title; $item.Add_Click($action); [void]$menu.Items.Add($item)
}
Add-Item '摸摸码团' { Set-PetAction 'idle'; Say ($lines | Get-Random); Bounce 1.15 0.83 }
Add-Item '散步一会儿' { Set-PetAction 'walk' }
Add-Item '坐下陪我' { Set-PetAction 'sit' }
Add-Item '躺下休息' { Set-PetAction 'sleep' }
Add-Item '伸个懒腰' { Set-PetAction 'stretch' }
Add-Item '挥手打招呼' { Set-PetAction 'wave' }
Add-Item '开关随机待机动作' { $script:randomActions=-not $script:randomActions; Set-PetAction 'idle'; Save-State; Say $(if ($script:randomActions) {'我会自己散步，也会乖乖休息。'} else {'我就待在这里陪你。'}) }
Add-Item '专注 25 分钟' { Set-PetAction 'idle'; $script:focusUntil = [DateTime]::Now.AddMinutes(25); Say '好，我陪你专注 25 分钟。' }
Add-Item '结束专注' { $script:focusUntil = $null; $label.Text = '码团  ·  陪你写点东西'; Say '休息一下，伸个懒腰。' }
Add-Item '查看 Codex 用量页面' { Start-Process 'https://chatgpt.com/codex/settings/usage' }
Add-Item '刷新 5 小时 / 一周用量' { Refresh-Usage; Say '正在更新两档用量。' }
Add-Item '安静 / 灵动模式' { $script:quiet = -not $script:quiet; Set-PetAction 'idle'; $leaf.Angle=0; Save-State; Say $(if ($script:quiet) {'我安静陪着你。'} else {'码团又精神啦。'}) }
Add-Item '小号' { Resize-Pet 0.8; Save-State }
Add-Item '标准大小' { Resize-Pet 1; Save-State }
Add-Item '大号' { Resize-Pet 1.3; Save-State }
Add-Item '切换置顶' { $window.Topmost = -not $window.Topmost; Save-State }
Add-Item '收起码团（退出）' { $window.Close() }
$pet.ContextMenu = $menu
$menu.FontFamily='Microsoft YaHei'; $menu.FontSize=14
$menu.Add_Opened({ Set-PetAction 'idle' })
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({
 $script:tick++
 if ($Smoke) {
  switch ($script:tick) {
   1 {Set-PetAction 'walk'; $script:smokeOrigin=$window.Left}
   80 {$script:smokeDistance=[Math]::Abs($window.Left-$script:smokeOrigin)}
   90 {Set-PetAction 'sit'} 145 {Set-PetAction 'sleep'} 200 {Set-PetAction 'stretch'} 250 {Set-PetAction 'wave'}
   300 {Set-PetAction 'idle'} 325 {$window.Close(); return}
  }
 }
 if ($script:tick % 30 -eq 0 -and -not $Smoke) {
  if ([DateTime]::Now -ge $script:nextRefresh) { Refresh-Usage }
  Show-Usage
 }
 Update-Behavior
 if ([DateTime]::Now -gt $script:bubbleUntil) { $bubble.Visibility = 'Collapsed' }
 if ($null -ne $script:focusUntil) {
  $remaining = $script:focusUntil-[DateTime]::Now
  if ($remaining.TotalSeconds -le 0) { $script:focusUntil = $null; $label.Text = '码团  ·  休息时间'; Say '25 分钟到啦！喝口水，看看远处。' }
  else { $label.Text = '专注陪伴  '+$remaining.ToString('mm\:ss') }
 }
})
$window.Add_Closed({ $timer.Stop(); if (-not $Preview -and -not $Smoke) { Save-State } })
if ($Preview) {
 Resize-Pet 0.8
 Resize-Pet 1.3
 Resize-Pet 1
 Bounce 1.12 0.86
 $squish.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty,$null)
 $squish.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$null)
 $window.Show(); Say '你好，我是码团。两档用量，我帮你看着。'
 $window.FindName('FiveText').Text='5 小时  ·  剩余 72%'
 $window.FindName('FiveBar').Value=72
 $window.FindName('WeekText').Text='一周  ·  剩余 48%'
 $window.FindName('WeekBar').Value=48
 $window.FindName('SyncText').Text='外观预览 · 示例数据'
 Apply-Pose (Get-PetPose $PreviewAction $PreviewAge 12)
 Set-UsageMood @{name=$PreviewMood;remaining=$null;limiting=$null}
 if ($PreviewMood -ne 'unknown') {
  $sample=switch ($PreviewMood) { 'happy' {85} 'calm' {45} 'worried' {12} 'exhausted' {0} }
  $window.FindName('FiveText').Text='5 小时  ·  剩余 '+$sample+'%'
  $window.FindName('FiveBar').Value=$sample
  $window.FindName('WeekText').Text='一周  ·  剩余 80%'
  $window.FindName('WeekBar').Value=80
 }
 $window.UpdateLayout()
 $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap(280,430,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $bmp.Render($window)
 $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
 $previewName = $(if ($PreviewAction -eq 'idle') {'preview.png'} else {'preview-'+$PreviewAction+'.png'})
 if ($PreviewMood -ne 'unknown') { $previewName='preview-mood-'+$PreviewMood+'.png' }
 $stream = [IO.File]::Create((Join-Path $PSScriptRoot $previewName))
 $encoder.Save($stream); $stream.Dispose(); $window.Close()
} else {
 Refresh-Usage
 $timer.Start()
 Say '你好，我是码团。点我摸摸，右键打开菜单。'
 [void]$window.ShowDialog()
 if ($Smoke) {
  if ($null -eq $script:smokeDistance -or $script:smokeDistance -lt 8) {throw 'Live walking did not move the desktop window'}
  Write-Output ('PASS: live desktop displacement '+[Math]::Round($script:smokeDistance,1)+' px')
 }
}
