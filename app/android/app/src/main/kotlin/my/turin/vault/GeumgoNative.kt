package my.turin.vault

/**
 * Rust 코어(librust_lib_app.so)로의 JNI 브리지.
 *
 * Flutter 엔진과 같은 프로세스·같은 .so를 사용하므로, Flutter UI에서 잠금 해제한
 * 볼트 상태(Rust 전역 static)를 그대로 공유한다. 자동완성 서비스는 이 함수들로
 * 잠금 여부를 확인하고 후보 자격증명을 JSON으로 받는다.
 */
object GeumgoNative {
    @Volatile private var loaded = false

    private fun ensureLoaded() {
        if (!loaded) {
            System.loadLibrary("rust_lib_app")
            loaded = true
        }
    }

    fun isVaultUnlocked(): Boolean {
        return try {
            ensureLoaded()
            isUnlocked()
        } catch (e: Throwable) {
            false
        }
    }

    /** 힌트(웹 도메인 또는 앱 패키지명)에 맞는 후보를 JSON 배열로 반환. */
    fun candidates(hint: String): String {
        return try {
            ensureLoaded()
            autofillCandidates(hint)
        } catch (e: Throwable) {
            "[]"
        }
    }

    private external fun isUnlocked(): Boolean
    private external fun autofillCandidates(hint: String): String
}
