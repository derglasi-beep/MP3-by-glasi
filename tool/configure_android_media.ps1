param(
  [string]$ManifestPath = "android/app/src/main/AndroidManifest.xml"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $ManifestPath)) { throw "AndroidManifest.xml wurde nicht gefunden: $ManifestPath" }
$content = Get-Content -Raw -Path $ManifestPath
function Add-IfMissing([string]$Text, [string]$Needle, [string]$Insertion, [string]$Anchor) {
  if ($Text -notmatch [regex]::Escape($Needle)) {
    if ($Text -notmatch [regex]::Escape($Anchor)) { throw "Anchor nicht gefunden: $Anchor" }
    return $Text.Replace($Anchor, $Insertion + [Environment]::NewLine + $Anchor)
  }
  return $Text
}
$content = Add-IfMissing $content "android.permission.WAKE_LOCK" '    <uses-permission android:name="android.permission.WAKE_LOCK" />' '<application'
$content = Add-IfMissing $content "android.permission.FOREGROUND_SERVICE" '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />' '<application'
$content = Add-IfMissing $content "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />' '<application'
$service = @'
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:exported="true"
            android:foregroundServiceType="mediaPlayback">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
'@
if ($content -notmatch 'com\.ryanheise\.audioservice\.AudioService') {
  $content = $content.Replace('</application>', $service + '    </application>')
}
Set-Content -Path $ManifestPath -Value $content -Encoding UTF8
Write-Host "Android Media Service wurde konfiguriert: $ManifestPath"
