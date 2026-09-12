$ErrorActionPreference='Stop'
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$root=Split-Path $PSScriptRoot
$sandbox=Join-Path $env:TEMP ('CodexPet-read-usage-test-'+[Guid]::NewGuid().ToString('N'))
$fakeProfile=Join-Path $sandbox 'localappdata'
[void][IO.Directory]::CreateDirectory($fakeProfile)
try {
 # read-usage.ps1 publishes usage.json next to itself, so the suite runs a copy in a
 # sandbox instead of overwriting the real one the pet is currently showing.
 Copy-Item -LiteralPath (Join-Path $root 'read-usage.ps1') -Destination $sandbox
 Copy-Item -LiteralPath (Join-Path $root 'usage-core.ps1') -Destination $sandbox
 $worker=Join-Path $sandbox 'read-usage.ps1'
 $output=Join-Path $sandbox 'usage.json'
 $tempFile="$output.tmp"
 $launcher=Join-Path $sandbox 'run-without-codex.ps1'
 # Hide the Codex CLI for the child process: it is found either on PATH or under
 # %LOCALAPPDATA%\OpenAI\Codex\bin, so both are redirected at a sandbox. -DirectOnly
 # keeps the run fast (no 25s proxy retry) while exercising the same failure handling,
 # which is the part that has to leave a usable usage.json behind instead of dying.
 $launcherLines=@(
  '$env:PATH=''C:\Windows\System32'''
  ('$env:LOCALAPPDATA='''+$fakeProfile+'''')
  '$env:HTTP_PROXY=$null; $env:HTTPS_PROXY=$null; $env:ALL_PROXY=$null'
  ('& '''+$worker+''' -DirectOnly')
 )
 [IO.File]::WriteAllLines($launcher,$launcherLines,(New-Object Text.UTF8Encoding($false)))
 function Invoke-Worker {
  $process=Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$launcher+'"') -WindowStyle Hidden -PassThru -Wait
  return $process.ExitCode
 }
 function Read-UsageFile {
  Assert (Test-Path -LiteralPath $output) 'The worker must always publish usage.json'
  $raw=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
  return ($raw | ConvertFrom-Json)
 }

 # 1. No previous reading: the failure itself must be recorded, not thrown.
 Assert ((Invoke-Worker) -eq 0) 'A failed refresh must still exit 0 so the pet keeps refreshing'
 Assert (-not (Test-Path -LiteralPath $tempFile)) 'The temporary file must not survive the atomic publish'
 $first=Read-UsageFile
 foreach ($key in @('status','updatedAt','fiveHour','weekly')) {
  Assert ($null -ne $first.PSObject.Properties[$key]) ('usage.json must always carry '+$key)
 }
 Assert ($first.status -eq 'unavailable') 'An unreadable quota must be reported as unavailable'
 Assert ($null -eq $first.fiveHour -and $null -eq $first.weekly) 'An unavailable quota must not invent numbers'
 Assert ($first.failureCount -eq 1) 'The first failed refresh must start the consecutive failure count'

 # 2. A previous good reading: it must be kept as stale instead of being wiped, because
 #    the pet shows the last known numbers until they are refreshed successfully.
 [IO.File]::WriteAllText($output,'{"status":"ok","updatedAt":1234,"fiveHour":{"remaining":42,"resetsAt":5000},"weekly":{"remaining":77,"resetsAt":9000}}',(New-Object Text.UTF8Encoding($false)))
 Assert ((Invoke-Worker) -eq 0) 'A failed refresh over a cached reading must still exit 0'
 Assert (-not (Test-Path -LiteralPath $tempFile)) 'The temporary file must not survive a cached refresh'
 $cached=Read-UsageFile
 Assert ($cached.status -eq 'stale') 'A cached reading must be downgraded to stale, not deleted'
 Assert ($cached.fiveHour.remaining -eq 42 -and $cached.weekly.remaining -eq 77) 'The last known numbers must survive a failed refresh'
 Assert ($cached.updatedAt -eq 1234) 'The timestamp of the cached reading must be preserved'
 Assert ($cached.failureCount -eq 1) 'A good cached reading with no prior failure starts at one failure'
 Assert ((Invoke-Worker) -eq 0) 'A repeated failed refresh must still exit 0'
 $repeated=Read-UsageFile
 Assert ($repeated.failureCount -eq 2) 'Consecutive failures must accumulate for the UI alert threshold'

 # 3. A corrupt previous reading: it must not stop the refresh from publishing.
 [IO.File]::WriteAllText($output,'{ not json',(New-Object Text.UTF8Encoding($false)))
 Assert ((Invoke-Worker) -eq 0) 'A corrupt cached reading must not fail the refresh'
 $recovered=Read-UsageFile
 Assert ($recovered.status -eq 'unavailable') 'A corrupt cached reading must fall back to unavailable'
 Assert ($null -eq $recovered.fiveHour) 'A corrupt cached reading must not be half-parsed'
 Assert ($recovered.failureCount -eq 1) 'A corrupt cache starts a fresh failure count'
 Assert (-not (Test-Path -LiteralPath $tempFile)) 'The temporary file must not survive a corrupt publish'
 'PASS: read-usage failure paths, cached reading preservation, atomic publish'
} finally {
 if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
