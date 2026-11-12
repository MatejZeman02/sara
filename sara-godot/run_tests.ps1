# The suites on Windows, the way run_tests.sh runs them on Linux.
#
#     powershell -File run_tests.ps1            every suite
#     powershell -File run_tests.ps1 chunk      only suites matching "chunk"
#
# Its one job beyond starting the engine is the folder. Godot keeps its own
# user folder, the shader caches, the Vulkan pipeline cache and the snapshots
# folder among them, under %APPDATA%\Godot\app_userdata\Sara, which is the
# painter's folder with their colours, their layout and their recovery
# copies. run_tests.sh moves it on Linux with XDG_DATA_HOME, and
# --settings-dir moves only what Sara itself writes, so a run that set only that
# would leave an objectdb_snapshots folder and shader files behind.
# Here APPDATA and XDG_DATA_HOME, the two variables the engine reads for it on
# Windows, are set to a scratch folder of the checkout before the first engine
# starts, and everything the engine starts after that inherits them.
#
# There is no offscreen compositor on Windows, so this is the desktop run, and
# it takes run_tests.sh's `xdg-desktop` folder.
#
# After the suites on a full run it boots the skeleton, run_tests.sh's last
# step: one launch of the resting-app scenario against an empty
# modules root, read back from its artefacts by the same check_skeleton_boots.py
# the shell script runs. scripts/sara_shot.py nests a weston and Windows has
# none, so this is the desktop launch of the same command, under the same
# scratch folders and a limit of its own. A boot that fails fails the run, and a
# filtered run, which is a person chasing one suite, skips it, as does
# SARA_SKIP_BOOT_CHECK.
#
# The painter's own folder is listed before the first engine and after the
# last, and the script says whether the two listings differ. It does not turn
# that into an exit code, because a painter with Sara open writes there too.
# The exit code is the engine's, or 1 when the suites passed and the skeleton did
# not boot, which is what the gate reads.
param(
    [string]$Godot = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "" }),
    [int]$TimeoutSeconds = $(if ($env:SARA_TEST_TIMEOUT) { [int]$env:SARA_TEST_TIMEOUT } else { 1800 }),
    [int]$BootTimeoutSeconds = $(if ($env:SARA_BOOT_TIMEOUT) { [int]$env:SARA_BOOT_TIMEOUT } else { 120 }),
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Filter
)
$ErrorActionPreference = "Stop"

$project = $PSScriptRoot

# The console build prints to the console the suites are read from, so it is
# asked for first. GODOT_BIN or -Godot names one outright.
if (-not $Godot) {
    $found = "godot.console", "godot", "godot4" | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $found) {
        "Error: Godot executable not found on PATH. Set GODOT_BIN or pass -Godot."
        exit 1
    }
    $Godot = $found.Source
}
$isolation = Join-Path $project "scratch\xdg-desktop"
$settings = Join-Path $isolation "config\sara"
$engineLog = Join-Path $project "scratch\logs\gate\godot.log"

# The painter's folder, read before the two variables below change what the
# engine calls its own. It is the folder a run must leave as found.
$painters = Join-Path $env:APPDATA "Godot\app_userdata\Sara"

function Get-Listing([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) { return @("(no such folder)") }
    $lines = @(Get-ChildItem -LiteralPath $Folder -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $name = $_.FullName.Substring($Folder.Length + 1)
        if ($_.PSIsContainer) { "$name\ dir $($_.LastWriteTime.ToString('s'))" }
        else { "$name $($_.Length) $($_.LastWriteTime.ToString('s'))" }
    })
    if (-not $lines) { return @("(empty)") }
    return $lines
}

New-Item -ItemType Directory -Force (Join-Path $isolation "appdata"), $settings, (Split-Path $engineLog) | Out-Null
$before = @(Get-Listing $painters)

# Before the first engine starts, and set in this process so that every engine
# below inherits them. The folder is the one run_tests.sh's XDG_DATA_HOME names
# on Linux, the engine adding its own `Godot\app_userdata\Sara` beneath it.
$env:APPDATA = Join-Path $isolation "appdata"
$env:XDG_DATA_HOME = $env:APPDATA
$env:SARA_LOG_FILE = $engineLog

