//! Android 자동완성용 JNI 브리지.
//!
//! AutofillService(Kotlin)는 Flutter가 로드한 것과 **같은** `librust_lib_app.so`를
//! 같은 프로세스에서 사용하므로, 잠금 해제된 볼트 상태(전역 VAULT static)를 공유한다.
//! 여기 함수들은 그 전역 상태를 읽어 자동완성 후보를 넘겨준다.
//! 볼트가 잠겨 있으면 빈 목록을 돌려주고, Kotlin 측이 "잠금 해제" 흐름을 띄운다.
#![cfg(target_os = "android")]

use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jstring, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;
use serde_json::json;

use super::vault::VAULT;

#[no_mangle]
pub extern "system" fn Java_kr_scin_app_GeumgoNative_isUnlocked(
    _env: JNIEnv,
    _class: JClass,
) -> jboolean {
    if VAULT.lock().unwrap().is_some() {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[no_mangle]
pub extern "system" fn Java_kr_scin_app_GeumgoNative_autofillCandidates<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    hint: JString<'l>,
) -> jstring {
    let hint: String = env
        .get_string(&hint)
        .map(|s| s.into())
        .unwrap_or_default();
    let out = candidates_json(&hint);
    env.new_string(out)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// url에서 등록 도메인의 핵심 토큰(예: github.com → "github")을 추출.
fn host_tokens(url: &str) -> Vec<String> {
    let lower = url.to_lowercase();
    let after_scheme = lower.split("://").last().unwrap_or(&lower);
    let host = after_scheme
        .split(['/', '?', '#', ':'])
        .next()
        .unwrap_or("");
    host.split('.')
        .filter(|p| p.len() >= 3 && !matches!(*p, "www" | "com" | "net" | "org" | "co" | "kr" | "io"))
        .map(|s| s.to_string())
        .collect()
}

fn candidates_json(hint: &str) -> String {
    let guard = VAULT.lock().unwrap();
    let Some(v) = guard.as_ref() else {
        return "[]".to_string();
    };
    let entries = match v.list_entries() {
        Ok(e) => e,
        Err(_) => return "[]".to_string(),
    };
    let h = hint.to_lowercase();

    let mut scored: Vec<(i32, serde_json::Value)> = Vec::new();
    for e in &entries {
        if e.password.is_empty() {
            continue;
        }
        let title = e.title.to_lowercase();
        let mut score = 0;

        // URL 도메인 토큰이 힌트(도메인/패키지명)에 포함되면 강한 매칭
        for tok in host_tokens(&e.url) {
            if h.contains(&tok) {
                score += 10;
            }
        }
        // 제목 토큰 매칭
        for tok in title.split_whitespace() {
            if tok.len() >= 3 && h.contains(tok) {
                score += 5;
            }
        }
        // 힌트가 제목을 통째로 포함
        if !title.is_empty() && h.contains(&title) {
            score += 6;
        }

        if score > 0 {
            scored.push((
                score,
                json!({
                    "id": e.id,
                    "title": e.title,
                    "username": e.username,
                    "password": e.password,
                }),
            ));
        }
    }

    // 매칭이 하나도 없으면 전체를 낮은 우선순위로 제공 (수동 선택 가능)
    if scored.is_empty() {
        for e in &entries {
            if e.password.is_empty() {
                continue;
            }
            scored.push((
                0,
                json!({
                    "id": e.id,
                    "title": e.title,
                    "username": e.username,
                    "password": e.password,
                }),
            ));
        }
    }

    scored.sort_by(|a, b| b.0.cmp(&a.0));
    let list: Vec<serde_json::Value> = scored.into_iter().take(20).map(|(_, v)| v).collect();
    serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string())
}
