# Run in an Administrator PowerShell. Scope is this computer's chosen LAN IP,
# this TCP port, and the directly attached subnet; no router or VPN changes.
param(
 [Parameter(Mandatory=$true)][ipaddress]$Address,
 [ValidateRange(1,65535)][int]$Port=47831,
 [string]$Program=(Join-Path $PSScriptRoot 'CodexPet-Sync-Bridge.exe')
)
$ErrorActionPreference='Stop'
$local=Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $Address.ToString() -and $_.AddressState -eq 'Preferred' } | Select-Object -First 1
if(-not $local){throw 'The selected LAN address is not active on this computer.'}
$bytes=$Address.GetAddressBytes()
if(-not ($bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168))){throw 'Use a private LAN IPv4 address.'}
$exe=(Resolve-Path -LiteralPath $Program -ErrorAction Stop).Path
$ruleName="CodexPet-Wireless-$Port"
Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name $ruleName -DisplayName "Codex Pet wireless sync ($Port)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -LocalAddress $Address.ToString() -RemoteAddress LocalSubnet -InterfaceAlias $local.InterfaceAlias -Program $exe -Profile Any -ErrorAction Stop | Out-Null
Write-Host 'Wireless sync allowed only for this program, from the local subnet on the selected interface.'