$argsFor = @("--settings-dir=`"$settings`"", "--path", "`"$project`"")

# Output goes to the console unless a pair of files is named, which is how the
# skeleton boot keeps what the app printed for the check to read. What a
# function writes to the pipeline is part of what it returns, so every line this
# and the boot say goes through Write-Host, and the return is the exit code alone.
function Invoke-Engine([string[]]$Arguments, [int]$Seconds, [string]$StdOut = "", [string]$StdErr = "") {
    $start = @{ FilePath = $Godot; ArgumentList = $Arguments; NoNewWindow = $true; PassThru = $true }
    if ($StdOut) { $start.RedirectStandardOutput = $StdOut; $start.RedirectStandardError = $StdErr }
    $p = Start-Process @start
    # Reading the handle keeps ExitCode readable once the process has ended.
    $null = $p.Handle
    if (-not $p.WaitForExit($Seconds * 1000)) {
        Write-Host "  the engine was still running after $Seconds s and was stopped"
        Stop-Process -Id $p.Id -Force
        $p.WaitForExit()
        return 124
    }
    return $p.ExitCode
}

# A class_name added since an editor last looked is not in the class cache, and
# a tree with no .godot at all has none. The editor's import pass writes it,
# the same pass run_tests.sh runs. A picture merged or replaced since is read
# through an import only that pass writes, so an .import newer than the cache
# counts, and so does a file with one beside it.
$classCache = Join-Path $project ".godot\global_script_class_cache.cfg"
$rescan = -not (Test-Path -LiteralPath $classCache)
if (-not $rescan) {
    $cache = (Get-Item -LiteralPath $classCache).LastWriteTime
    $rescan = [bool](Get-ChildItem -LiteralPath $project -Recurse -File |
        Where-Object { $_.LastWriteTime -gt $cache -and $_.FullName -notmatch '\\(\.godot|scratch|\.conda|build)\\' } |
        Where-Object { $_.Extension -eq ".gd" -or $_.Extension -eq ".import" -or (Test-Path -LiteralPath "$($_.FullName).import") } |
        Select-Object -First 1)
}
if ($rescan) {
    "  rescan  letting the editor look at the tree"
    $null = Invoke-Engine (@("--headless") + $argsFor + @("--editor", "--quit")) 1200
}

"  godot   $Godot"
"  folder  the engine's own folder is $env:APPDATA\Godot\app_userdata\Sara"
$suiteArgs = @("--no-header", "--log-file", "`"$engineLog`"") + $argsFor + @("res://tests/run_all.tscn")
if ($Filter) { $suiteArgs += @("--") + $Filter }
$code = Invoke-Engine $suiteArgs $TimeoutSeconds

# The skeleton boots with no module to load, after a suite that passed. The
# engine is the desktop one and the scenario is run_tests.sh's, so a window opens
# for the few seconds it takes. The artefacts land under scratch\boot-check, and
# the check that reads them is the Python one the shell script runs, called
# without sara_shot.py between, which needs a compositor Windows does not have.
function Invoke-SkeletonBoot {
    $boot = Join-Path $project "scratch\boot-check"
    $empty = Join-Path $boot "no-modules"
    $out = Join-Path $boot "out"
    $bootLog = Join-Path $boot "godot.log"
    $scenario = Join-Path $project "scenarios\the-skeleton-without-modules.json"
    Remove-Item -LiteralPath $boot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $empty, $out | Out-Null
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Host "  the skeleton boot is read back by python, and none is on PATH"
        return 1
    }
    Write-Host "  skeleton  booting with no module to load, limit $BootTimeoutSeconds s"
    $env:SARA_MODULES_ROOT = $empty
    $env:SARA_LOG_FILE = $bootLog
    $bootArgs = @("--log-file", "`"$bootLog`"", "--path", "`"$project`"", "--",
        "--capture=`"$scenario`"", "--capture-out=`"$out`"", "--settings-dir=`"$settings`"")
    $stdout = Join-Path $boot "stdout.txt"
    $stderr = Join-Path $boot "stderr.txt"
    $code = Invoke-Engine $bootArgs $BootTimeoutSeconds $stdout $stderr
    Remove-Item Env:SARA_MODULES_ROOT
    $env:SARA_LOG_FILE = $engineLog
    # run.log is what sara_shot.py writes beside the artefacts and the check reads.
    @("# exit $code", "") + @(Get-Content -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue) |
        Set-Content -LiteralPath (Join-Path $out "run.log") -Encoding utf8
    # The limit is a failure of its own. Any other exit is said and left to the
    # artefacts, as sara_shot.py leaves a teardown that went wrong after the
    # scenario had finished.
    if ($code -eq 124) { return 124 }
    if ($code -ne 0) { Write-Host "  the engine exited $code after the scenario" }
    # The log has the engine's own characters in it, and Python on Windows
    # reads a text file as the code page unless it is told otherwise.
    $env:PYTHONPATH = Join-Path $project "scripts"
    $env:PYTHONUTF8 = "1"
    python -c "import sys, check_skeleton_boots as c; from pathlib import Path; f = c.check(Path(sys.argv[1])); print(chr(10).join(f)); sys.exit(1 if f else 0)" $out | Out-Host
    if ($LASTEXITCODE -ne 0) { return 1 }
    Write-Host "  skeleton  the window opened, the toolbox is empty, no error"
    return 0
}

if ($code -eq 0 -and -not $Filter -and -not $env:SARA_SKIP_BOOT_CHECK) {
    if ((Invoke-SkeletonBoot) -ne 0) {
        Write-Host "  The skeleton did not boot with no module to load."
        $code = 1
    }
}

$after = @(Get-Listing $painters)
$moved = Compare-Object $before $after
if ($moved) {
    "  the painter's folder changed while the suites ran: $painters"
    $moved | ForEach-Object { "    $($_.SideIndicator) $($_.InputObject)" }
} else {
    "  the painter's folder is as found, $($before.Count) entries: $painters"
}
exit $code
