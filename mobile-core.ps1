$script:mobileProcess=$null
$script:mobileSession=''
$script:mobileMessage='尚未开启手机同步'
$script:mobileRoot=Join-Path $env:LOCALAPPDATA 'CodexUsagePet/mobile-link'
$script:mobileState=Join-Path $env:LOCALAPPDATA 'CodexUsagePet/android-bridge'
$script:mobileConfig=@{address='';port=47831;inviteMinutes=10;autoStart=$false}

function Test-MobileAddress([string]$Address) {
 $ip=$null
 if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){return $false}
 $b=$ip.GetAddressBytes()
 return ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168))
}
function Get-MobileAddresses {
 $items=@()
 foreach($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
  if($nic.OperationalStatus -ne 'Up' -or $nic.NetworkInterfaceType -notin @('Ethernet','Wireless80211')){continue}
  if(($nic.Description+' '+$nic.Name) -match '(?i)virtual|vpn|tap-|tun|wireguard|tailscale|zerotier|hyper-v|vmware|loopback'){continue}
  foreach($entry in $nic.GetIPProperties().UnicastAddresses) {
   $ip=$entry.Address.ToString()
   if(Test-MobileAddress $ip) {
    $wifi=$nic.NetworkInterfaceType -eq 'Wireless80211'
    $items+=[pscustomobject]@{address=$ip;label=($ip+'  ·  '+$(if($wifi){'Wi-Fi'}else{$nic.Name}));wifi=$wifi}
   }
  }
 }
 return @($items | Sort-Object @{Expression='wifi';Descending=$true},address)
}
function Test-MobileConfig($Config) {
 if(-not (Test-MobileAddress ([string]$Config.address))){return '请先选择电脑当前已连接的局域网地址。'}
 $port=0; $minutes=0
 if(-not [int]::TryParse([string]$Config.port,[ref]$port) -or $port -lt 1024 -or $port -gt 65535){return '连接端口请输入 1024–65535 之间的整数。'}
 if(-not [int]::TryParse([string]$Config.inviteMinutes,[ref]$minutes) -or $minutes -lt 1 -or $minutes -gt 60){return '配对码有效期请输入 1–60 分钟之间的整数。'}
 return $null
}
function Protect-MobileDirectory([string]$Path) {
 [void][IO.Directory]::CreateDirectory($Path)
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
 $acl.AddAccessRule($rule)
 [IO.Directory]::SetAccessControl($Path,$acl)
}
function Write-MobileJson([string]$Path,$Value) {
 $temp=$Path+'.tmp'
 [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
}
function Initialize-MobileLink {
 $path=Join-Path $script:mobileRoot 'settings.json'
 if(Test-Path -LiteralPath $path) {
  try {
   $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
   $candidate=$script:mobileConfig.Clone()
   foreach($k in @($candidate.Keys)){if($null -ne $saved.$k){$candidate[$k]=$saved.$k}}
   if(-not (Test-MobileConfig $candidate)){$script:mobileConfig=$candidate}
  } catch { }
 }
}
function Save-MobileConfig($Candidate) {
 $errorText=Test-MobileConfig $Candidate
 if($errorText){throw $errorText}
 Protect-MobileDirectory $script:mobileRoot
 $script:mobileConfig=@{address=[string]$Candidate.address;port=[int]$Candidate.port;inviteMinutes=[int]$Candidate.inviteMinutes;autoStart=[bool]$Candidate.autoStart}
 Write-MobileJson (Join-Path $script:mobileRoot 'settings.json') $script:mobileConfig
}
function Get-MobileStatus {
 $alive=$null -ne $script:mobileProcess -and -not $script:mobileProcess.HasExited
 $path=Join-Path $script:mobileRoot 'status.json'
 if($script:mobileSession -and (Test-Path -LiteralPath $path)) {
  try {
   $status=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
   if($status.session -eq $script:mobileSession) {
    if($status.state -eq 'running' -and -not $alive){return [pscustomobject]@{state='error';error='service_stopped';qr=$false}}
    elseif($status.state -eq 'running' -and [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-$status.updatedAt -gt 10){return [pscustomobject]@{state='error';error='service_unresponsive';qr=$false}}
    return $status
   }
  } catch { }
 }
 if($alive){return [pscustomobject]@{state='starting';qr=$false}}
 if($null -ne $script:mobileProcess){return [pscustomobject]@{state='error';error='startup_failed';qr=$false}}
 return [pscustomobject]@{state='stopped';qr=$false}
}
function Send-MobileCommand([string]$Action) {
 if($Action -notin @('renew','revoke','stop')){throw 'Invalid local command'}
 if(-not $script:mobileSession -or $null -eq $script:mobileProcess -or $script:mobileProcess.HasExited){return}
 $path=Join-Path $script:mobileRoot ('command-'+[DateTime]::UtcNow.Ticks+'-'+[Guid]::NewGuid().ToString('N')+'.json')
 Write-MobileJson $path @{session=$script:mobileSession;action=$Action}
}
function Stop-MobileLink {
 if($null -ne $script:mobileProcess) {
  if(-not $script:mobileProcess.HasExited) {
   Send-MobileCommand 'stop'
   if(-not $script:mobileProcess.WaitForExit(2500)){$script:mobileProcess.Kill(); [void]$script:mobileProcess.WaitForExit(1000)}
  }
  $script:mobileProcess.Dispose(); $script:mobileProcess=$null
 }
 $script:mobileMessage='同步已关闭，手机会保留上次数据并提示过期。'
}
function Start-MobileLink {
 $errorText=Test-MobileConfig $script:mobileConfig
 if($errorText){throw $errorText}
 $active=@(Get-MobileAddresses)
 if($script:mobileConfig.address -notin @($active | ForEach-Object {$_.address})){throw '所选网卡地址已断开。请连接 Wi-Fi，刷新地址后重试。'}
 $exe=Join-Path $PSScriptRoot 'mobile-sync/dist/CodexPet-Mobile-Link/CodexPet-Mobile-Link.exe'
 if(-not (Test-Path -LiteralPath $exe)){throw '缺少手机连接组件，请重新下载完整 EXE。'}
 Stop-MobileLink
 Protect-MobileDirectory $script:mobileRoot
 $script:mobileSession=[Guid]::NewGuid().ToString('N')
 $argsText='--host '+$script:mobileConfig.address+' --port '+$script:mobileConfig.port+' --invite-minutes '+$script:mobileConfig.inviteMinutes+' --owner '+$PID+' --session '+$script:mobileSession+' --state "'+$script:mobileState+'" --control "'+$script:mobileRoot+'" --usage "'+(Join-Path $PSScriptRoot 'usage.json')+'"'
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$exe; $info.Arguments=$argsText; $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WindowStyle='Hidden'
 $script:mobileProcess=[Diagnostics.Process]::Start($info)
 $script:mobileMessage='正在开启加密同步…'
}
function Get-MobileStatusText($Status) {
 switch($Status.state) {
  'running' {
   if($Status.online -gt 0){return ('已连接 '+$Status.online+' 台手机 · '+$(if($Status.usage.status -eq 'ok'){'额度已更新'}else{'电脑额度尚未更新'}))}
   if($Status.paired -gt 0){return ('已配对 '+$Status.paired+' 台 · 等待手机同步')}
   return '同步已开启 · 等待首次配对'
  }
  'starting' {return '正在开启加密同步…'}
  'error' {
   return $(switch($Status.error){
    'address_in_use' {'此地址的端口已被占用，请先退出独立同步端或更换端口。'}
    'already_running' {'已有桌面同步服务在运行，请先退出另一个码团。'}
    'address_unavailable' {'当前网卡地址已失效，请刷新地址。'}
    'service_unresponsive' {'同步服务未响应，请关闭后重新开启。'}
    'service_stopped' {'同步服务已意外停止，请重新开启。'}
    default {'同步未能启动，请检查网卡连接及文件权限，再尝试开启。'}
   })
  }
  default {return $script:mobileMessage}
 }
}
