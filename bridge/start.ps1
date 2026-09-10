param([Parameter(Mandatory=$true)][string]$Address,[int]$Port=47831,[switch]$Reset)
$ErrorActionPreference='Stop'
$python=Get-Command python.exe -ErrorAction SilentlyContinue
if(-not $python){throw 'Install Python 3.11 or newer, then run this script again.'}
$venv=Join-Path $env:LOCALAPPDATA 'CodexUsagePet/android-bridge-env'
if(-not(Test-Path "$venv/Scripts/python.exe")){
 & $python.Source -m venv $venv
 if($LASTEXITCODE -ne 0){throw 'Failed to create bridge environment'}
}
& "$venv/Scripts/python.exe" -m pip install -r "$PSScriptRoot/requirements.txt"
if($LASTEXITCODE -ne 0){throw 'Failed to install bridge dependencies'}
$argsList=@('--host',$Address,'--port',"$Port")
if($Reset){$argsList+='--reset'}
& "$venv/Scripts/python.exe" "$PSScriptRoot/bridge.py" @argsList
