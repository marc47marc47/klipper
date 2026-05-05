$ErrorActionPreference = "Stop"

$PythonVersion = if ($env:PYTHON_VERSION) { $env:PYTHON_VERSION } else { "3.10" }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = $ScriptDir
$UvDir = Join-Path $RootDir ".uv"
$UvBinDir = Join-Path $UvDir "bin"
$PythonInstallDir = Join-Path $UvDir "python"
$VenvDir = Join-Path $RootDir ".venv"
$Uv = Join-Path $UvBinDir "uv.exe"

New-Item -ItemType Directory -Force -Path $UvBinDir, $PythonInstallDir | Out-Null

if (-not (Test-Path $Uv)) {
    $ExistingUv = Get-Command uv -ErrorAction SilentlyContinue
    if ($ExistingUv) {
        Copy-Item -Force $ExistingUv.Source $Uv
    } else {
        $env:UV_INSTALL_DIR = $UvBinDir
        irm https://astral.sh/uv/install.ps1 | iex
    }
}

if (-not (Test-Path $Uv)) {
    throw "uv was not installed at $Uv"
}

Set-Content -Path (Join-Path $RootDir ".python-version") -Value $PythonVersion -Encoding ascii

Write-Host "Installing Python $PythonVersion into $PythonInstallDir"
Write-Host "Using uv: $Uv"

Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue
$env:UV_PYTHON_INSTALL_DIR = $PythonInstallDir

& $Uv python install $PythonVersion --install-dir $PythonInstallDir --no-bin --no-registry
& $Uv python find $PythonVersion
if (-not (Test-Path $VenvDir)) {
    & $Uv venv --python $PythonVersion $VenvDir
} else {
    Write-Host "Virtual environment already exists: $VenvDir"
}
& $Uv run --python $PythonVersion python --version

Write-Host ""
Write-Host "Environment ready."
Write-Host "Enable it in the current PowerShell with:"
Write-Host "  . .\scripts\setenv.python.ps1"
