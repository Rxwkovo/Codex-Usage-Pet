param([switch]$DirectOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'usage-core.ps1')
$outputPath = Join-Path $PSScriptRoot 'usage.json'
function Read-OnlineUsage([bool]$direct) {
 $process = $null; $started = $false
 try {
 $codex = Get-Command codex.exe -ErrorAction SilentlyContinue
 if ($null -eq $codex) {
  $codex = Get-ChildItem -Path "$env:LOCALAPPDATA/OpenAI/Codex/bin/*/codex.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $exe = $codex.FullName
 } else { $exe = $codex.Source }
 if (-not $exe) { throw 'Codex CLI unavailable' }
 $info = New-Object Diagnostics.ProcessStartInfo
 $info.FileName = $exe; $info.Arguments = 'app-server'
 $info.UseShellExecute=$false; $info.CreateNoWindow=$true
 $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
 if ($direct) {
  foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')) { $info.EnvironmentVariables.Remove($key) }
  $info.EnvironmentVariables['NO_PROXY']='*'
 } elseif (-not $info.EnvironmentVariables['HTTPS_PROXY']) {
  # Honor the Windows proxy setting when Explorer did not inherit proxy variables.
  $destination = [Uri]'https://chatgpt.com'
  $proxy = [Net.WebRequest]::GetSystemWebProxy().GetProxy($destination)
  if ($proxy -and $proxy.AbsoluteUri -ne $destination.AbsoluteUri) { $info.EnvironmentVariables['HTTPS_PROXY']=$proxy.AbsoluteUri }
 }
 $process = New-Object Diagnostics.Process
 $process.StartInfo=$info; [void]$process.Start(); $started=$true
 $stderr = $process.StandardError.ReadToEndAsync()
 $process.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_pet","title":"Codex Pet","version":"1.0.0"}}}')
 $deadline = [DateTime]::UtcNow.AddSeconds($(if ($direct) {12} else {25}))
 $pending = $process.StandardOutput.ReadLineAsync()
 $result = $null
 while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
  if (-not $pending.IsCompleted) { Start-Sleep -Milliseconds 50; continue }
  $line = $pending.Result
  if ($null -eq $line) { break }
  $message = $line | ConvertFrom-Json
  if ($message.id -eq 1) {
   if ($message.error) { throw 'Initialization failed' }
   $process.StandardInput.WriteLine('{"method":"initialized","params":{}}')
   $process.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":{}}')
  }
  if ($message.id -eq 2) {
   if ($message.error) { throw 'Sign in to Codex with ChatGPT and retry' }
   $result = Convert-Usage $message.result
   break
  }
  $pending = $process.StandardOutput.ReadLineAsync()
 }
 if ($null -eq $result) {
  # Distinguish "the CLI died" from "the CLI went quiet": both used to report
  # "Usage request timed out", which sent you looking for a network problem.
  if ($started -and $process.HasExited) {
   $detail = ''
   if ($null -ne $stderr -and $stderr.IsCompleted) {
    $detail = ([string]$stderr.Result).Trim()
    if ($detail.Length -gt 200) { $detail = $detail.Substring(0,200) }
   }
   throw ('Codex CLI exited with code '+$process.ExitCode+' before returning usage'+$(if($detail){': '+$detail}else{''}))
  }
  throw 'Usage request timed out'
 }
 $result.route = $(if ($direct) {'direct'} else {'system'})
 return $result
 } finally {
  if ($null -ne $process) {
   # HasExited throws when no process is associated, so only touch it after a
   # successful Start; otherwise a failed launch replaced its own error message
   # with "No process is associated with this object".
   if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit(2000) | Out-Null }
   $process.Dispose()
  }
 }
}
try {
 try { $result = Read-OnlineUsage $true } catch {
  if ($DirectOnly) { throw }
  $result = Read-OnlineUsage $false
 }
} catch {
 $result = @{status='unavailable';updatedAt=0;fiveHour=$null;weekly=$null}
 if (Test-Path -LiteralPath $outputPath) {
  try { $cached = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json; $cached.status='stale'; $result=$cached } catch { }
 }
}
$temp = "$outputPath.tmp"
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8
Move-Item -LiteralPath $temp -Destination $outputPath -Force
