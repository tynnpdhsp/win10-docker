. "$PSScriptRoot\common.ps1"
Start-Log 'optimize'

Step 'Time zone UTC+7 and time sync' {
    Set-TimeZone -Id 'SE Asia Standard Time'
    $cfg = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config'
    Set-Reg $cfg 'MaxPosPhaseCorrection' -1 # -1 = 0xFFFFFFFF: allow any correction size
    Set-Reg $cfg 'MaxNegPhaseCorrection' -1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' 'SpecialPollInterval' 3600
    Set-Service w32time -StartupType Automatic
    Start-Service w32time -ErrorAction SilentlyContinue
    Invoke-Native w32tm.exe @('/config', '/manualpeerlist:time.windows.com,0x9', '/syncfromflags:manual', '/update')
    Restart-Service w32time -Force
    Start-Sleep -Seconds 3
    Invoke-Native w32tm.exe @('/resync', '/rediscover')
    try {
        $r = Invoke-WebRequest -Uri 'https://www.microsoft.com' -Method Head -UseBasicParsing -TimeoutSec 30
        $web = [DateTimeOffset]::Parse($r.Headers['Date'], [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
        $skew = ($web - (Get-Date).ToUniversalTime()).TotalSeconds
        Write-Log ('   clock skew vs. web time: {0:N0} s' -f $skew)
        if ([Math]::Abs($skew) -gt 120) { Set-Date -Date $web.ToLocalTime() | Out-Null; Write-Log '   clock corrected' }
    } catch { Write-Log "   web time check skipped: $($_.Exception.Message)" }
    Write-Log "   now: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
}

Step 'Power: High performance, never sleep or hibernate' {
    $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    & powercfg.exe /setactive $hp 2>&1 | Out-Null
    if ($LASTEXITCODE) {
        $out = & powercfg.exe /duplicatescheme $hp | Out-String
        if ($out -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { & powercfg.exe /setactive $Matches[1] }
    }
    foreach ($t in 'monitor-timeout-ac', 'disk-timeout-ac', 'standby-timeout-ac', 'hibernate-timeout-ac') {
        Invoke-Native powercfg.exe @('/change', $t, '0')
    }
    Invoke-Native powercfg.exe @('/hibernate', 'off')
}

Step 'Visual effects: best performance, ClearType kept' {
    $desk = 'HKCU:\Control Panel\Desktop'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    Set-Reg $desk 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) 'Binary'
    Set-Reg $desk 'DragFullWindows' '0' 'String'
    Set-Reg $desk 'MenuShowDelay' '100' 'String'
    Set-Reg $desk 'FontSmoothing' '2' 'String'
    Set-Reg $desk 'FontSmoothingType' 2
    Set-Reg "$desk\WindowMetrics" 'MinAnimate' '0' 'String'
    Set-Reg $adv 'TaskbarAnimations' 0
    Set-Reg $adv 'ListviewAlphaSelect' 0
    Set-Reg $adv 'ListviewShadow' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Set-Reg $desk 'WallPaper' '' 'String'
    Set-Reg 'HKCU:\Control Panel\Colors' 'Background' '0 78 152' 'String'
}

Step 'Services: disable unneeded ones' {
    $services = 'SysMain', 'WSearch', 'DiagTrack', 'dmwappushservice', 'WerSvc', 'MapsBroker', 'lfsvc', 'RetailDemo',
        'wisvc', 'WpcMonSvc', 'PhoneSvc', 'icssvc', 'Fax', 'WMPNetworkSvc', 'TrkWks', 'RemoteRegistry'
    foreach ($name in $services) {
        if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "   disabled $name"
        }
    }
}

Step 'Scheduled tasks: disable telemetry and compatibility scans' {
    $tasks = '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Maps\MapsToastTask',
        '\Microsoft\Windows\Maps\MapsUpdateTask',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    foreach ($t in $tasks) {
        $i = $t.LastIndexOf('\')
        $task = Get-ScheduledTask -TaskPath $t.Substring(0, $i + 1) -TaskName $t.Substring($i + 1) -ErrorAction SilentlyContinue
        if ($task) { $task | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null; Write-Log "   disabled $t" }
    }
}

Step 'Policies: telemetry, web search, feeds, background apps, Edge background mode' {
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
    Set-Reg "$pol\Windows\DataCollection" 'AllowTelemetry' 0
    Set-Reg "$pol\Windows\Windows Search" 'AllowCortana' 0
    Set-Reg "$pol\Windows\Windows Search" 'DisableWebSearch' 1
    Set-Reg "$pol\Windows\Windows Search" 'ConnectedSearchUseWeb' 0
    Set-Reg "$pol\Windows\Windows Feeds" 'EnableFeeds' 0
    Set-Reg "$pol\Windows\AppPrivacy" 'LetAppsRunInBackground' 2
    Set-Reg "$pol\Windows\AdvertisingInfo" 'DisabledByGroupPolicy' 1
    Set-Reg "$pol\Windows\System" 'EnableActivityFeed' 0
    Set-Reg "$pol\Windows\System" 'PublishUserActivities' 0
    Set-Reg "$pol\Windows\System" 'UploadUserActivities' 0
    Set-Reg "$pol\Windows\Windows Error Reporting" 'Disabled' 1
    Set-Reg "$pol\Windows\GameDVR" 'AllowGameDVR' 0
    Set-Reg "$pol\Windows\DeliveryOptimization" 'DODownloadMode' 0
    Set-Reg "$pol\Edge" 'StartupBoostEnabled' 0
    Set-Reg "$pol\Edge" 'BackgroundModeEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
}

Step 'Explorer and taskbar' {
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'LaunchTo' 1
    Set-Reg $adv 'ShowCortanaButton' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg "$adv\People" 'PeopleBand' 0
}

Step 'Microsoft Defender: lower scan CPU usage' {
    Set-MpPreference -ScanAvgCPULoadFactor 20 -ErrorAction Stop
    Set-MpPreference -EnableLowCpuPriority $true -ErrorAction SilentlyContinue
}

Step 'Remove OneDrive sync client' {
    Get-Process OneDrive, OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($exe in "$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe") {
        if (Test-Path $exe) {
            $p = Start-Process -FilePath $exe -ArgumentList '/uninstall' -PassThru
            if (-not $p.WaitForExit(180000)) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
            Write-Log "   ran $exe /uninstall"
            break
        }
    }
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive', 'OneDriveSetup' -ErrorAction SilentlyContinue
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
}

Step 'Disk: TRIM on, no last-access writes' {
    Invoke-Native fsutil.exe @('behavior', 'set', 'DisableDeleteNotify', '0')
    Invoke-Native fsutil.exe @('behavior', 'set', 'disablelastaccess', '1')
}

Write-Log 'Windows optimization finished.'
Stop-Transcript | Out-Null
