$RootDir = if ($env:KLIPPER_ROOT) {
    $env:KLIPPER_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$env:UV_PYTHON_INSTALL_DIR = Join-Path $RootDir ".uv\python"
$env:VIRTUAL_ENV = Join-Path $RootDir ".venv"
$UvBinDir = Join-Path $RootDir ".uv\bin"
$VenvScripts = Join-Path $env:VIRTUAL_ENV "Scripts"
$env:PATH = "$VenvScripts;$UvBinDir;$env:PATH"
$env:PYTHON = Join-Path $VenvScripts "python.exe"

if (Test-Path $env:PYTHON) {
    & $env:PYTHON --version
} else {
    Write-Warning "Python was not found at $env:PYTHON"
    Write-Warning "Run: powershell -ExecutionPolicy Bypass -File .\install-project-python.ps1"
}
