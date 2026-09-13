param([string]$Python='python')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Dependencies are pinned in requirements.txt. Development and CI install them first.
& $Python -m PyInstaller --noconfirm --clean --onedir --windowed --name CodexPet-Mobile-Link --distpath (Join-Path $PSScriptRoot 'dist') --workpath (Join-Path $PSScriptRoot 'build') --specpath (Join-Path $PSScriptRoot 'build') --paths $root --copy-metadata qrcode --copy-metadata Pillow --copy-metadata PyInstaller --exclude-module numpy --exclude-module matplotlib --exclude-module tkinter --exclude-module pytest --icon (Join-Path $PSScriptRoot '../pet.ico') (Join-Path $PSScriptRoot 'desktop.py')
if($LASTEXITCODE -ne 0){throw 'Mobile service build failed'}
$pythonLicense=& $Python -c "import pathlib,sys; print(pathlib.Path(sys.base_prefix)/'LICENSE.txt')"
if(Test-Path -LiteralPath $pythonLicense){Copy-Item -LiteralPath $pythonLicense -Destination (Join-Path $PSScriptRoot 'dist/CodexPet-Mobile-Link/Python-LICENSE.txt')}
