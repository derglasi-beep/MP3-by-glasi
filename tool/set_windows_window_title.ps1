# Set the native Windows title bar caption from pubspec.yaml.
# Run after flutter create --platforms=windows . and before flutter build.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $projectRoot 'pubspec.yaml'
$mainCpp = Join-Path $projectRoot 'windows/runner/main.cpp'
if (-not (Test-Path $mainCpp)) {
    throw "Windows runner missing: $mainCpp. Run flutter create --platforms=windows . first."
}
$versionMatch = Select-String -Path $pubspec -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $versionMatch) { throw "No app version found in pubspec.yaml" }
$version = $versionMatch.Matches[0].Groups[1].Value
$source = [System.IO.File]::ReadAllText($mainCpp)
$pattern = 'window\.Create\(L"[^"]+",\s*origin,\s*size\)'
$replacement = 'window.Create(L"MP3 by Glasi v' + $version + '", origin, size)'
if (-not [regex]::IsMatch($source, $pattern)) {
    throw "Could not find the Windows window.Create caption in main.cpp"
}
$updated = [regex]::Replace($source, $pattern, $replacement, 1)
if ($updated -ne $source) {
    [System.IO.File]::WriteAllText($mainCpp, $updated, [System.Text.UTF8Encoding]::new($false))
}
Write-Host "Windows title bar: MP3 by Glasi v$version"
