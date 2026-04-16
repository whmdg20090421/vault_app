package com.tianyanmczj.vault

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vault/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "detectSecurityLevel" -> result.success(detectSecurityLevel())
                else -> result.notImplemented()
            }
        }
    }

    private fun baseSpec(alias: String): KeyGenParameterSpec {
        return KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
    }

    private fun detectSecurityLevel(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return "level2"
        }

        val alias = "vault_security_probe"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

        fun safeDelete() {
            try {
                if (keyStore.containsAlias(alias)) {
                    keyStore.deleteEntry(alias)
                }
            } catch (_: Exception) {}
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    val generator =
                        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    val spec = KeyGenParameterSpec.Builder(
                        alias,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .setIsStrongBoxBacked(true)
                        .build()
                    generator.init(spec)
                    generator.generateKey()
                    return "level1"
                } catch (_: Exception) {
                    safeDelete()
                }
            }

            val generator =
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(baseSpec(alias))
            generator.generateKey()

            val key = keyStore.getKey(alias, null) as? SecretKey ?: return "level2"
            val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            return if (info.isInsideSecureHardware) "level1" else "level2"
        } catch (_: Exception) {
            return "level2"
        } finally {
            safeDelete()
        }
    }
}
