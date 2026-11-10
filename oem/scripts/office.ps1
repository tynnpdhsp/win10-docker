. "$PSScriptRoot\common.ps1"
Start-Log 'office'

$config = 'C:\OEM\office\office-ltsc2024.xml'
$fallback = Join-Path $LogDir 'office-fallback.xml'
$work = Join-Path $env:TEMP 'odt'
$setup = Join-Path $work 'setup.exe'
$root = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16'
$apps = [ordered]@{ Word = 'WINWORD.EXE'; Excel = 'EXCEL.EXE'; PowerPoint = 'POWERPNT.EXE' }

function Test-Office {
    foreach ($exe in $apps.Values) { if (-not (Test-Path (Join-Path $root $exe))) { return $false } }
    return $true
}

function Get-OfficeSetup {
    for ($i = 1; $i -le 5; $i++) {
        try {
            Write-Log "Downloading Office Deployment Tool (attempt $i)"
            Invoke-WebRequest -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setup -UseBasicParsing -TimeoutSec 300
            Unblock-File $setup
            $sig = Get-AuthenticodeSignature $setup
            if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'O=Microsoft Corporation') { return $true }
            Write-Log "   invalid signature: $($sig.Status) $($sig.SignerCertificate.Subject)"
        } catch {
            Write-Log "   failed: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 20
    }
    return $false
}

function New-FallbackConfig {
    [xml]$x = Get-Content -Raw $config
    @($x.SelectNodes("//Product[@ID='ProofingTools']")) | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
    @($x.SelectNodes('//ExcludeApp') | Where-Object { 'Access', 'Lync', 'OneDrive', 'OneNote', 'Outlook' -notcontains $_.ID }) |
        ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
    $x.Save($fallback)
}

if (Test-Office) {
    Write-Log 'Office is already installed.'
} else {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    if (-not (Get-OfficeSetup)) { Write-Log 'ERROR: cannot download the Office Deployment Tool'; Stop-Transcript | Out-Null; exit 1 }
    New-FallbackConfig
    foreach ($cfg in $config, $config, $fallback) {
        if (Test-Office) { break }
        Write-Log "Installing Office with $cfg (about 3 GB download)"
        $p = Start-Process -FilePath $setup -ArgumentList "/configure `"$cfg`"" -Wait -PassThru
        Write-Log "   setup.exe exit code: $($p.ExitCode)"
        if (-not (Test-Office)) { Start-Sleep -Seconds 30 }
    }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Office)) { Write-Log 'ERROR: Office is not installed'; Stop-Transcript | Out-Null; exit 1 }

Step 'Office settings: no GPU acceleration or animations, no telemetry' {
    $base = 'HKCU:\Software\Microsoft\Office\16.0'
    Set-Reg "$base\Common\Graphics" 'DisableHardwareAcceleration' 1
    Set-Reg "$base\Common\Graphics" 'DisableAnimations' 1
    Set-Reg "$base\Common\General" 'ShownFirstRunOptin' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry' 'SendTelemetry' 3
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry' 'DisableTelemetry' 1
}

Step 'Office scheduled tasks: disable telemetry and monitors (updates stay on)' {
    Get-ScheduledTask -TaskPath '\Microsoft\Office\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match 'Telemetry|Performance Monitor|Service Monitor' } |
        ForEach-Object { $_ | Disable-ScheduledTask | Out-Null; Write-Log "   disabled $($_.TaskName)" }
}

Step 'Desktop shortcuts' {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    foreach ($app in $apps.GetEnumerator()) {
        $lnk = $shell.CreateShortcut((Join-Path $desktop "$($app.Key).lnk"))
        $lnk.TargetPath = Join-Path $root $app.Value
        $lnk.Save()
    }
}

Step 'Report' {
    $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
    Write-Log "   products: $($c2r.ProductReleaseIds) | version: $($c2r.VersionToReport) | $($c2r.Platform)"
    $ospp = Join-Path $env:ProgramFiles 'Microsoft Office\Office16\OSPP.VBS'
    if (Test-Path $ospp) { Invoke-Native cscript.exe @('//Nologo', $ospp, '/dstatus') }
}

Write-Log 'Office installation finished.'
Stop-Transcript | Out-Null
exit 0
