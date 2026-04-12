$fallback7z = Join-Path $PSScriptRoot "7z\7zr.exe";
$useragent = "Yomipv-Updater"
$api_url = "https://api.github.com/repos/BrenoAqua/Yomipv/releases/latest"

function Get-7z {
    $7z_command = Get-Command -CommandType Application -ErrorAction Ignore 7z.exe | Select-Object -Last 1
    if ($7z_command) {
        return $7z_command.Source
    }
    $7zdir = Get-ItemPropertyValue -ErrorAction Ignore "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip" "InstallLocation"
    if ($7zdir -and (Test-Path (Join-Path $7zdir "7z.exe"))) {
        return Join-Path $7zdir "7z.exe"
    }
    if (Test-Path $fallback7z) {
        return $fallback7z
    }
    return $null
}

function Install-7z {
    if (-not (Get-7z))
    {
        $null = New-Item -ItemType Directory -Force (Split-Path $fallback7z)
        $download_file = $fallback7z
        Write-Host "Downloading 7zr.exe" -ForegroundColor Green
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -UserAgent $useragent -OutFile $download_file -UseBasicParsing
    }
}

function Test-PowershellVersion {
    $version = $PSVersionTable.PSVersion.Major
    Write-Host "Checking Windows PowerShell version -- $version" -ForegroundColor Green
    if ($version -le 2)
    {
        Write-Host "Using Windows PowerShell $version is unsupported. Upgrade your Windows PowerShell." -ForegroundColor Red
        throw
    }
}

function Test-Admin {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Receive-Archive ($filename, $link) {
    Write-Host "Downloading" $filename -ForegroundColor Green
    Invoke-WebRequest -Uri $link -UserAgent $useragent -OutFile $filename -UseBasicParsing
}

function Expand-YomipvArchive ($archiveFile, $destination) {
    $7z = Get-7z
    Write-Host "Extracting" $archiveFile -ForegroundColor Green
    & $7z x -y $archiveFile "-o$destination"
}

function Get-LocalVersion {
    $main_lua = Join-Path $PSScriptRoot "scripts\yomipv\main.lua"
    if (Test-Path $main_lua) {
        $content = Get-Content $main_lua -Raw
        if ($content -match 'yomipv_version = "([^"]+)"') {
            return $matches[1]
        }
    }
    return "0.0.0"
}

function Get-Config {
    $conf = @{}
    $conf_path = Join-Path $PSScriptRoot "script-opts\yomipv.conf"
    if (Test-Path $conf_path) {
        Get-Content $conf_path -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*([^#\s=]+)\s*=\s*([^#]*)') {
                $conf[$matches[1]] = $matches[2].Trim()
            }
        }
    }
    return $conf
}

function Merge-Config ($OldConfig) {
    if ($null -eq $OldConfig -or $OldConfig.Count -eq 0) { return }
    $conf_path = Join-Path $PSScriptRoot "script-opts\yomipv.conf"
    if (Test-Path $conf_path) {
        Write-Host "Restoring user configuration settings..." -ForegroundColor Cyan
        $lines = Get-Content $conf_path -Raw -Encoding UTF8
        $linesArray = $lines -split "\r?\n"
        $usedKeys = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        
        for ($i = 0; $i -lt $linesArray.Count; $i++) {
            if ($linesArray[$i] -match '^(\s*#?\s*([^#\s=]+)\s*=\s*)([^#]*)(.*)$') {
                $prefix = $matches[1]
                $key = $matches[2]
                $suffix = $matches[4]
                
                if ($OldConfig.ContainsKey($key) -and -not $usedKeys.Contains($key)) {
                    $val = $OldConfig[$key]
                    $newPrefix = $prefix -replace '^(\s*)#?\s*', '$1'
                    $linesArray[$i] = "$newPrefix$val$suffix"
                    $null = $usedKeys.Add($key)
                }
            }
        }
        
        $newLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in $linesArray) { $null = $newLines.Add($line) }
        
        foreach ($key in $OldConfig.Keys) {
            if (-not $usedKeys.Contains($key)) {
                $null = $newLines.Add("$key=$($OldConfig[$key])")
            }
        }
        
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($conf_path, ($newLines -join [Environment]::NewLine), $utf8NoBom)
    }
}

function Backup-Css {
    $css_path = Join-Path $PSScriptRoot "script-opts\yomipv.css"
    if (Test-Path $css_path) {
        Copy-Item -Path $css_path -Destination "$css_path.tmp_backup" -Force
        return $true
    }
    return $false
}

