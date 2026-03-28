[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [Parameter()]
    [string]$PythonCommand = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$requirementsPath = Join-Path $repoRoot "Windows\runtime-requirements\kokoro-common.txt"
$cudaWheelIndex = "https://download.pytorch.org/whl/cu124"

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)][string]$PythonExe,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $PythonExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $PythonExe $($Arguments -join ' ')"
    }
}

function Remove-IfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function New-RuntimeVirtualEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeName,
        [Parameter(Mandatory = $true)][string[]]$TorchInstallArguments
    )

    $runtimeRoot = Join-Path $OutputRoot $RuntimeName
    Remove-IfExists -Path $runtimeRoot

    & $PythonCommand -m venv $runtimeRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create virtual environment for $RuntimeName."
    }

    $runtimePython = Join-Path $runtimeRoot "Scripts\python.exe"
    Invoke-Python -PythonExe $runtimePython -Arguments @("-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel")
    Invoke-Python -PythonExe $runtimePython -Arguments $TorchInstallArguments
    Invoke-Python -PythonExe $runtimePython -Arguments @("-m", "pip", "install", "-r", $requirementsPath)
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

New-RuntimeVirtualEnvironment -RuntimeName "KokoroDirectML" -TorchInstallArguments @(
    "-m", "pip", "install",
    "torch==2.4.1",
    "torchvision==0.19.1",
    "torch-directml==0.2.5.dev240914")

$directMlRoot = Join-Path $OutputRoot "KokoroDirectML"
$cpuRoot = Join-Path $OutputRoot "KokoroCpu"
Remove-IfExists -Path $cpuRoot
Copy-Item -LiteralPath $directMlRoot -Destination $cpuRoot -Recurse -Force

New-RuntimeVirtualEnvironment -RuntimeName "KokoroCuda" -TorchInstallArguments @(
    "-m", "pip", "install",
    "torch==2.4.1",
    "torchvision==0.19.1",
    "--index-url", $cudaWheelIndex)
