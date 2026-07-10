$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourceDir = Join-Path $repoRoot "Assets/SaiGame/LuaScript/AbilitySources"
$orderFile = Join-Path $sourceDir "ability_order.txt"
$outputFile = Join-Path $repoRoot "Assets/SaiGame/LuaScript/Scripts/ability_all.lua"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("-- ability_all")
$lines.Add("-- Generated bundle from ``Assets/SaiGame/LuaScript/AbilitySources``.")
$lines.Add("-- is_library = true")
$lines.Add("")

foreach ($entry in Get-Content -Path $orderFile) {
    $name = $entry.Trim()
    if ($name -eq "" -or $name.StartsWith("#")) {
        continue
    }

    $sourcePath = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Ability source not found: $sourcePath"
    }

    foreach ($line in Get-Content -Path $sourcePath) {
        $lines.Add($line)
    }
    $lines.Add("")
}

Set-Content -Path $outputFile -Value $lines -Encoding UTF8
Write-Host "Generated $outputFile"
