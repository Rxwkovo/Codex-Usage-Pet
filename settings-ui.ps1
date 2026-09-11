function Show-PetSettings([string]$SelectTab='') {
 if($null -ne $script:settingsWindow) {if($SelectTab -eq '手机连接' -and $null -ne $script:mobileTab){$script:settingsTabs.SelectedItem=$script:mobileTab}; $script:settingsWindow.Activate(); return}
 Wake-Pet
 $dialog=New-Object Windows.Window
 $script:settingsWindow=$dialog
 $dialog.Title='码团设置'; $dialog.Width=650; $dialog.Height=720; $dialog.MinWidth=560; $dialog.MinHeight=480
 $dialog.WindowStartupLocation='CenterScreen'; $dialog.FontFamily='Microsoft YaHei UI'; $dialog.FontSize=14
 $dialog.Background='#F4F9F6'; $dialog.Foreground='#243E35'
 $root=New-Object Windows.Controls.DockPanel; $root.Margin='22'; $dialog.Content=$root
 $header=New-Object Windows.Controls.TextBlock; $header.Text="让码团按你的节奏生活`n保存后立即生效。随机动作按上一段动作结束后计时。"; $header.FontSize=15; $header.Margin='0,0,0,18'
 [Windows.Controls.DockPanel]::SetDock($header,'Top'); [void]$root.Children.Add($header)
 $footer=New-Object Windows.Controls.StackPanel; $footer.Orientation='Horizontal'; $footer.HorizontalAlignment='Right'; $footer.Margin='0,16,0,0'
 [Windows.Controls.DockPanel]::SetDock($footer,'Bottom'); [void]$root.Children.Add($footer)
 $reset=New-Object Windows.Controls.Button; $reset.Content='恢复默认'; $reset.Padding='14,8'; $reset.Margin='0,0,12,0'; [void]$footer.Children.Add($reset)
 $cancel=New-Object Windows.Controls.Button; $cancel.Content='取消'; $cancel.Padding='14,8'; $cancel.Margin='0,0,12,0'; [void]$footer.Children.Add($cancel)
 $save=New-Object Windows.Controls.Button; $save.Content='保存并应用'; $save.Padding='18,8'; $save.Background='#B5EBD1'; [void]$footer.Children.Add($save)
 $tabs=New-Object Windows.Controls.TabControl; $script:settingsTabs=$tabs; [void]$root.Children.Add($tabs)
 $fields=@{}; $groups=@{}
 foreach($s in (Get-PreferenceSchema)) {
  if(-not $groups.ContainsKey($s.group)) {
   $tab=New-Object Windows.Controls.TabItem; $tab.Header=$s.group
   $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $tab.Content=$scroll
   $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='18'; $scroll.Content=$panel; $groups[$s.group]=$panel
   [void]$tabs.Items.Add($tab)
  }
  $row=New-Object Windows.Controls.DockPanel; $row.Margin='0,0,0,14'
  if($s.type -eq 'bool') {
   $field=New-Object Windows.Controls.CheckBox; $field.Content=$s.label; $field.IsChecked=[bool]$script:preferences[$s.key]; [void]$row.Children.Add($field)
  } else {
   $field=New-Object Windows.Controls.TextBox; $field.Width=110; $field.Padding='8,5'; $field.Text=[string]$script:preferences[$s.key]
   $field.ToolTip=('范围：'+$s.min+' – '+$s.max); [Windows.Controls.DockPanel]::SetDock($field,'Right'); [void]$row.Children.Add($field)
   $name=New-Object Windows.Controls.TextBlock; $name.Text=$s.label; $name.VerticalAlignment='Center'; [void]$row.Children.Add($name)
  }
  $fields[$s.key]=$field; [void]$groups[$s.group].Children.Add($row)
 }
 $script:mobileTab=Add-MobileSettingsTab $tabs
 if($SelectTab -eq '手机连接'){$tabs.SelectedItem=$script:mobileTab}
 $font=New-Object Windows.Controls.ComboBox; $font.Margin='0,8,0,12'
 foreach($f in @('Microsoft YaHei UI','Microsoft YaHei','Segoe UI','SimHei')) {[void]$font.Items.Add($f)}
 $font.SelectedItem=$script:preferences.fontFamily
 $tabs.Add_SelectionChanged({
  if($tabs.SelectedItem -eq $script:mobileTab){
   $reset.Visibility='Collapsed';$save.Visibility='Collapsed';$cancel.Content='完成'
   $header.Text="手机连接与配对`n本页操作立即生效，关闭窗口后同步会继续运行。"
  }else{
   $reset.Visibility='Visible';$save.Visibility='Visible';$cancel.Content='取消'
   $header.Text="让码团按你的节奏生活`n保存后立即生效。随机动作按上一段动作结束后计时。"
  }
 })
 if($SelectTab -eq '手机连接'){$reset.Visibility='Collapsed';$save.Visibility='Collapsed';$cancel.Content='完成';$header.Text="手机连接与配对`n本页操作立即生效，关闭窗口后同步会继续运行。"}
 $fontLabel=New-Object Windows.Controls.TextBlock; $fontLabel.Text='字体'; [void]$groups['外观'].Children.Add($fontLabel); [void]$groups['外观'].Children.Add($font)
 $reset.Add_Click({$defaults=Get-DefaultPreferences; foreach($s in (Get-PreferenceSchema)){if($s.type -eq 'bool'){$fields[$s.key].IsChecked=$defaults[$s.key]}else{$fields[$s.key].Text=[string]$defaults[$s.key]}}; $font.SelectedItem=$defaults.fontFamily})
 $cancel.Add_Click({$dialog.Close()})
 $save.Add_Click({
  $candidate=@{fontFamily=[string]$font.SelectedItem}
  foreach($s in (Get-PreferenceSchema)) {if($s.type -eq 'bool'){$candidate[$s.key]=[bool]$fields[$s.key].IsChecked}else{$candidate[$s.key]=$fields[$s.key].Text}}
  $errorText=Test-Preferences $candidate
  if($errorText){[void][Windows.MessageBox]::Show($dialog,$errorText,'请检查设置');return}
  foreach($s in (Get-PreferenceSchema)){if($s.type -eq 'number'){$candidate[$s.key]=[double]$candidate[$s.key]}}
  try {
   $candidate | ConvertTo-Json | Set-Content -LiteralPath $script:preferencesPath -Encoding UTF8
   $script:preferences=$candidate; Apply-Preferences; Save-State; $dialog.Close()
  } catch {[void][Windows.MessageBox]::Show($dialog,('设置保存失败：'+$_.Exception.Message),'码团')}
 })
 if($PreviewSettings) {
  $dialog.Add_ContentRendered({
   $dialog.UpdateLayout()
   $bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap(650,720,96,96,[Windows.Media.PixelFormats]::Pbgra32)
   $bmp.Render($dialog)
   $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
   $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
   $stream=[IO.File]::Create((Join-Path $PSScriptRoot 'preview-settings.png'))
   try {$encoder.Save($stream)} finally {$stream.Dispose()}
   $dialog.Close()
  })
 }
 try {[void]$dialog.ShowDialog()} finally {if($null -ne $script:mobileUiTimer){$script:mobileUiTimer.Stop();$script:mobileUiTimer=$null};$script:mobileControls=$null;$script:mobileTab=$null;$script:settingsTabs=$null;$script:settingsWindow=$null; Wake-Pet}
}
