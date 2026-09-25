$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'usage-core.ps1')
. (Join-Path (Split-Path $PSScriptRoot) 'preferences-core.ps1')
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
$policyPreferences=Get-DefaultPreferences
$policyPreferences.refreshSeconds=300.5;$policyPreferences.staleSeconds=360.5;$policyPreferences.happyThreshold=80;$policyPreferences.worriedThreshold=20
$policyArguments=Get-MobilePolicyArguments $policyPreferences
foreach($expected in @('--refresh-seconds 300.5','--stale-seconds 360.5','--happy-threshold 80','--worried-threshold 20')){Assert ($policyArguments.Contains($expected)) 'Validated desktop policy must enter the mobile service command line without rounding'}
$script:mobileRoot=Join-Path $env:TEMP ('CodexPet-mobile-config-test-'+[Guid]::NewGuid().ToString('N'))
[void](Protect-MobileDirectory $script:mobileRoot)
try {
 # The Get-MobileStatus state machine. The suite never used to reach it: with an empty
 # $script:mobileSession the function short-circuits, so deleting that whole branch kept
 # every assertion green - and that branch is what tells "service stopped" apart from
 # "service still working", and what stops a stuck start from disabling the UI forever.
 $statusPath=Join-Path $script:mobileRoot 'status.json'
 function Write-Status($value){[IO.File]::WriteAllText($statusPath,($value|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
 $script:mobileSession='session-under-test'
 $script:mobileProcess=[pscustomobject]@{HasExited=$false}
 $script:mobileStartedAt=[DateTime]::UtcNow
 Write-Status @{session=$script:mobileSession;state='running';updatedAt=$now;qr=$true;expires=$now+600;paired=1;online=1;lastSeen=$now}
 Assert ((Get-MobileStatus).state -eq 'running') 'A fresh running status is reported as running'
 Write-Status @{session=$script:mobileSession;state='running';updatedAt=$now-60;qr=$false}
 Assert ((Get-MobileStatus).error -eq 'service_unresponsive') 'A stale heartbeat must not look running'
 $script:mobileProcess=[pscustomobject]@{HasExited=$true}
 Write-Status @{session=$script:mobileSession;state='running';updatedAt=$now;qr=$false}
 Assert ((Get-MobileStatus).error -eq 'service_stopped') 'A dead process must not look running'
 $script:mobileProcess=[pscustomobject]@{HasExited=$false}
 Write-Status @{session='another-session';state='running';updatedAt=$now;qr=$false}
 Assert ((Get-MobileStatus).state -eq 'starting') 'A status from another session must be ignored'
 $script:mobileStartedAt=[DateTime]::UtcNow.AddSeconds(-60)
 Assert ((Get-MobileStatus).error -eq 'startup_failed') 'A stuck starting state must time out instead of disabling the UI forever'
 $script:mobileStartedAt=[DateTime]::UtcNow
 [IO.File]::WriteAllText($statusPath,'{ not json',(New-Object Text.UTF8Encoding($false)))
 Assert ((Get-MobileStatus).state -eq 'starting') 'A corrupt status file must fall back safely'
 Remove-Item -LiteralPath $statusPath -Force

 Save-MobileConfig $config
 $replacement=$config.Clone();$replacement.port=47832;$replacement.autoStart=$true
 Save-MobileConfig $replacement
 $script:mobileConfig=$config.Clone();Initialize-MobileLink
 Assert ($script:mobileConfig.port -eq 47832 -and $script:mobileConfig.autoStart) 'Connection config must survive atomic overwrite and restart'
}finally{
 if(Test-Path -LiteralPath $script:mobileRoot){Remove-Item -LiteralPath $script:mobileRoot -Recurse -Force}
}
'PASS: mobile address/port validation, disabled default, status state machine, config persistence'
