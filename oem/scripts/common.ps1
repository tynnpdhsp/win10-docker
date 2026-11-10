$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$LogDir = 'C:\OEM\logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Start-Log([string]$Name) {
    Start-Transcript -Path (Join-Path $LogDir "$Name.log") -Append | Out-Null
}

function Write-Log([string]$Message) {
    Write-Host ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message)
}

function Step([string]$Title, [scriptblock]$Action) {
    Write-Log "== $Title"
    try { & $Action } catch { Write-Log "   WARN: $($_.Exception.Message)" }
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
    $out = & $File @Arguments 2>&1 | Out-String
    if ($out.Trim()) { Write-Host $out.TrimEnd() }
    if ($LASTEXITCODE) { Write-Log "   $File exited with code $LASTEXITCODE" }
}

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "   WARN: $Path\$Name -> $($_.Exception.Message)"
    }
}
