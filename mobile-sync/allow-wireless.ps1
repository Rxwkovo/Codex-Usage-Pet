param([Parameter(Mandatory=$true)][ipaddress]$Address,[ValidateRange(1024,65535)][int]$Port=47831,[Parameter(Mandatory=$true)][string]$Program)
$ErrorActionPreference='Stop'
$local=Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq $Address.ToString() -and $_.AddressState -eq 'Preferred'} | Select-Object -First 1
if(-not $local){throw 'The chosen address is no longer connected.'}
$b=$Address.GetAddressBytes()
if($b.Length -ne 4 -or -not ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168))){throw 'Private IPv4 required'}
$exe=(Resolve-Path -LiteralPath $Program).Path
if((Split-Path $exe -Leaf) -ne 'CodexPet-Mobile-Link.exe'){throw 'Unexpected program'}
$rule='CodexPet-Mobile-Link'
Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name $rule -DisplayName '码团 · 手机局域网同步' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -LocalAddress $Address.ToString() -RemoteAddress LocalSubnet -InterfaceAlias $local.InterfaceAlias -Program $exe -Profile Any | Out-Null
