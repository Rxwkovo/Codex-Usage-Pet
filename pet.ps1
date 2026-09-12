param([switch]$Preview,[switch]$Smoke,[switch]$PreviewCompact,[switch]$PreviewSettings,[ValidateSet('idle','walk','sit','sleep','stretch','wave')][string]$PreviewAction='idle',[double]$PreviewAge=3,[ValidateSet('unknown','happy','calm','worried','exhausted')][string]$PreviewMood='unknown')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'behavior-core.ps1')
. (Join-Path $PSScriptRoot 'sprite-core.ps1')
if(-not ('PetSpriteView' -as [type])) {
 Add-Type -Path (Join-Path $PSScriptRoot 'sprite-player.cs') -ReferencedAssemblies @('System.dll','System.Core.dll',[Windows.DependencyObject].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.FrameworkElement].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location)
}
. (Join-Path $PSScriptRoot 'usage-core.ps1')
. (Join-Path $PSScriptRoot 'preferences-core.ps1')
. (Join-Path $PSScriptRoot 'settings-ui.ps1')
. (Join-Path $PSScriptRoot 'mobile-core.ps1')
. (Join-Path $PSScriptRoot 'mobile-ui.ps1')
if(-not $Preview -and -not $Smoke){Initialize-MobileLink}
$script:preferencesPath=Join-Path $PSScriptRoot 'preferences.json'
$script:preferences=Get-DefaultPreferences
if (-not $Preview -and -not $Smoke -and (Test-Path $script:preferencesPath)) {
 try {
  $loaded=Get-Content $script:preferencesPath -Raw | ConvertFrom-Json
  $candidate=$script:preferences.Clone()
  foreach($prop in $loaded.PSObject.Properties) {if($candidate.ContainsKey($prop.Name)) {$candidate[$prop.Name]=$prop.Value}}
  if(-not (Test-Preferences $candidate)) {$script:preferences=$candidate}
 } catch { }
}
$script:settingsWindow=$null
$script:compact=0.0; $script:compactTarget=0.0; $script:compactFrom=0.0; $script:compactStarted=0.0
$script:lastInteraction=[DateTime]::Now; $script:expandedUntil=[DateTime]::Now
$script:quotaSignature=$null
$statePath = Join-Path $PSScriptRoot 'settings.json'
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="280" Height="430" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" FontFamily="Microsoft YaHei" UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="Grayscale" Title="码团 · Codex Pet">
 <Grid>
  <Border x:Name="Bubble" Background="#233231" BorderBrush="#447EAF9C" BorderThickness="1" CornerRadius="18" Margin="12,0,12,0" VerticalAlignment="Top" Padding="16,12" Visibility="Collapsed">
   <TextBlock x:Name="Speech" Foreground="#F1FFF7" FontSize="14" TextWrapping="Wrap" TextAlignment="Center"/>
  </Border>
  <Viewbox x:Name="Pet" Width="230" Height="220" VerticalAlignment="Bottom" Margin="0,0,0,154" Cursor="Hand" RenderTransformOrigin="0.5,0.85">
   <Viewbox.RenderTransform><ScaleTransform x:Name="Squish"/></Viewbox.RenderTransform>
   <Grid x:Name="SpriteHost" Width="220" Height="210"/>
  </Viewbox>
  <Border x:Name="QuotaPanel" VerticalAlignment="Bottom" HorizontalAlignment="Stretch" Background="#233231" CornerRadius="16" Padding="16,12" Margin="12,0,12,4">
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
if($Smoke){$window.IsHitTestVisible=$false; $window.ShowActivated=$false}
$pet = $window.FindName('Pet')
$squish = $window.FindName('Squish')
$bubble=$window.FindName('Bubble'); $speech=$window.FindName('Speech'); $label=$window.FindName('Label')
$script:sprite=New-Object PetSpriteView
$script:sprite.Width=220; $script:sprite.Height=210
$script:sprite.Load((Join-Path $PSScriptRoot 'assets/flat'))
[void]$window.FindName('SpriteHost').Children.Add($script:sprite)
$script:mood='unknown'
function Set-UsageMood($mood) {
 $text=switch ($mood.name) { 'happy' {'额度充足，元气满满'} 'calm' {'额度够用，安心陪伴'} 'worried' {'额度快用完了，有点担心'} 'exhausted' {'额度用完了，等重置再一起玩'} default {'额度尚未同步，保持中性表情'} }
 if ($null -ne $mood.remaining) { $text+='（'+$(if ($mood.limiting -eq 'weekly') {'一周'} else {'5 小时'})+'剩余 '+$mood.remaining+'%）' }
 $pet.ToolTip=$text
 $script:mood=$mood.name
}
$script:worker = $null
$script:workerStarted = [DateTime]::MinValue
$script:nextRefresh = [DateTime]::MinValue
$script:usageStamp = ''
function Refresh-Usage {
 if ($Preview -or $Smoke) { return }
 if ($null -ne $script:worker) {
  if (-not $script:worker.HasExited) {
   # read-usage.ps1 has its own timeouts (12s direct / 25s proxied), but the guard
   # below used to be the only exit: a wedged worker left HasExited false forever,
   # so quota refresh stopped for the rest of the session. Reap it after the
   # longest internal timeout plus a generous margin.
   if (-not (Test-UsageWorkerStale $script:workerStarted ([DateTime]::Now))) { return }
   try { $script:worker.Kill(); $script:worker.WaitForExit(2000) | Out-Null } catch { }
  }
  try { $script:worker.Dispose() } catch { }
  $script:worker = $null
 }
 $workerPath = Join-Path $PSScriptRoot 'read-usage.ps1'
 $script:worker = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$workerPath+'"') -WindowStyle Hidden -PassThru
 $script:workerStarted = [DateTime]::Now
 $script:nextRefresh = [DateTime]::Now.AddSeconds($script:preferences.refreshSeconds)
}
function Show-Usage {
 $path = Join-Path $PSScriptRoot 'usage.json'
 if (-not (Test-Path -LiteralPath $path)) { Set-UsageMood (Get-UsageMood $null); return }
 try {
  $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Set-UsageMood (Get-UsageMood $data -StaleSeconds $script:preferences.staleSeconds -HappyThreshold $script:preferences.happyThreshold -WorriedThreshold $script:preferences.worriedThreshold)
  $signature=@($data.fiveHour.remaining,$data.weekly.remaining,$data.fiveHour.resetsAt,$data.weekly.resetsAt) -join '|'
  if($data.status -eq 'ok') {
   if($null -ne $script:quotaSignature -and $signature -ne $script:quotaSignature -and $script:preferences.wakeOnUsage) {Wake-Pet}
   $script:quotaSignature=$signature
  }
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
    $anim.From=$bar.Value; $anim.To=$targetValue; $anim.Duration=[TimeSpan]::FromSeconds($script:preferences.barTransition)
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
   $sync.Text = $(if ($data.status -eq 'ok' -and $age -lt $script:preferences.staleSeconds) {$route+' '+$stamp+' · 悬停查看重置'} else {'缓存 '+$stamp+' · 连接待恢复'})
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
$script:nextAction = [DateTime]::Now.AddSeconds((Get-RandomRange $script:preferences.actionMin $script:preferences.actionMax))
$script:walkFrom = 0.0
$script:walkTo = 0.0
$script:clock = [Diagnostics.Stopwatch]::StartNew()
$script:nextBlink = 3.0
$script:doubleBlink=$false; $script:happyUntil=0.0
function Set-PetAction([string]$action) {
 if ($action -ne 'idle') { $script:quiet=$false; Wake-Pet }
 $script:action=$action; $script:actionStarted=[DateTime]::Now
 $script:nextAction=[DateTime]::Now.AddSeconds((Get-RandomRange $script:preferences.actionMin $script:preferences.actionMax))
 $script:actionDuration = if($action -eq 'idle'){0.0}else{[double]$script:preferences[$action+'Duration']}
 if ($action -eq 'walk') {
  $area=[Windows.SystemParameters]::WorkArea
  $script:walkFrom=$window.Left
  $direction=if((Get-RandomRange 0 100) -lt $script:preferences.walkRightChance){1}else{-1}
  $script:walkTo=Get-WalkTarget $window.Left $window.Width $area.Left $area.Right $direction (Get-RandomRange $script:preferences.walkMin $script:preferences.walkMax)
 }
 if ($action -ne 'idle') { $script:lastAction=$action }
 if ($null -eq $script:focusUntil) {
  $label.Text = switch ($action) { 'walk' {'码团  ·  出门溜达一下'} 'sit' {'码团  ·  坐着陪你'} 'sleep' {'码团  ·  小憩一会儿'} 'stretch' {'码团  ·  伸个懒腰'} 'wave' {'码团  ·  嗨，我在呢'} default {'码团  ·  陪你写点东西'} }
 }

}
$script:blinkStarted=-100.0; $script:blinkLength=0.1
function Update-Behavior {
 $now=[DateTime]::Now; $t=$script:clock.Elapsed.TotalSeconds
 Update-Compact $t
 if($script:quiet){$script:action='idle'}
 if($script:action -eq 'idle' -and $script:randomActions -and -not $script:quiet -and $null -eq $script:settingsWindow -and $null -eq $script:focusUntil -and $null -eq $script:drag -and -not $menu.IsOpen -and -not $window.IsMouseOver -and $now -ge $script:nextAction){Set-PetAction (Get-WeightedAction $script:preferences $script:lastAction)}
 $age=($now-$script:actionStarted).TotalSeconds
 if($script:action -ne 'idle' -and $age -ge $script:actionDuration){
  if($script:action -eq 'walk'){$window.Left=$script:walkTo}
  $finished=$script:action
  if($finished -eq 'sleep' -and $script:preferences.sleepStretch){Set-PetAction 'stretch'}else{Set-PetAction 'idle'}
  $age=0.0
 }
 $pose=Get-PetPose $script:action $age $script:actionDuration ([Math]::Abs($script:walkTo-$script:walkFrom))
 if($script:action -eq 'walk'){$window.Left=$script:walkFrom+($script:walkTo-$script:walkFrom)*$pose.progress}
 $faceMood=$script:mood
 if($t -lt $script:happyUntil -and $faceMood -notin @('worried','exhausted')){$faceMood='happy'}
 $sample=Get-SpriteSample $script:action $age $script:actionDuration ([Math]::Abs($script:walkTo-$script:walkFrom)) $pose.progress $script:compact $faceMood ($script:walkTo -lt $script:walkFrom) $script:preferences
 if($t -ge $script:nextBlink -and -not $script:quiet){
  $script:blinkStarted=$t;$script:blinkLength=(Get-RandomRange $script:preferences.blinkDurationMin $script:preferences.blinkDurationMax)/1000
  if(-not $script:doubleBlink -and (Get-RandomRange 0 100) -lt $script:preferences.doubleBlinkChance){$script:nextBlink=$t+$script:preferences.doubleBlinkGap;$script:doubleBlink=$true}
  else{$script:nextBlink=$t+(Get-RandomRange $script:preferences.blinkMin $script:preferences.blinkMax);$script:doubleBlink=$false}
 }
 $expression=switch($script:mood){'happy'{1}'worried'{2}'exhausted'{3}default{0}}
 $blinkAge=$t-$script:blinkStarted
 $closed=($blinkAge -ge 0 -and $blinkAge -lt 2*$script:blinkLength)
 if($script:action -eq 'sleep' -and $sample.frame -gt 5){$closed=$true}
 $script:sprite.SetExpression($expression,$closed)
 $breath=0.0
 if(-not $script:quiet -and $script:action -eq 'idle'){$breath=[Math]::Sin($t*2*[Math]::PI/$script:preferences.breathPeriod)*$script:preferences.breathAmount}
 $script:sprite.SetFrame($sample.key,$sample.frame,$sample.mirror,$t,$script:preferences.spriteTransition,$breath,$sample.alternate,$sample.mix)
}
$lines = @('我在。慢慢来，一起把它做好。','投喂一个好点子，我来长出代码。','正在收集你散落的灵感。','今天也要给自己留一点空白。','摸摸收到！灵感 +1。','小小一团，随叫随到。','写累了就看看远处吧。')
function Say([string]$message) {
 Wake-Pet
 $script:happyUntil=$script:clock.Elapsed.TotalSeconds+$script:preferences.happySeconds
 $speech.Text = $message
 $bubble.Visibility = 'Visible'
 if (-not $Preview -and -not $script:quiet) {
  $fade=New-Object Windows.Media.Animation.DoubleAnimation
  $fade.From=0; $fade.To=1; $fade.Duration=[TimeSpan]::FromMilliseconds(220)
  $bubble.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
 }
 $script:bubbleUntil = [DateTime]::Now.AddSeconds($script:preferences.speechSeconds)
}
function Bounce([double]$x, [double]$y) {
 foreach ($pair in @(@([Windows.Media.ScaleTransform]::ScaleXProperty,$x),@([Windows.Media.ScaleTransform]::ScaleYProperty,$y))) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.From = $pair[1]; $a.To = 1; $a.Duration = [TimeSpan]::FromSeconds($script:preferences.bounceDuration)
  $ease = New-Object Windows.Media.Animation.ElasticEase
  $ease.Oscillations = $script:preferences.bounceOscillations; $ease.Springiness = $script:preferences.bounceSpring; $ease.EasingMode = 'EaseOut'; $a.EasingFunction = $ease
  $squish.BeginAnimation($pair[0], $a)
 }
}
function Save-State {
 $script:preferences.scale=$script:scale; $script:preferences.quiet=$script:quiet; $script:preferences.topmost=$window.Topmost; $script:preferences.randomActions=$script:randomActions
 $script:preferences | ConvertTo-Json | Set-Content -LiteralPath $script:preferencesPath -Encoding UTF8
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
function Wake-Pet {
 $script:lastInteraction=[DateTime]::Now
 $script:expandedUntil=[DateTime]::Now.AddSeconds($script:preferences.expandHold)
}
function Update-Compact([double]$t) {
 $active=$pet.IsMouseOver -or $window.FindName('QuotaPanel').IsMouseOver -or $null -ne $script:drag -or $menu.IsOpen -or $null -ne $script:settingsWindow -or $script:action -ne 'idle' -or [DateTime]::Now -lt $script:bubbleUntil
 if($Smoke){$active=$script:action -ne 'idle' -or [DateTime]::Now -lt $script:bubbleUntil}
 if($active) {$script:lastInteraction=[DateTime]::Now}
 $should=$script:preferences.autoCompact -and -not $active -and [DateTime]::Now -ge $script:expandedUntil -and ([DateTime]::Now-$script:lastInteraction).TotalSeconds -ge $script:preferences.compactDelay
 $target=if($should){1.0}else{0.0}
 if($target -ne $script:compactTarget) {$script:compactFrom=$script:compact; $script:compactTarget=$target; $script:compactStarted=$t}
 $v=[Math]::Min(1.0,[Math]::Max(0.0,($t-$script:compactStarted)/$script:preferences.compactTransition)); $f=$v*$v*$v*($v*($v*6-15)+10)
 $script:compact=$script:compactFrom+($target-$script:compactFrom)*$f
 Set-CompactVisual
}
function Set-CompactVisual {
 $factor=1-(1-$script:preferences.compactScale)*$script:compact
 $pet.Width=230*$script:scale*$factor; $pet.Height=220*$script:scale*$factor
 $panel=$window.FindName('QuotaPanel')
 $panel.Opacity=1-$script:compact
 $panel.IsHitTestVisible=$script:compact -lt 0.8
 $panel.Visibility=if($script:compact -gt 0.999){'Collapsed'}else{'Visible'}
}
function Apply-Preferences {
 $script:quiet=[bool]$script:preferences.quiet; $script:randomActions=[bool]$script:preferences.randomActions
 $window.Topmost=[bool]$script:preferences.topmost; $window.Opacity=$script:preferences.opacity
 $window.FontFamily=$script:preferences.fontFamily
 foreach($n in @('FiveText','WeekText')) {$window.FindName($n).FontSize=$script:preferences.fontSize}
 Resize-Pet $script:preferences.scale
 if($null -ne $timer) {$timer.Interval=[TimeSpan]::FromSeconds(1.0/$script:preferences.fps)}
 $script:nextRefresh=[DateTime]::Now
 $script:nextBlink=$script:clock.Elapsed.TotalSeconds+(Get-RandomRange $script:preferences.blinkMin $script:preferences.blinkMax)
 Wake-Pet
}
$area = [Windows.SystemParameters]::WorkArea
$window.Left = $area.Right-300; $window.Top = $area.Bottom-450
if (-not $Preview -and -not $Smoke -and (Test-Path -LiteralPath $statePath)) {
 try {
  $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  $window.Left = [double]$saved.left; $window.Top = [double]$saved.top
  $script:quiet = [bool]$saved.quiet; $window.Topmost = [bool]$saved.topmost
  if ($null -ne $saved.randomActions) { $script:randomActions=[bool]$saved.randomActions }
  if(-not (Test-Path $script:preferencesPath)) {
   $script:preferences.quiet=$script:quiet; $script:preferences.topmost=$window.Topmost; $script:preferences.randomActions=$script:randomActions
   $script:preferences.scale=[Math]::Max(0.7,[Math]::Min(1.5,[double]$saved.scale))
  }
  Resize-Pet ([Math]::Max(0.7,[Math]::Min(1.5,[double]$saved.scale)))
 } catch { }
}
Apply-Preferences
Clamp-Position
$pet.Add_MouseEnter({Wake-Pet})
$pet.Add_MouseLeftButtonDown({
 Wake-Pet
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
  if ($window.Left-$a.Left -lt $script:preferences.edgeSnap) { $window.Left = $a.Left }
  if ($a.Right-$window.Left-$window.Width -lt $script:preferences.edgeSnap) { $window.Left = $a.Right-$window.Width }
  if ($window.Top-$a.Top -lt $script:preferences.edgeSnap) { $window.Top = $a.Top }
  if ($a.Bottom-$window.Top-$window.Height -lt $script:preferences.edgeSnap) { $window.Top = $a.Bottom-$window.Height }
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
Add-Item '设置…' { Show-PetSettings }
Add-Item '连接手机…' { Show-PetSettings '手机连接' }
Add-Item '摸摸码团' { Set-PetAction 'idle'; Say ($lines | Get-Random); Bounce 1.15 0.83 }
Add-Item '散步一会儿' { Set-PetAction 'walk' }
Add-Item '坐下陪我' { Set-PetAction 'sit' }
Add-Item '躺下休息' { Set-PetAction 'sleep' }
Add-Item '伸个懒腰' { Set-PetAction 'stretch' }
Add-Item '挥手打招呼' { Set-PetAction 'wave' }
Add-Item '开关随机待机动作' { $script:randomActions=-not $script:randomActions; Set-PetAction 'idle'; Save-State; Say $(if ($script:randomActions) {'我会自己散步，也会乖乖休息。'} else {'我就待在这里陪你。'}) }
Add-Item '开始专注（时长见设置）' { Set-PetAction 'idle'; $script:focusUntil = [DateTime]::Now.AddMinutes($script:preferences.focusMinutes); Say ('好，我陪你专注 '+$script:preferences.focusMinutes+' 分钟。') }
Add-Item '结束专注' { $script:focusUntil = $null; $label.Text = '码团  ·  陪你写点东西'; Say '休息一下，伸个懒腰。' }
Add-Item '查看 Codex 用量页面' { Start-Process 'https://chatgpt.com/codex/settings/usage' }
Add-Item '刷新 5 小时 / 一周用量' { Refresh-Usage; Say '正在更新两档用量。' }
Add-Item '安静 / 灵动模式' { $script:quiet = -not $script:quiet; Set-PetAction 'idle'; Save-State; Say $(if ($script:quiet) {'我安静陪着你。'} else {'码团又精神啦。'}) }
Add-Item '小号' { Resize-Pet 0.8; Save-State }
Add-Item '标准大小' { Resize-Pet 1; Save-State }
Add-Item '大号' { Resize-Pet 1.3; Save-State }
Add-Item '切换置顶' { $window.Topmost = -not $window.Topmost; Save-State }
Add-Item '收起码团（退出）' { $window.Close() }
$pet.ContextMenu = $menu
$menu.FontFamily='Microsoft YaHei'; $menu.FontSize=14
$menu.Add_Opened({ Set-PetAction 'idle' })
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1.0/$script:preferences.fps)
$timer.Add_Tick({
 $script:tick++
 if ($Smoke) {
  switch ($script:tick) {
   1 {Set-PetAction 'walk'; $script:smokeOrigin=$window.Left}
   80 {$script:smokeDistance=[Math]::Abs($window.Left-$script:smokeOrigin)}
   90 {Set-PetAction 'sit'} 145 {Set-PetAction 'sleep'} 200 {Set-PetAction 'stretch'} 250 {Set-PetAction 'wave'}
   300 {Set-PetAction 'idle'}
   325 {$script:lastInteraction=[DateTime]::Now.AddMinutes(-10); $script:expandedUntil=[DateTime]::MinValue; $script:bubbleUntil=[DateTime]::MinValue}
   390 {if($script:compact -lt 0.99){throw ('Idle compaction did not finish: '+$script:compact+' action='+$script:action)}; Wake-Pet}
   450 {if($script:compact -gt 0.01){throw 'Wake did not expand the pet'}; if(-not $script:tray.Visible){throw 'Tray icon is not visible'}; $script:trayExit.PerformClick(); return}
  }
 }
 if (($script:clock.Elapsed.TotalSeconds-$script:lastUsageCheck) -ge 1 -and -not $Smoke) {
  $script:lastUsageCheck=$script:clock.Elapsed.TotalSeconds
  if ([DateTime]::Now -ge $script:nextRefresh) { Refresh-Usage }
  Show-Usage
 }
 Update-Behavior
 if ([DateTime]::Now -gt $script:bubbleUntil) { $bubble.Visibility = 'Collapsed' }
 if ($null -ne $script:focusUntil) {
  $remaining = $script:focusUntil-[DateTime]::Now
  if ($remaining.TotalSeconds -le 0) { $script:focusUntil = $null; $label.Text = '码团  ·  休息时间'; Say '专注时间到啦！喝口水，看看远处。' }
  else { $label.Text = '专注陪伴  '+$remaining.ToString('mm\:ss') }
 }
})
$script:tray=$null; $script:trayMenu=$null; $script:trayIcon=$null
function Show-PetFromTray {
 Set-PetAction 'idle'; Wake-Pet
 $window.Show(); $window.WindowState='Normal'; Clamp-Position
 [void]$window.Activate()
}
function Remove-PetTray {
 if($null -ne $script:tray){$script:tray.Visible=$false; $script:tray.Dispose(); $script:tray=$null}
 if($null -ne $script:trayMenu){$script:trayMenu.Dispose(); $script:trayMenu=$null}
 if($null -ne $script:trayIcon){$script:trayIcon.Dispose(); $script:trayIcon=$null}
}
function Initialize-PetTray {
 $script:tray=New-Object System.Windows.Forms.NotifyIcon
 $iconPath=Join-Path $PSScriptRoot 'pet.ico'
 $script:trayIcon=if(Test-Path $iconPath){New-Object System.Drawing.Icon($iconPath)}else{[System.Drawing.SystemIcons]::Application.Clone()}
 $script:tray.Icon=$script:trayIcon
 $script:tray.Text='码团 · 右键设置或退出'
 $script:trayMenu=New-Object System.Windows.Forms.ContextMenuStrip
 $show=$script:trayMenu.Items.Add('显示码团')
 $show.Add_Click({Show-PetFromTray})
 $settings=$script:trayMenu.Items.Add('设置…')
 $settings.Add_Click({[void]$window.Dispatcher.BeginInvoke([Action]{Show-PetSettings})})
 $mobile=$script:trayMenu.Items.Add('连接手机…')
 $mobile.Add_Click({[void]$window.Dispatcher.BeginInvoke([Action]{Show-PetSettings '手机连接'})})
 [void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
 $script:trayExit=$script:trayMenu.Items.Add('退出码团')
 $script:trayExit.Add_Click({if($null -ne $script:settingsWindow){$script:settingsWindow.Close()}; $window.Close()})
 $script:tray.ContextMenuStrip=$script:trayMenu
 $script:tray.Add_MouseDoubleClick({if($_.Button -eq [System.Windows.Forms.MouseButtons]::Left){Show-PetFromTray}})
 $script:tray.Visible=$true
}
$window.Add_Closed({ $timer.Stop(); Stop-MobileLink; Remove-PetTray; if (-not $Preview -and -not $Smoke) { Save-State } })
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
 Set-UsageMood @{name=$PreviewMood;remaining=$null;limiting=$null}
 if ($PreviewMood -ne 'unknown') {
  $sample=switch ($PreviewMood) { 'happy' {85} 'calm' {45} 'worried' {12} 'exhausted' {0} }
  $window.FindName('FiveText').Text='5 小时  ·  剩余 '+$sample+'%'
  $window.FindName('FiveBar').Value=$sample
  $window.FindName('WeekText').Text='一周  ·  剩余 80%'
  $window.FindName('WeekBar').Value=80
 }
 if($PreviewCompact){$script:compact=1; Set-CompactVisual; $bubble.Visibility='Collapsed'}
 $sample=Get-SpriteSample $PreviewAction $PreviewAge 12 140 0.4 $script:compact $PreviewMood $false $script:preferences
 $expression=switch($PreviewMood){'happy'{1}'worried'{2}'exhausted'{3}default{0}}
 $script:sprite.SetExpression($expression,($PreviewAction -eq 'sleep'))
 $script:sprite.SetFrame($sample.key,$sample.frame,$sample.mirror,0,0,0,-1,0)
 if($PreviewSettings){Show-PetSettings}
 $window.UpdateLayout()
 $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap(280,430,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $bmp.Render($window)
 $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
 $previewName = $(if ($PreviewAction -eq 'idle') {'preview.png'} else {'preview-'+$PreviewAction+'.png'})
 if ($PreviewMood -ne 'unknown') { $previewName='preview-mood-'+$PreviewMood+'.png' }
 if($PreviewCompact){$previewName='preview-compact.png'}
 $stream = [IO.File]::Create((Join-Path $PSScriptRoot $previewName))
 $encoder.Save($stream); $stream.Dispose(); $window.Close()
} else {
 Refresh-Usage
 if(-not $Smoke -and $script:mobileConfig.autoStart){try{Start-MobileLink}catch{$script:mobileMessage=$_.Exception.Message}}
 $timer.Start()
 Say '你好，我是码团。点我摸摸，右键打开菜单。'
 try {Initialize-PetTray; [void]$window.ShowDialog()} finally {$timer.Stop(); Stop-MobileLink; Remove-PetTray}
 if ($Smoke) {
  if ($null -eq $script:smokeDistance -or $script:smokeDistance -lt 8) {throw 'Live walking did not move the desktop window'}
  if($null -ne $script:tray){throw 'Tray icon was not disposed on exit'}
  Write-Output ('PASS: live desktop displacement '+[Math]::Round($script:smokeDistance,1)+' px; idle compaction, wake expansion and tray menu exit')
 }
}