function Restore-Css ($has_css) {
    if ($has_css) {
        $css_path = Join-Path $PSScriptRoot "script-opts\yomipv.css"
        Move-Item -Path "$css_path.tmp_backup" -Destination $css_path -Force
    }
}

function Update-Dependencies {
    $app_dir = Join-Path $PSScriptRoot "scripts\yomipv\lookup-app"
    if (Test-Path (Join-Path $app_dir "package.json")) {
        Write-Host "Checking for node_modules..." -ForegroundColor Cyan
        if (-not (Test-Path (Join-Path $app_dir "node_modules"))) {
            Write-Host "Installing dependencies for lookup-app..." -ForegroundColor Green
            Push-Location $app_dir
            npm install
            Pop-Location
        }
    }
}

function Read-KeyOrTimeout ($prompt, $key){
    $seconds = 9
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds

    Write-Host "$prompt " -ForegroundColor Green

    # Progress bar
    [Console]::CursorLeft = 0
    [Console]::Write("[")
    [Console]::CursorLeft = $seconds + 2
    [Console]::Write("]")
    [Console]::CursorLeft = 1

    while (-not [System.Console]::KeyAvailable) {
        $currentTime = Get-Date
        Start-Sleep -s 1
        Write-Host "#" -ForegroundColor Green -NoNewline
        if ($currentTime -gt $startTime + $timeOut) {
            Break
        }
    }
    if ([System.Console]::KeyAvailable) {
        $response = [System.Console]::ReadKey($true).Key
    }
    else {
        $response = $key
    }
    return $response.ToString()
}

function Get-MpvInstances {
    $instances = @()
    try {
        $processes = Get-CimInstance Win32_Process -Filter "name = 'mpv.exe'" -ErrorAction SilentlyContinue
        foreach ($proc in $processes) {
            if ($proc.CommandLine) {
                $instances += @{
                    CommandLine = $proc.CommandLine
                    Executable = $proc.ExecutablePath
                }
            }
        }
    } catch {
        Write-Host "Warning: Could not capture MPV command line arguments." -ForegroundColor Yellow
    }
    return $instances
}

