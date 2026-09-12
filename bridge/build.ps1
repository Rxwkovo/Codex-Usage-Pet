param([string]$Python='python')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dist=Join-Path $PSScriptRoot 'dist'
$work=Join-Path $PSScriptRoot 'build'
& $Python -m PyInstaller --noconfirm --clean --onefile --console --name CodexPet-Sync-Bridge `
 --distpath $dist --workpath $work --specpath $work `
 --copy-metadata qrcode --copy-metadata Pillow --copy-metadata PyInstaller `
 --exclude-module numpy --exclude-module matplotlib --exclude-module tkinter --exclude-module pytest `
 --icon (Join-Path $root 'pet.ico') `
 --add-data ((Join-Path $root 'read-usage.ps1')+';.') `
 --add-data ((Join-Path $root 'usage-core.ps1')+';.') `
 (Join-Path $PSScriptRoot 'bridge.py')
if($LASTEXITCODE -ne 0){throw 'Standalone bridge build failed'}
$pythonLicense=& $Python -c "import pathlib,sys; print(pathlib.Path(sys.base_prefix)/'LICENSE.txt')"
if(Test-Path -LiteralPath $pythonLicense){Copy-Item -LiteralPath $pythonLicense -Destination (Join-Path $dist 'Python-LICENSE.txt') -Force}
Write-Output (Join-Path $dist 'CodexPet-Sync-Bridge.exe')
