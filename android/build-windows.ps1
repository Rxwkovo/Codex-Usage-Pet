param([switch]$Offline)
$ErrorActionPreference='Stop'
if(-not $env:JAVA_HOME){$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'}
if(-not $env:ANDROID_HOME){$env:ANDROID_HOME=Join-Path $env:LOCALAPPDATA 'Android/Sdk'}
# Gradle/JVM test classpaths can fail under non-ASCII Windows paths. Stage source only.
$stage=Join-Path $env:TEMP ('codexpet-android-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $stage | Out-Null
robocopy $PSScriptRoot $stage /E /XD build .gradle dist /XF local.properties /NFL /NDL /NJH /NJS | Out-Null
if($LASTEXITCODE -ge 8){throw 'Source copy failed'}
[IO.File]::WriteAllText((Join-Path $stage 'local.properties'),('sdk.dir='+$env:ANDROID_HOME.Replace('\','/').Replace(':','\:')))
$proxyArgs=@()
if($env:HTTPS_PROXY){$u=[Uri]$env:HTTPS_PROXY;$proxyArgs=@("-Dhttps.proxyHost=$($u.Host)","-Dhttps.proxyPort=$($u.Port)","-Dhttp.proxyHost=$($u.Host)","-Dhttp.proxyPort=$($u.Port)")}
$flags=@('--no-daemon','--console=plain')
if($Offline){$flags+='--offline'}
Push-Location $stage
try {
 & ./gradlew.bat @proxyArgs @flags assembleDebug testDebugUnitTest lintDebug
 if($LASTEXITCODE -ne 0){throw 'Android checks failed'}
 New-Item -ItemType Directory -Force "$PSScriptRoot/dist" | Out-Null
 Copy-Item "$stage/app/build/outputs/apk/debug/app-debug.apk" "$PSScriptRoot/dist/CodexPet-Android-0.1.1-preview.apk" -Force
} finally {Pop-Location}
