package com.example.mp3_by_glasi

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CHANNEL = "de.glasi.mp3byglasi/storage"
        private const val AUDIO_PERMISSION_REQUEST = 4107
    }

    private var pendingMusicDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMusicDirectory" -> resolveMusicDirectory(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveMusicDirectory(result: MethodChannel.Result) {
        val permission = audioReadPermission()
        if (permission == null ||
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(publicMusicDirectory())
            return
        }

        if (pendingMusicDirectoryResult != null) {
            result.error(
                "permission_pending",
                "Die Audio-Berechtigung wird bereits angefordert.",
                null
            )
            return
        }

        pendingMusicDirectoryResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(permission),
            AUDIO_PERMISSION_REQUEST
        )
    }

    private fun audioReadPermission(): String? {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                Manifest.permission.READ_MEDIA_AUDIO
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                Manifest.permission.READ_EXTERNAL_STORAGE
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun publicMusicDirectory(): String {
        return Environment
            .getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
            .absolutePath
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != AUDIO_PERMISSION_REQUEST) return

        val result = pendingMusicDirectoryResult ?: return
        pendingMusicDirectoryResult = null

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(publicMusicDirectory())
        } else {
            result.error(
                "permission_denied",
                "Zugriff auf Musikdateien wurde nicht erlaubt.",
                null
            )
        }
    }
}