function Stop-YomipvProcesses {
    Write-Host "Checking for running Yomipv processes..." -ForegroundColor Cyan
    
    $lookupProcs = Get-Process "YomipvLookup" -ErrorAction SilentlyContinue
    if ($lookupProcs) {
        Write-Host "Stopping Yomipv Lookup App..." -ForegroundColor Yellow
        $lookupProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $mpvProcs = Get-Process "mpv" -ErrorAction SilentlyContinue
    if ($mpvProcs) {
        Write-Host "Stopping MPV instances..." -ForegroundColor Yellow
        $mpvProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

function Restart-MpvInstances ($instances) {
    if ($null -eq $instances -or $instances.Count -eq 0) { return }
    
    Write-Host "Restarting MPV instances..." -ForegroundColor Cyan
    foreach ($inst in $instances) {
        try {
            $cmd = $inst.CommandLine
            $exe = $inst.Executable
            
            $p_exe = $null
            $p_args = $null

            if ($cmd -match '^"([^"]+)"\s*(.*)$') {
                $p_exe = $matches[1]
                $p_args = $matches[2]
            } elseif ($cmd -match '^([^\s]+)\s*(.*)$') {
                $p_exe = $matches[1]
                $p_args = $matches[2]
            }

            if ($p_exe) {
                $target = if ($exe -and (Test-Path $exe)) { $exe } else { $p_exe }
                Start-Process -FilePath $target -ArgumentList $p_args
            }
        } catch {
            Write-Host "Warning: Failed to restart an MPV instance." -ForegroundColor Yellow
        }
    }
}

function Update-Yomipv {
    if (Test-Path (Join-Path $PSScriptRoot ".git")) {
        Write-Host "Git repository detected. Updating via git..." -ForegroundColor Cyan
        git fetch origin main | Out-Null
        $local_hash = git rev-parse HEAD
        $remote_hash = git rev-parse origin/main
        
        if ($local_hash -eq $remote_hash) {
            Write-Host "You are already using the latest version." -ForegroundColor Green
            return $false
        }
        
        Write-Host "New updates available. Pulling..." -ForegroundColor Green
        $oldConfig = Get-Config
        $hasCss = Backup-Css
        git pull origin main
        Restore-Css $hasCss
        Merge-Config $oldConfig
        return $true
    }

    $config = Get-Config
    $use_source = ($config["updater_use_source"] -eq "yes")
    
    if (-not $config.ContainsKey("updater_use_source")) {
        $result = Read-KeyOrTimeout "Choose update source: Official Releases or Latest Source? [1=Releases / 2=Source] (default=1)" "D1"
        Write-Host ""
        if ($result -eq 'D2') {
            $use_source = $true
        }
    }

    if ($use_source) {
        Write-Host "Updating from source (main branch)..." -ForegroundColor Cyan
        $zip_url = "https://github.com/BrenoAqua/Yomipv/archive/refs/heads/main.zip"
        $temp_zip = Join-Path $env:TEMP "yomipv-source.zip"
        
        Receive-Archive $temp_zip $zip_url
        Install-7z
        
        $oldConfig = Get-Config
        $hasCss = Backup-Css
        
        $extract_dir = Join-Path $env:TEMP "yomipv-extract"
        if (Test-Path $extract_dir) { Remove-Item $extract_dir -Recurse -Force }
        New-Item -ItemType Directory -Path $extract_dir | Out-Null
        
        Expand-YomipvArchive $temp_zip $extract_dir
        
        $source_folder = Get-ChildItem -Path $extract_dir -Directory | Select-Object -First 1
        if ($source_folder) {
            Write-Host "Applying source changes..." -ForegroundColor Green
            Copy-Item -Path (Join-Path $source_folder.FullName "*") -Destination $PSScriptRoot -Recurse -Force
            Restore-Css $hasCss
            Merge-Config $oldConfig
        }
        
        Remove-Item $temp_zip -ErrorAction Ignore
        Remove-Item $extract_dir -Recurse -ErrorAction Ignore
        return $true
    }

    Write-Host "Checking for latest release..." -ForegroundColor Cyan
    try {
        $json = Invoke-RestMethod -Uri $api_url -UserAgent $useragent -ErrorAction Stop
        if ($null -eq $json) { throw "Empty response from GitHub API." }
        
        $release = if ($json -is [Array]) { $json[0] } else { $json }
        
        if ($null -eq $release -or -not $release.tag_name) {
            throw "Invalid release data received from GitHub. You might be rate-limited."
        }

        $latest_ver = $release.tag_name -replace '^v', ""
        $local_ver = Get-LocalVersion
        
        Write-Host "Local version: $local_ver"
        Write-Host "Latest version: $latest_ver"
        
        if ($latest_ver -le $local_ver) {
            Write-Host "You are already using the latest version -- v$latest_ver" -ForegroundColor Green
            return $false
        }

        Write-Host "Newer Yomipv build available -- v$latest_ver" -ForegroundColor Green
        
        $zip_url = $null
        if ($release.assets) {
            foreach ($asset in $release.assets) {
                if ($asset.name -like "win-yomipv-*.zip") {
                    $zip_url = $asset.browser_download_url
                    break
                }
            }
            # Fallback
            if (-not $zip_url) {
                foreach ($asset in $release.assets) {
                    if ($asset.name -like "*.zip" -and $asset.name -notlike "*linux*") {
                        $zip_url = $asset.browser_download_url
                        break
                    }
                }
            }
        }
        
        if (-not $zip_url) { $zip_url = $release.zipball_url }
        if (-not $zip_url) { throw "Could not find a valid download URL." }
        
        $oldConfig = Get-Config
        $hasCss = Backup-Css
        
        $temp_zip = Join-Path $env:TEMP "yomipv-update.zip"
        Receive-Archive $temp_zip $zip_url
        Install-7z
        Expand-YomipvArchive $temp_zip $PSScriptRoot
        Restore-Css $hasCss
        Merge-Config $oldConfig
        
        Remove-Item $temp_zip -ErrorAction Ignore
        return $true
    } catch {
        Write-Host "Error checking for updates: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main script entry point
if (Test-Admin) {
    Write-Host "Running script with administrator privileges" -ForegroundColor Yellow
} else {
    Write-Host "Running script without administrator privileges" -ForegroundColor Red
}

try {
    Test-PowershellVersion
    $global:progressPreference = 'silentlyContinue'
    
    $mpvInstances = Get-MpvInstances
    Stop-YomipvProcesses
    
    $updated = Update-Yomipv
    if ($updated) {
        Update-Dependencies
        Restart-MpvInstances $mpvInstances
        Write-Host "Update installed!" -ForegroundColor Cyan
    }
    
    Write-Host "Operation completed" -ForegroundColor Magenta
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}

Read-Host "Press Enter to exit..."
