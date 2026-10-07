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

    private var pendingMusicTracksResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getMusicTracks" -> resolveMusicTracks(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveMusicTracks(result: MethodChannel.Result) {
        val permission = audioReadPermission()
        if (permission == null ||
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        ) {
            queryMusicTracksAsync(result)
            return
        }

        if (pendingMusicTracksResult != null) {
            result.error(
                "permission_pending",
                "Die Audio-Berechtigung wird bereits angefordert.",
                null
            )
            return
        }

        pendingMusicTracksResult = result
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

    private fun queryMusicTracksAsync(result: MethodChannel.Result) {
        Thread {
            try {
                val tracks = queryMusicTracks()
                runOnUiThread { result.success(tracks) }
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

    private fun queryMusicTracks(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val projection = mutableListOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.IS_MUSIC,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.YEAR
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        }

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.ARTIST} COLLATE NOCASE, " +
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE"
        )?.use { cursor ->
            val dataIndex = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            val titleIndex = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val artistIndex = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val albumIndex = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val durationIndex = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val yearIndex = cursor.getColumnIndex(MediaStore.Audio.Media.YEAR)
            val relativePathIndex =
                cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)

            while (cursor.moveToNext()) {
                if (dataIndex < 0) continue

                val path = cursor.getString(dataIndex) ?: continue
                if (path.isBlank()) continue

                val isInMusicDirectory =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        relativePathIndex >= 0
                    ) {
                        val relativePath =
                            cursor.getString(relativePathIndex).orEmpty()
                                .replace('\\', '/')
                                .trimStart('/')
                        relativePath.equals("Music", ignoreCase = true) ||
                            relativePath.startsWith("Music/", ignoreCase = true)
                    } else {
                        val normalized = path.replace('\\', '/')
                        normalized.contains("/Music/", ignoreCase = true)
                    }

                if (!isInMusicDirectory) continue

                result.add(
                    mapOf(
                        "path" to path,
                        "title" to if (titleIndex >= 0) cursor.getString(titleIndex) else null,
                        "artist" to if (artistIndex >= 0) cursor.getString(artistIndex) else null,
                        "album" to if (albumIndex >= 0) cursor.getString(albumIndex) else null,
                        "durationMs" to if (durationIndex >= 0) cursor.getLong(durationIndex) else null,
                        "year" to if (yearIndex >= 0) cursor.getInt(yearIndex) else null
                    )
                )
            }
        }

        return result.distinctBy { it["path"] as? String }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != AUDIO_PERMISSION_REQUEST) return

        val result = pendingMusicTracksResult ?: return
        pendingMusicTracksResult = null

        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            queryMusicTracksAsync(result)
        } else {
            result.error(
                "permission_denied",
                "Zugriff auf Musikdateien wurde nicht erlaubt.",
                null
            )
        }
    }
}
