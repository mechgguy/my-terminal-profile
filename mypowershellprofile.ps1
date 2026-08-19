$WeatherLatitude  = 50.1109
$WeatherLongitude = 8.6821
$WeatherLocation  = "Frankfurt"

# ─────────────────────────────────────────────
# Conda
# ─────────────────────────────────────────────

& "C:\ProgramData\anaconda3\shell\condabin\conda-hook.ps1"

# ─────────────────────────────────────────────
# Chocolatey + Git PATH
# ─────────────────────────────────────────────

$env:ChocolateyInstall = "$env:LOCALAPPDATA\chocolatey"

& {
    $chocoPath = Join-Path $env:ChocolateyInstall 'bin'
    $gitPath   = Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd'

    if (Test-Path $chocoPath) {
        if (($env:Path -split ';') -notcontains $chocoPath) {
            $env:Path += ";$chocoPath"
        }
    }

    if (Test-Path $gitPath) {
        if (($env:Path -split ';') -notcontains $gitPath) {
            $env:Path += ";$gitPath"
        }
    }
}

# linux like aliases

function ll {
    Get-ChildItem -Force |
        Sort-Object LastWriteTime -Descending |
        Format-Table Mode, LastWriteTime, Length, Name -AutoSize
}
function du {
    param(
        [string]$Path = "."
    )

    $item = Get-Item $Path -ErrorAction Stop

    if ($item.PSIsContainer) {
        $bytes = (Get-ChildItem $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
    }
    else {
        $bytes = $item.Length
    }

    if ($null -eq $bytes) {
        $bytes = 0
    }

    if ($bytes -ge 1TB) {
        "{0:N2} TB`t{1}" -f ($bytes / 1TB), $Path
    }
    elseif ($bytes -ge 1GB) {
        "{0:N2} GB`t{1}" -f ($bytes / 1GB), $Path
    }
    elseif ($bytes -ge 1MB) {
        "{0:N2} MB`t{1}" -f ($bytes / 1MB), $Path
    }
    elseif ($bytes -ge 1KB) {
        "{0:N2} KB`t{1}" -f ($bytes / 1KB), $Path
    }
    else {
        "{0} B`t{1}" -f $bytes, $Path
    }
}
function df {
    Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Used -ne $null } |
        ForEach-Object {
            $used = $_.Used
            $free = $_.Free
            $total = $used + $free

            [PSCustomObject]@{
                Filesystem = $_.Root
                Size       = "{0:N1} GB" -f ($total / 1GB)
                Used       = "{0:N1} GB" -f ($used / 1GB)
                Available  = "{0:N1} GB" -f ($free / 1GB)
                Use        = "{0:N0}%" -f (($used / $total) * 100)
                MountedOn  = $_.Root
            }
        } |
        Format-Table -AutoSize
}
Set-Alias -Name grep -Value Select-String
Set-Alias -Name which -Value Get-Command

