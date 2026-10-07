package com.example.mp3_by_glasi

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
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

    private var pendingMusicFilesResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMusicFiles" -> resolveMusicFiles(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveMusicFiles(result: MethodChannel.Result) {
        val permission = audioReadPermission()
        if (permission == null ||
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        ) {
            queryMusicFilesAsync(result)
            return
        }

        if (pendingMusicFilesResult != null) {
            result.error(
                "permission_pending",
                "Die Audio-Berechtigung wird bereits angefordert.",
                null
            )
            return
        }

        pendingMusicFilesResult = result
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

    private fun queryMusicFilesAsync(result: MethodChannel.Result) {
        Thread {
            try {
                val files = queryMusicFiles()
                runOnUiThread { result.success(files) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "media_store_error",
                        e.message ?: "Android-Musikbibliothek konnte nicht gelesen werden.",
                        null
                    )
                }
            }
        }.start()
    }

    private fun queryMusicFiles(): List<String> {
        val result = mutableListOf<String>()
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.IS_MUSIC
        )

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.ARTIST} COLLATE NOCASE, " +
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE"
        )?.use { cursor ->
            val dataIndex = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            while (cursor.moveToNext()) {
                if (dataIndex < 0) continue
                val path = cursor.getString(dataIndex) ?: continue
                if (path.isNotBlank()) result.add(path)
            }
        }

        return result.distinct()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != AUDIO_PERMISSION_REQUEST) return

        val result = pendingMusicFilesResult ?: return
        pendingMusicFilesResult = null

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            queryMusicFilesAsync(result)
        } else {
            result.error(
                "permission_denied",
                "Zugriff auf Musikdateien wurde nicht erlaubt.",
                null
            )
        }
    }
}
