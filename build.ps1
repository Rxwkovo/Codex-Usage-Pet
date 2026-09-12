param([switch]$SkipMobileBuild,[string]$Python='python')
$ErrorActionPreference='Stop'
$build=Join-Path $PSScriptRoot 'build'
$dist=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $build,$dist -Force | Out-Null
if(-not $SkipMobileBuild){& (Join-Path $PSScriptRoot 'mobile-sync/build.ps1') -Python $Python}
if(-not (Test-Path (Join-Path $PSScriptRoot 'mobile-sync/dist/CodexPet-Mobile-Link/CodexPet-Mobile-Link.exe'))){throw 'Missing mobile component'}
$payload=Join-Path $build 'pet.zip'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$files=@('pet.ps1','pet.ico','preferences-core.ps1','settings-ui.ps1','mobile-core.ps1','mobile-ui.ps1','behavior-core.ps1','sprite-core.ps1','sprite-player.cs','usage-core.ps1','read-usage.ps1','README.md','CHANGELOG.md','LICENSE','mobile-sync/allow-wireless.ps1') | ForEach-Object {Get-Item (Join-Path $PSScriptRoot $_)}
$files+=Get-ChildItem (Join-Path $PSScriptRoot 'assets') -Recurse -File
$files+=Get-ChildItem (Join-Path $PSScriptRoot 'mobile-sync/dist') -Recurse -File
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload}
$archive=[IO.Compression.ZipFile]::Open($payload,'Create')
try {
 foreach($file in $files){
  $relative=$file.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/')
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,'Optimal')
 }
} finally {$archive.Dispose()}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path $compiler)) { $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
$output=Join-Path $dist 'Codex-Usage-Pet-v2.2.1.exe'
$arguments=@('/nologo','/target:winexe','/platform:anycpu','/optimize+',('/out:'+$output),('/resource:'+$payload+',pet.zip'),'/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll')
if (Test-Path (Join-Path $PSScriptRoot 'pet.ico')) { $arguments+=('/win32icon:'+(Join-Path $PSScriptRoot 'pet.ico')) }
$arguments+=(Join-Path $PSScriptRoot 'launcher.cs')
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'EXE build failed' }
$hash=Get-FileHash -LiteralPath $output -Algorithm SHA256
($hash.Hash.ToLower()+'  '+(Split-Path $output -Leaf)) | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Output $output