function touch($Path) {
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    }
    else {
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

function .. {
    Set-Location ..
}

function ... {
    Set-Location ../..
}

function .... {
    Set-Location ../../..
}

# ─────────────────────────────────────────────
# GPU status
# ─────────────────────────────────────────────

function gpustat {
    if (-not (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)) {
        Write-Host "nvidia-smi not found." -ForegroundColor Red
        return
    }

    $query = @(
        "index"
        "name"
        "temperature.gpu"
        "utilization.gpu"
        "utilization.memory"
        "memory.used"
        "memory.total"
        "power.draw"
        "power.limit"
    ) -join ","

    $rows = nvidia-smi --query-gpu=$query --format=csv,noheader,nounits 2>$null

    if (-not $rows) {
        Write-Host "No NVIDIA GPU detected." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host " NVIDIA GPU STATUS" -ForegroundColor Cyan
    Write-Host " ================================================================" -ForegroundColor DarkGray

    foreach ($row in $rows) {
        $p = $row -split ',\s*'

        $index      = $p[0]
        $name       = $p[1]
        $temp       = [int]$p[2]
        $gpuUtil    = [int]$p[3]
        $memUtil    = [int]$p[4]
        $memUsed    = [int]$p[5]
        $memTotal   = [int]$p[6]
        $power      = [double]$p[7]
        $powerLimit = [double]$p[8]

        if ($memTotal -gt 0) {
            $memPercent = [math]::Round(($memUsed / $memTotal) * 100)
        }
        else {
            $memPercent = 0
        }

        # ASCII progress bars
        $gpuFilled = [math]::Floor($gpuUtil / 5)
        $memFilled = [math]::Floor($memPercent / 5)

        $gpuBar = ("#" * $gpuFilled).PadRight(20, ".")
        $memBar = ("#" * $memFilled).PadRight(20, ".")

        Write-Host ""
        Write-Host (" GPU {0}  {1}" -f $index, $name) -ForegroundColor White

        Write-Host ("   GPU   [{0}] {1,3}%" -f $gpuBar, $gpuUtil) `
            -ForegroundColor $(if ($gpuUtil -ge 90) { "Red" } elseif ($gpuUtil -ge 70) { "Yellow" } else { "Green" })

        Write-Host ("   VRAM  [{0}] {1,3}%  ({2:N0} / {3:N0} MiB)" `
            -f $memBar, $memPercent, $memUsed, $memTotal)

        Write-Host ("   TEMP  {0,3} C    POWER  {1,5:N1} / {2,5:N1} W" `
            -f $temp, $power, $powerLimit)

        Write-Host " ================================================================" `
            -ForegroundColor DarkGray
    }
}


# Continuously refresh GPU status
function watch-gpustat {
    param(
        [int]$Interval = 2
    )

    while ($true) {
        Clear-Host
        Write-Host " GPU MONITOR" -ForegroundColor Cyan
        Write-Host (" Refresh: every {0}s   Press Ctrl+C to exit" -f $Interval) `
            -ForegroundColor DarkGray

        gpustat

        Start-Sleep -Seconds $Interval
    }
}


# Linux-style command
Set-Alias -Name gpu -Value gpustat
Set-Alias -Name watchgpu -Value watch-gpustat


# ─────────────────────────────────────────────
# Bash-style prompt
# ─────────────────────────────────────────────

function prompt {
    $userName = $env:USERNAME
    $computerName = $env:COMPUTERNAME

    $currentPath = (Get-Location).Path.Replace('\', '/')
    $homePath = $HOME.Replace('\', '/')

    if ($currentPath -eq $homePath) {
        $displayPath = "~"
    }
    elseif ($currentPath.StartsWith("$homePath/")) {
        $displayPath = "~" + $currentPath.Substring($homePath.Length)
    }
    else {
        $displayPath = $currentPath
    }

    Write-Host "$userName@$computerName" -ForegroundColor Green -NoNewline
    Write-Host ":$displayPath" -ForegroundColor Cyan -NoNewline

    return "$ "
}

# ─────────────────────────────────────────────
# Weather
# Fixed coordinates - no location access
# ─────────────────────────────────────────────

function weather {
    	$lat = $WeatherLatitude
	$lon = $WeatherLongitude

    try {
        $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m&timezone=auto"

        $w = Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop

        $code = $w.current.weather_code

        $condition = switch ($code) {
            0     { "Clear sky" }
            1     { "Mainly clear" }
            2     { "Partly cloudy" }
            3     { "Overcast" }
            45    { "Fog" }
            48    { "Rime fog" }
            51    { "Light drizzle" }
            53    { "Moderate drizzle" }
            55    { "Dense drizzle" }
            61    { "Light rain" }
            63    { "Moderate rain" }
            65    { "Heavy rain" }
            71    { "Light snow" }
            73    { "Moderate snow" }
            75    { "Heavy snow" }
            80    { "Light showers" }
            81    { "Moderate showers" }
            82    { "Heavy showers" }
            95    { "Thunderstorm" }
            96    { "Thunderstorm + hail" }
            99    { "Thunderstorm + heavy hail" }
            default { "Unknown" }
        }

        Write-Host ""
        Write-Host " WEATHER" -ForegroundColor Cyan
        Write-Host " ==============================================" -ForegroundColor DarkGray
	Write-Host (" Location : {0}" -f $WeatherLocation) -ForegroundColor White
        Write-Host (" Temp     : {0:N1} C" -f $w.current.temperature_2m)
        Write-Host (" Feels    : {0:N1} C" -f $w.current.apparent_temperature)
        Write-Host (" Humidity : {0}%" -f $w.current.relative_humidity_2m)
        Write-Host (" Wind     : {0:N1} km/h" -f $w.current.wind_speed_10m)
        Write-Host (" Rain     : {0:N1} mm" -f $w.current.precipitation)
        Write-Host (" Condition: {0}" -f $condition)
        Write-Host " ==============================================" -ForegroundColor DarkGray
        Write-Host ""
    }
    catch {
        Write-Host "Weather request failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Set-Alias -Name wt -Value weather