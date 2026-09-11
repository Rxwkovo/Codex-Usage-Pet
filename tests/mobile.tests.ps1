$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'mobile-core.ps1')
function Assert($value,$label){if(-not $value){throw $label}}
$config=@{address='192.168.3.10';port=47831;inviteMinutes=10;autoStart=$false}
Assert ($null -eq (Test-MobileConfig $config)) 'Default mobile config'
foreach($address in @('127.0.0.1','169.254.2.3','0.0.0.0','8.8.8.8','::1','bad','172.32.0.1')){Assert (-not (Test-MobileAddress $address)) 'Only LAN IPv4 may be selected'}
foreach($address in @('10.0.0.1','172.16.0.1','172.31.255.1','192.168.1.20')){Assert (Test-MobileAddress $address) 'Private address should work'}
foreach($value in @('NaN',47831.5,80,65536,'x')){$bad=$config.Clone();$bad.port=$value;Assert ((Test-MobileConfig $bad) -ne $null) 'Port range and integer validation'}
foreach($value in @(0,61,1.2,'x')){$bad=$config.Clone();$bad.inviteMinutes=$value;Assert ((Test-MobileConfig $bad) -ne $null) 'Invitation lifetime validation'}
$snapshot=[pscustomobject]@{state='running';paired=1;online=0;usage=@{status='ok'}}
Assert ((Get-MobileStatusText $snapshot) -match '等待手机同步') 'Paired is not the same as connected'
$snapshot.online=1; $snapshot.usage.status='stale'
Assert ((Get-MobileStatusText $snapshot) -match '尚未更新') 'Connected but stale quota must be explicit'
Assert ((Get-MobileStatus).state -eq 'stopped') 'Disabled by default'
$script:mobileRoot=Join-Path $env:TEMP ('CodexPet-mobile-config-test-'+[Guid]::NewGuid().ToString('N'))
try {
 Save-MobileConfig $config
 $replacement=$config.Clone();$replacement.port=47832;$replacement.autoStart=$true
 Save-MobileConfig $replacement
 $script:mobileConfig=$config.Clone();Initialize-MobileLink
 Assert ($script:mobileConfig.port -eq 47832 -and $script:mobileConfig.autoStart) 'Connection config must survive atomic overwrite and restart'
}finally{
 $path=Join-Path $script:mobileRoot 'settings.json'
 if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
 if(Test-Path -LiteralPath $script:mobileRoot){Remove-Item -LiteralPath $script:mobileRoot}
}
'PASS: mobile address/port validation, disabled default, paired/online and stale status'
