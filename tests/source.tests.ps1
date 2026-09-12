$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
function Assert($condition,$message){if(-not $condition){throw $message}}

# 1. A PowerShell file that contains non-ASCII text must be saved as UTF-8 BOM.
#    Windows PowerShell 5.1 otherwise decodes it with the ANSI code page, so
#    Chinese string literals turn into mojibake and can swallow the closing
#    quote of a literal (a real parse failure, not just ugly output).
$checked=0
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.ps1){
 if($file.FullName -match '\\\.git\\'){continue}
 $raw=[IO.File]::ReadAllBytes($file.FullName)
 $nonAscii=$false
 foreach($byte in $raw){if($byte -gt 127){$nonAscii=$true;break}}
 if(-not $nonAscii){continue}
 $bom=($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
 Assert $bom ('PowerShell files containing non-ASCII text must be UTF-8 BOM: '+$file.Name)
 $checked++
}
Assert ($checked -gt 0) 'Expected to find PowerShell sources with Chinese text'

# 2. The Android frames under android/app/src/main/assets/pet are exported from the
#    desktop player at its internal render size (android/export-frames.ps1). If they
#    are re-exported from a checkout whose sprite-player.cs still renders smaller,
#    every frame is silently downgraded and nothing else notices. Pin the two together.
$playerPath=Join-Path $root 'sprite-player.cs'
$declaration=[regex]::Match((Get-Content -LiteralPath $playerPath -Raw),'const int Density=(\d+),W=(\d+)\*Density,H=(\d+)\*Density')
Assert $declaration.Success 'Could not read the render size from sprite-player.cs; update this check if the declaration changed'
$expectedWidth=[int]$declaration.Groups[1].Value*[int]$declaration.Groups[2].Value
$expectedHeight=[int]$declaration.Groups[1].Value*[int]$declaration.Groups[3].Value

Add-Type -AssemblyName System.Drawing
$frames=Get-ChildItem -LiteralPath (Join-Path $root 'android/app/src/main/assets/pet') -File -Filter *.png
Assert ($frames.Count -gt 0) 'Android exported frames are missing'
$sizes=@{}
foreach($frame in $frames){
 $image=[System.Drawing.Image]::FromFile($frame.FullName)
 try {$key="$($image.Width)x$($image.Height)"} finally {$image.Dispose()}
 if($sizes.ContainsKey($key)){$sizes[$key]++}else{$sizes[$key]=1}
}
$expected="${expectedWidth}x${expectedHeight}"
Assert ($sizes.Count -eq 1) ('Android frames must all share one size, found: '+(($sizes.Keys|Sort-Object) -join ', '))
Assert ($sizes.ContainsKey($expected)) ("Android frames are $((($sizes.Keys)|Select-Object -First 1)) but sprite-player.cs renders ${expected}; re-export with ./export-frames.ps1 -WindowsSource <this checkout>")
# 3. The phone settings page promises that every change takes effect immediately and
#    hides its save button, so the auto-start checkbox has to persist itself. Ticking it
#    used to write nothing and pet.ps1 never auto-started - a silent regression, because
#    the box looked ticked until the window was reopened. Pin the handler to the write.
$uiText=[IO.File]::ReadAllText((Join-Path $root 'mobile-ui.ps1'))
$autoHandler=[regex]::Match($uiText,'(?s)\$script:mobileControls\.Auto\.Add_Click\(\{(.*?)\r?\n \}\)')
Assert $autoHandler.Success 'Could not find the auto-start checkbox handler in mobile-ui.ps1; update this check if the handler changed'
Assert ($autoHandler.Groups[1].Value -match 'Save-MobileConfig') 'The auto-start checkbox must persist its own state, the page has no save button'
Assert ($autoHandler.Groups[1].Value -match 'IsChecked=\[bool\]\$script:mobileConfig\.autoStart') 'A rejected auto-start change must roll the checkbox back instead of showing a state that was never saved'

# 4. Update-MobileSettingsCore already reads status.json once and passes that snapshot
#    to Test-MobileInvite. Reading it again defeats the race reduction and can mix two
#    different service states in one UI tick.
$inviteFunction=[regex]::Match($uiText,'(?s)function Test-MobileInvite\(\$Status\) \{(.*?)\r?\n\}')
Assert $inviteFunction.Success 'Could not find Test-MobileInvite in mobile-ui.ps1; update this check if the function changed'
Assert ($inviteFunction.Groups[1].Value -match '\$s=\$Status') 'Test-MobileInvite must use the status snapshot supplied by its caller'
Assert ($inviteFunction.Groups[1].Value -notmatch '\$s=Get-MobileStatus') 'Test-MobileInvite must not read status.json a second time'

# 5. The optional standalone bridge must not open the selected port for every
#    executable on the machine. Bind its firewall rule to the bridge executable.
$firewallText=[IO.File]::ReadAllText((Join-Path $root 'bridge/allow-wireless.ps1'))
Assert ($firewallText -match 'New-NetFirewallRule[^\r\n]+-Program\s+\$exe') 'The standalone bridge firewall rule must be scoped to its executable'

# 6. The tray is the always-visible control surface when the pet is compacted or hidden.
#    Keep the recovery and frequently used controls there rather than only on the pet.
$petText=[IO.File]::ReadAllText((Join-Path $root 'pet.ps1'))
foreach($label in @('刷新 5 小时 / 一周用量','暂停 / 恢复随机动作','查看 Codex 用量页面','切换置顶')) {
 Assert ($petText.Contains($label)) ('Tray quick action is missing: '+$label)
}
Assert ($petText.Contains('额度连续三次获取失败，请检查网络或 Codex 版本。')) 'Three consecutive quota failures must produce a visible user message'

"PASS: $checked UTF-8 BOM PowerShell sources; $($frames.Count) Android frames at $expected; mobile settings source guards"
