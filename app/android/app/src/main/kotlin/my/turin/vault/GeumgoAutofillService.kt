package my.turin.vault

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import org.json.JSONArray

/**
 * 금고 자동완성 서비스. 다른 앱/브라우저의 로그인 화면에서 아이디·비밀번호를 채운다.
 *
 * - 볼트가 잠겨 있으면 "잠금 해제" 항목을 보여주고 탭하면 앱이 열린다.
 * - 잠금 해제 상태면 요청한 도메인/앱에 맞는 자격증명 목록을 제시한다.
 * 자격증명 조회는 GeumgoNative(JNI)를 통해 Rust 코어의 in-memory 볼트에서 직접 이뤄지며,
 * 자동완성용 별도 평문 저장은 없다(zero-knowledge 유지).
 */
@RequiresApi(Build.VERSION_CODES.O)
class GeumgoAutofillService : AutofillService() {

    private data class Parsed(
        var usernameId: AutofillId? = null,
        var passwordId: AutofillId? = null,
        var webDomain: String? = null,
    )

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val parsed = parseStructure(structure)
        if (parsed.usernameId == null && parsed.passwordId == null) {
            callback.onSuccess(null)
            return
        }
        val hint = parsed.webDomain
            ?: structure.activityComponent?.packageName
            ?: ""

        val builder = FillResponse.Builder()

        if (!GeumgoNative.isVaultUnlocked()) {
            // 잠금 해제 유도 데이터셋 — 탭하면 앱을 연다
            val presentation = simpleRemote("🔒 금고 잠금 해제")
            val ids = listOfNotNull(parsed.usernameId, parsed.passwordId).toTypedArray()
            val intent = Intent(this, MainActivity::class.java)
            val pi = PendingIntent.getActivity(
                this,
                1001,
                intent,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.setAuthentication(ids, pi.intentSender, presentation)
            callback.onSuccess(builder.build())
            return
        }

        val json = GeumgoNative.candidates(hint)
        val arr = try { JSONArray(json) } catch (e: Exception) { JSONArray() }
        if (arr.length() == 0) {
            callback.onSuccess(null)
            return
        }

        var added = 0
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val title = o.optString("title")
            val user = o.optString("username")
            val pass = o.optString("password")
            val label = if (user.isNotEmpty()) "$title  ·  $user" else title
            val presentation = simpleRemote(label)

            val ds = Dataset.Builder()
            var set = false
            parsed.usernameId?.let {
                ds.setValue(it, AutofillValue.forText(user), presentation)
                set = true
            }
            parsed.passwordId?.let {
                ds.setValue(it, AutofillValue.forText(pass), presentation)
                set = true
            }
            if (set) {
                builder.addDataset(ds.build())
                added++
            }
        }

        callback.onSuccess(if (added > 0) builder.build() else null)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // 저장 흐름은 향후 구현 — 지금은 채우기 전용
        callback.onSuccess()
    }

    private fun simpleRemote(text: String): RemoteViews {
        return RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, text)
        }
    }

    private fun parseStructure(structure: AssistStructure): Parsed {
        val p = Parsed()
        for (i in 0 until structure.windowNodeCount) {
            traverse(structure.getWindowNodeAt(i).rootViewNode, p)
        }
        return p
    }

    private fun traverse(node: AssistStructure.ViewNode, p: Parsed) {
        node.webDomain?.let { if (it.isNotEmpty()) p.webDomain = it }

        val id = node.autofillId
        if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT) {
            val hints = node.autofillHints
            var handled = false
            if (hints != null) {
                for (h in hints) {
                    val hl = h.lowercase()
                    when {
                        hl.contains("password") -> {
                            if (p.passwordId == null) p.passwordId = id
                            handled = true
                        }
                        hl.contains("username") || hl.contains("email") ||
                            hl.contains("phone") || hl.contains("name") -> {
                            if (p.usernameId == null) p.usernameId = id
                            handled = true
                        }
                    }
                }
            }
            if (!handled) {
                // 힌트가 없으면 입력 타입으로 추정
                if (isPasswordField(node.inputType)) {
                    if (p.passwordId == null) p.passwordId = id
                } else if (isTextInput(node.inputType) && p.usernameId == null) {
                    // 비밀번호보다 앞서 나오는 첫 텍스트 필드를 아이디 후보로
                    p.usernameId = id
                }
            }
        }

        for (i in 0 until node.childCount) {
            traverse(node.getChildAt(i), p)
        }
    }

    private fun isPasswordField(inputType: Int): Boolean {
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val cls = inputType and InputType.TYPE_MASK_CLASS
        return (cls == InputType.TYPE_CLASS_TEXT &&
            (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) ||
            (cls == InputType.TYPE_CLASS_NUMBER &&
                variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)
    }

    private fun isTextInput(inputType: Int): Boolean {
        val cls = inputType and InputType.TYPE_MASK_CLASS
        return cls == InputType.TYPE_CLASS_TEXT
    }
}
