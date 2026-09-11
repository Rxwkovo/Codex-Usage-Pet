function Add-MobileSettingsTab($Tabs) {
 [xml]$markup=@'
<TabItem xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Header="手机连接">
 <TabItem.Resources>
  <Style TargetType="Button">
   <Setter Property="Padding" Value="14,9"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Background" Value="#DDF3E8"/><Setter Property="Foreground" Value="#244C3D"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Surface" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="#C4EAD7"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.7"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Surface" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="TextBox"><Setter Property="Padding" Value="8,6"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#CDE1D5"/></Style>
 </TabItem.Resources>
 <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="18">
  <TextBlock Text="把码团带到手机上" FontSize="23" FontWeight="SemiBold" Margin="0,0,0,6"/>
  <TextBlock Text="电脑和手机连接同一 Wi-Fi，五小时与一周额度同步陪伴。" TextWrapping="Wrap" Foreground="#597367" Margin="0,0,0,14"/>
  <Border Background="#E6F4EC" CornerRadius="12" Padding="14" Margin="0,0,0,16"><StackPanel>
   <TextBlock x:Name="MobileStatus" Text="尚未开启手机同步" FontWeight="SemiBold" TextWrapping="Wrap"/>
   <TextBlock x:Name="MobileDetail" Foreground="#5C7467" FontSize="12" Margin="0,5,0,0" TextWrapping="Wrap" Text="仅分享额度与更新时间；电脑登录信息留在电脑上。"/>
  </StackPanel></Border>
  <TextBlock Text="1  选择电脑地址" FontWeight="SemiBold" Margin="0,0,0,8"/>
  <DockPanel><Button x:Name="MobileRefresh" DockPanel.Dock="Right" Content="刷新地址" Margin="8,0,0,0"/><ComboBox x:Name="MobileAddresses" DisplayMemberPath="label" SelectedValuePath="address" Padding="8,7"/></DockPanel>
  <Grid Margin="0,12,0,8"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="连接端口" FontSize="12"/><TextBox x:Name="MobilePort" Width="120" HorizontalAlignment="Left" Margin="0,5,0,0"/></StackPanel>
   <StackPanel Grid.Column="1"><TextBlock Text="配对码有效期（分钟）" FontSize="12"/><TextBox x:Name="MobileMinutes" Width="120" HorizontalAlignment="Left" Margin="0,5,0,0"/></StackPanel>
  </Grid>
  <CheckBox x:Name="MobileAuto" Content="下次启动码团时自动开启同步" Margin="0,6,0,14"/>
  <WrapPanel><Button x:Name="MobileStart" Content="保存并开启同步" Background="#9FE0BF"/><Button x:Name="MobileStop" Content="关闭同步"/></WrapPanel>
  <TextBlock Text="本页连接操作立即生效。关闭同步也会关闭自动开启。" FontSize="12" Foreground="#6E8176" TextWrapping="Wrap" Margin="0,0,0,20"/>
  <TextBlock Text="2  在手机完成配对" FontWeight="SemiBold" Margin="0,0,0,10"/>
  <Border BorderBrush="#D6E7DC" BorderThickness="1" Background="White" CornerRadius="12" Padding="12"><StackPanel>
   <TextBlock Text="手机码团 → 连接电脑 → 粘贴配对码，或导入保存的二维码原图。" TextWrapping="Wrap" Foreground="#526D5E"/>
   <Grid Height="230" Margin="0,8,0,8"><Image x:Name="MobileQr" Width="224" Height="224" Stretch="Uniform" RenderOptions.BitmapScalingMode="NearestNeighbor"/><TextBlock x:Name="MobileQrHint" Text="开启同步后，在这里显示配对二维码" HorizontalAlignment="Center" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="#7F9789"/></Grid>
   <TextBlock x:Name="MobileExpiry" Text="配对码限时、一次有效。已配对的手机不受续期影响。" TextAlignment="Center" Foreground="#60796A" FontSize="12" Margin="0,0,0,10"/>
   <WrapPanel HorizontalAlignment="Center"><Button x:Name="MobileCopy" Content="复制配对码"/><Button x:Name="MobileSaveQr" Content="保存二维码…"/><Button x:Name="MobileRenew" Content="生成新配对码"/></WrapPanel>
  </StackPanel></Border>
  <TextBlock Text="3  连接状态与管理" FontWeight="SemiBold" Margin="0,20,0,8"/>
  <TextBlock x:Name="MobileLastSeen" Text="手机通常每分钟同步一次。关闭电脑或离开局域网后，手机会提示数据过期。" TextWrapping="Wrap" Foreground="#60796A" Margin="0,0,0,10"/>
  <WrapPanel><Button x:Name="MobileFirewall" Content="允许局域网连接…"/><Button x:Name="MobileRevoke" Content="解除全部手机配对" Background="#F6E7E0"/></WrapPanel>
  <TextBlock Text="连接不通时：确认同一 Wi-Fi，退出旧的独立同步端，允许局域网连接。旧 USB 配对可在新版手机端切换为这里的无线地址。" TextWrapping="Wrap" FontSize="12" Foreground="#6E8176"/>
 </StackPanel></ScrollViewer>
</TabItem>
'@
 $tab=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $markup))
 $script:mobileControls=@{tab=$tab;qrStamp=''}
 foreach($name in @('Status','Detail','Addresses','Port','Minutes','Auto','Start','Stop','Refresh','Qr','QrHint','Expiry','Copy','SaveQr','Renew','LastSeen','Firewall','Revoke')){$script:mobileControls[$name]=$tab.FindName('Mobile'+$name)}
 $script:mobileControls.Port.Text=[string]$script:mobileConfig.port
 $script:mobileControls.Minutes.Text=[string]$script:mobileConfig.inviteMinutes
 $script:mobileControls.Auto.IsChecked=[bool]$script:mobileConfig.autoStart
 Update-MobileAddressList
 $script:mobileControls.Refresh.Add_Click({Update-MobileAddressList})
 $script:mobileControls.Start.Add_Click({
  try {
   $c=$script:mobileControls
   $candidate=@{address=[string]$c.Addresses.SelectedValue;port=$c.Port.Text;inviteMinutes=$c.Minutes.Text;autoStart=[bool]$c.Auto.IsChecked}
   $errorText=Test-MobileConfig $candidate
   if($errorText){throw $errorText}
   $currentAddresses=@(Get-MobileAddresses)
   if($candidate.address -notin @($currentAddresses | ForEach-Object {$_.address})){throw '所选地址已经断开，请刷新地址。'}
   Save-MobileConfig $candidate; Start-MobileLink
  } catch {$script:mobileMessage=$_.Exception.Message}
  Update-MobileSettings
 })
 $script:mobileControls.Stop.Add_Click({
  Stop-MobileLink; $script:mobileConfig.autoStart=$false; $script:mobileControls.Auto.IsChecked=$false
  if(-not (Test-MobileConfig $script:mobileConfig)){Save-MobileConfig $script:mobileConfig}
  Update-MobileSettings
 })
 $script:mobileControls.Renew.Add_Click({Send-MobileCommand 'renew'})
 $script:mobileControls.Copy.Add_Click({
  if(Test-MobileInvite){[Windows.Clipboard]::SetText([IO.File]::ReadAllText((Join-Path $script:mobileRoot 'pairing.txt'))); $script:mobileControls.Expiry.Text='配对码已复制，请在手机码团中粘贴。'}
 })
 $script:mobileControls.SaveQr.Add_Click({
  if(Test-MobileInvite){
   $saveQr=New-Object Microsoft.Win32.SaveFileDialog; $saveQr.FileName='码团-手机配对.png'; $saveQr.Filter='PNG 图片|*.png'
   if($saveQr.ShowDialog($script:settingsWindow)){
    if(Test-MobileInvite){[IO.File]::Copy((Join-Path $script:mobileRoot 'pairing.png'),$saveQr.FileName,$true)}
   }
  }
 })
 $script:mobileControls.Revoke.Add_Click({
  if([Windows.MessageBox]::Show($script:settingsWindow,'解除后，所有手机都需要重新配对才能同步。','解除手机配对','YesNo','Question') -eq 'Yes'){Send-MobileCommand 'revoke'}
 })
 $script:mobileControls.Firewall.Add_Click({
  try {
   if((Get-MobileStatus).state -ne 'running'){throw '请先开启同步。'}
   $scriptPath=Join-Path $PSScriptRoot 'mobile-sync/allow-wireless.ps1'
   $argsText='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$scriptPath+'" -Address '+$script:mobileConfig.address+' -Port '+$script:mobileConfig.port+' -Program "'+(Join-Path $PSScriptRoot 'mobile-sync/dist/CodexPet-Mobile-Link/CodexPet-Mobile-Link.exe')+'"'
   $script:mobileFirewallProcess=Start-Process powershell.exe -ArgumentList $argsText -Verb RunAs -WindowStyle Hidden -PassThru
   $script:mobileControls.LastSeen.Text='请完成 Windows 管理员授权；规则只允许当前网卡的局域网设备访问。'
  } catch {[void][Windows.MessageBox]::Show($script:settingsWindow,('未能设置局域网访问：'+$_.Exception.Message),'手机连接')}
 })
 [void]$Tabs.Items.Add($tab)
 $script:mobileUiTimer=New-Object Windows.Threading.DispatcherTimer
 $script:mobileUiTimer.Interval=[TimeSpan]::FromSeconds(1)
 $script:mobileUiTimer.Add_Tick({Update-MobileSettings})
 $script:mobileUiTimer.Start()
 Update-MobileSettings
 return $tab
}
function Update-MobileAddressList {
 $c=$script:mobileControls
 $selected=[string]$c.Addresses.SelectedValue
 if(-not $selected){$selected=$script:mobileConfig.address}
 $items=@(Get-MobileAddresses)
 $c.Addresses.ItemsSource=$items
 if($selected -in @($items | ForEach-Object {$_.address})){$c.Addresses.SelectedValue=$selected}elseif($items.Count -gt 0){$c.Addresses.SelectedIndex=0}
 if($items.Count -eq 0){$c.Detail.Text='未找到已连接的局域网网卡。请先将电脑连接到手机所在的 Wi-Fi。'}
}
function Test-MobileInvite {
 $s=Get-MobileStatus
 return ($s.state -eq 'running' -and $s.qr -and $s.expires -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -and (Test-Path -LiteralPath (Join-Path $script:mobileRoot 'pairing.txt')) -and (Test-Path -LiteralPath (Join-Path $script:mobileRoot 'pairing.png')))
}
function Update-MobileSettings {
 if($null -eq $script:mobileControls){return}
 $c=$script:mobileControls; $s=Get-MobileStatus; $running=$s.state -eq 'running'
 $c.Status.Text=Get-MobileStatusText $s
 $c.Stop.IsEnabled=$running -or $s.state -eq 'starting' -or ($null -ne $script:mobileProcess -and -not $script:mobileProcess.HasExited)
 $c.Start.IsEnabled=$s.state -ne 'starting'
 $c.Start.Content=$(if($running){'保存并重新开启'}else{'保存并开启同步'})
 $c.Renew.IsEnabled=$running; $c.Firewall.IsEnabled=$running; $c.Revoke.IsEnabled=$running -and $s.paired -gt 0
 if($running){$c.Detail.Text=($s.url+' · 已配对 '+$s.paired+' 台')}
 $valid=Test-MobileInvite
 $c.Copy.IsEnabled=$valid; $c.SaveQr.IsEnabled=$valid
 if($valid){
  $path=Join-Path $script:mobileRoot 'pairing.png'
  $stamp=(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
  if($c.qrStamp -ne $stamp){
   try {
    $image=New-Object Windows.Media.Imaging.BitmapImage
    $stream=New-Object IO.MemoryStream(,[IO.File]::ReadAllBytes($path))
    try {$image.BeginInit(); $image.CacheOption='OnLoad'; $image.StreamSource=$stream; $image.EndInit(); $image.Freeze()} finally {$stream.Dispose()}
    $c.Qr.Source=$image; $c.qrStamp=$stamp
   } catch { }
  }
  $c.QrHint.Visibility='Collapsed'
  $seconds=[Math]::Max(0,$s.expires-[DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
  $c.Expiry.Text=('剩余 '+[Math]::Floor($seconds/60)+' 分 '+($seconds%60)+' 秒 · 仅限一次新配对')
 }else{
  $c.Qr.Source=$null; $c.qrStamp=''; $c.QrHint.Visibility='Visible'
  $c.QrHint.Text=$(if($running){'配对码已使用或失效，可生成新配对码。'}else{'开启同步后，在这里显示配对二维码'})
  $c.Expiry.Text='生成新配对码不会解除已有手机。'
 }
 if($s.lastSeen -gt 0){$c.LastSeen.Text='最近收到手机请求：'+[DateTimeOffset]::FromUnixTimeSeconds($s.lastSeen).LocalDateTime.ToString('HH:mm:ss')+'。手机通常每分钟同步一次。'}
 if($null -ne $script:mobileFirewallProcess -and $script:mobileFirewallProcess.HasExited){
  $c.LastSeen.Text=$(if($script:mobileFirewallProcess.ExitCode -eq 0){'已允许当前网卡的局域网连接，请在手机点立即同步。'}else{'局域网放行未成功。请检查管理员授权与网卡状态。'})
  $script:mobileFirewallProcess.Dispose(); $script:mobileFirewallProcess=$null
 }
}
