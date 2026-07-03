package my.turin.vault

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import android.widget.inline.InlinePresentationSpec
import androidx.annotation.RequiresApi
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import org.json.JSONArray

/**
 * Vault 자동완성 서비스. 다른 앱/브라우저의 로그인 화면에서 아이디·비밀번호를 채운다.
 *
 * 키보드 추천 줄(인라인 자동완성, Android 11+)과 기존 드롭다운을 모두 지원한다.
 * - 볼트가 잠겨 있으면 "Vault" 항목을 보여주고 탭하면 앱이 열린다.
 * - 잠금 해제 상태면 요청한 도메인/앱에 맞는 자격증명을 제시한다.
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

        val inlineSpecs: List<InlinePresentationSpec>? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                request.inlineSuggestionsRequest?.inlinePresentationSpecs
            } else {
                null
            }

        val builder = FillResponse.Builder()

        if (!GeumgoNative.isVaultUnlocked()) {
            // 잠금 상태: 탭하면 앱을 여는 인증 데이터셋. 인라인으로도 노출.
            val pi = PendingIntent.getActivity(
                this,
                1001,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val presentation = simpleRemote("Vault")
            val ds = Dataset.Builder()
            val spec = inlineSpecs?.getOrNull(0)
            val inline = spec?.let { buildInline(it, "Vault", null, pi) }
            var any = false
            for (id in listOfNotNull(parsed.usernameId, parsed.passwordId)) {
                if (inline != null) {
                    ds.setValue(id, null, presentation, inline)
                } else {
                    ds.setValue(id, null, presentation)
                }
                any = true
            }
            if (any) {
                ds.setAuthentication(pi.intentSender)
                builder.addDataset(ds.build())
                callback.onSuccess(builder.build())
            } else {
                callback.onSuccess(null)
            }
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

            val spec = inlineSpecs?.getOrNull(i)
            val inline = spec?.let {
                val pi = PendingIntent.getActivity(
                    this,
                    2000 + i,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                buildInline(it, title.ifEmpty { "Vault" }, if (user.isNotEmpty()) user else null, pi)
            }

            val ds = Dataset.Builder()
            var set = false
            parsed.usernameId?.let {
                if (inline != null) {
                    ds.setValue(it, AutofillValue.forText(user), presentation, inline)
                } else {
                    ds.setValue(it, AutofillValue.forText(user), presentation)
                }
                set = true
            }
            parsed.passwordId?.let {
                if (inline != null) {
                    ds.setValue(it, AutofillValue.forText(pass), presentation, inline)
                } else {
                    ds.setValue(it, AutofillValue.forText(pass), presentation)
                }
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

    /** 키보드 추천 줄에 표시할 인라인 프레젠테이션 생성 (Android 11+). */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun buildInline(
        spec: InlinePresentationSpec,
        title: String,
        subtitle: String?,
        pendingIntent: PendingIntent,
    ): InlinePresentation? {
        // 스타일이 v1 인라인 UI를 지원하는지 확인
        val versions = UiVersions.getVersions(spec.style)
        if (!versions.contains(UiVersions.INLINE_UI_VERSION_1)) return null

        val contentBuilder = InlineSuggestionUi.newContentBuilder(pendingIntent)
            .setTitle(title)
        if (!subtitle.isNullOrEmpty()) contentBuilder.setSubtitle(subtitle)
        try {
            contentBuilder.setStartIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
        } catch (e: Throwable) {
            // 아이콘 실패는 무시
        }
        val slice = contentBuilder.build().slice
        return InlinePresentation(slice, spec, false)
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
                if (isPasswordField(node.inputType)) {
                    if (p.passwordId == null) p.passwordId = id
                } else if (isTextInput(node.inputType) && p.usernameId == null) {
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
