$ErrorActionPreference='Stop'
$build=Join-Path $PSScriptRoot 'build'
$dist=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $build,$dist -Force | Out-Null
$payload=Join-Path $build 'pet.zip'
$files=@('pet.ps1','pet.ico','preferences-core.ps1','settings-ui.ps1','behavior-core.ps1','sprite-core.ps1','sprite-player.cs','assets','usage-core.ps1','read-usage.ps1','README.md','CHANGELOG.md','LICENSE') | ForEach-Object { Join-Path $PSScriptRoot $_ }
Compress-Archive -LiteralPath $files -DestinationPath $payload -Force
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path $compiler)) { $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
$output=Join-Path $dist 'Codex-Usage-Pet-v2.1.1.exe'
$arguments=@('/nologo','/target:winexe','/platform:anycpu','/optimize+',('/out:'+$output),('/resource:'+$payload+',pet.zip'),'/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll')
if (Test-Path (Join-Path $PSScriptRoot 'pet.ico')) { $arguments+=('/win32icon:'+(Join-Path $PSScriptRoot 'pet.ico')) }
$arguments+=(Join-Path $PSScriptRoot 'launcher.cs')
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'EXE build failed' }
$hash=Get-FileHash -LiteralPath $output -Algorithm SHA256
($hash.Hash.ToLower()+'  '+(Split-Path $output -Leaf)) | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Output $output
