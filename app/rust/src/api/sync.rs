//! 동기화 클라이언트. 서버는 암호문 블롭만 저장하는 zero-knowledge 서버
//! (geumgo-server). 서버 설정은 볼트 meta에 저장된다:
//!   sync.url / sync.user / sync.since / sync.last_at

use anyhow::{anyhow, bail, Result};
use geumgo_core::crypto::{self, KdfParams};
use geumgo_core::{EncryptedEntry, Vault};
use serde::Deserialize;

use super::vault::VAULT;

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}

fn http_err(e: ureq::Error) -> anyhow::Error {
    match e {
        ureq::Error::Status(code, resp) => {
            let body = resp.into_string().unwrap_or_default();
            let body = body.trim();
            match code {
                401 => anyhow!("서버 인증 실패 — 사용자명 또는 마스터 비밀번호가 다릅니다"),
                404 => anyhow!("서버에 없는 사용자입니다"),
                409 => anyhow!("이미 존재하는 사용자명입니다"),
                _ => anyhow!("서버 오류 {code}: {body}"),
            }
        }
        e => anyhow!("서버에 연결할 수 없습니다: {e}"),
    }
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(std::time::Duration::from_secs(30))
        .build()
}

fn normalize_url(url: &str) -> Result<String> {
    let url = url.trim().trim_end_matches('/').to_string();
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        bail!("서버 주소는 https:// 로 시작해야 합니다");
    }
    Ok(url)
}

fn valid_username(u: &str) -> bool {
    (3..=64).contains(&u.len())
        && u.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "._-@".contains(c))
}

pub struct SyncConfigDto {
    pub url: String,
    pub username: String,
    pub since_revision: i64,
    pub last_sync_at: i64,
}

pub struct SyncResultDto {
    pub pushed: u32,
    pub pulled: u32,
    pub server_revision: i64,
}

fn with_vault<T>(f: impl FnOnce(&Vault) -> Result<T>) -> Result<T> {
    let guard = VAULT.lock().unwrap();
    match guard.as_ref() {
        Some(v) => f(v),
        None => Err(anyhow!("볼트가 잠겨 있습니다")),
    }
}

/// 현재 볼트의 동기화 설정 (없으면 None).
pub fn get_sync_config() -> Result<Option<SyncConfigDto>> {
    with_vault(|v| {
        let url = v.get_meta("sync.url").map_err(|e| anyhow!(e.to_string()))?;
        let user = v.get_meta("sync.user").map_err(|e| anyhow!(e.to_string()))?;
        match (url, user) {
            (Some(url), Some(username)) => Ok(Some(SyncConfigDto {
                url,
                username,
                since_revision: v
                    .get_meta("sync.since")
                    .ok()
                    .flatten()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0),
                last_sync_at: v
                    .get_meta("sync.last_at")
                    .ok()
                    .flatten()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0),
            })),
            _ => Ok(None),
        }
    })
}

/// 서버에 새 계정 등록 후 이 볼트를 연결.
pub fn register_account(url: String, username: String) -> Result<()> {
    let url = normalize_url(&url)?;
    if !valid_username(&username) {
        bail!("사용자명은 3~64자의 소문자/숫자/._-@ 만 가능합니다");
    }
    let (auth_token, header_json) = with_vault(|v| {
        Ok((
            v.auth_token.clone(),
            v.header_json().map_err(|e| anyhow!(e.to_string()))?,
        ))
    })?;
    let header: serde_json::Value = serde_json::from_str(&header_json)?;
    agent()
        .post(&format!("{url}/api/register"))
        .send_json(serde_json::json!({
            "username": username,
            "auth_token": auth_token,
            "header": header,
        }))
        .map_err(http_err)?;
    with_vault(|v| {
        v.put_meta("sync.url", &url).map_err(|e| anyhow!(e.to_string()))?;
        v.put_meta("sync.user", &username).map_err(|e| anyhow!(e.to_string()))?;
        v.put_meta("sync.since", "0").map_err(|e| anyhow!(e.to_string()))?;
        Ok(())
    })?;
    // 첫 업로드
    sync_now()?;
    Ok(())
}

#[derive(Deserialize)]
struct SyncResp {
    server_revision: i64,
    entries: Vec<EncryptedEntry>,
}

/// push + pull 한 사이클.
pub fn sync_now() -> Result<SyncResultDto> {
    let (url, username, auth_token, since, local) = with_vault(|v| {
        let url = v
            .get_meta("sync.url")
            .ok()
            .flatten()
            .ok_or_else(|| anyhow!("동기화가 설정되지 않았습니다"))?;
        let user = v
            .get_meta("sync.user")
            .ok()
            .flatten()
            .ok_or_else(|| anyhow!("동기화가 설정되지 않았습니다"))?;
        let since: i64 = v
            .get_meta("sync.since")
            .ok()
            .flatten()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        let local = v.export_encrypted().map_err(|e| anyhow!(e.to_string()))?;
        Ok((url, user, v.auth_token.clone(), since, local))
    })?;

    let pushed = local.len() as u32;
    let resp: SyncResp = agent()
        .post(&format!("{url}/api/sync"))
        .set("x-user", &username)
        .set("x-auth", &auth_token)
        .send_json(serde_json::json!({
            "since_revision": since,
            "entries": local,
        }))
        .map_err(http_err)?
        .into_json()
        .map_err(|e| anyhow!("서버 응답 파싱 실패: {e}"))?;

    with_vault(|v| {
        let applied = v
            .import_encrypted(&resp.entries)
            .map_err(|e| anyhow!(e.to_string()))?;
        // 서버가 부여한 리비전 반영
        for e in &resp.entries {
            v.set_revision(&e.id, e.revision)
                .map_err(|err| anyhow!(err.to_string()))?;
        }
        v.put_meta("sync.since", &resp.server_revision.to_string())
            .map_err(|e| anyhow!(e.to_string()))?;
        v.put_meta("sync.last_at", &now_secs().to_string())
            .map_err(|e| anyhow!(e.to_string()))?;
        Ok(SyncResultDto {
            pushed,
            pulled: applied,
            server_revision: resp.server_revision,
        })
    })
}

#[derive(Deserialize)]
struct Prelogin {
    kdf: KdfParams,
    salt_b64: String,
}

/// 새 기기 합류: 서버 계정의 헤더로 로컬 볼트를 만들고 첫 동기화까지 수행.
pub fn join_remote_vault(
    path: String,
    url: String,
    username: String,
    password: String,
) -> Result<()> {
    let url = normalize_url(&url)?;
    if std::path::Path::new(&path).exists() {
        bail!("이 기기에 이미 볼트가 있습니다");
    }

    // 1) prelogin으로 salt/KDF 수신 → 인증 토큰 유도 (비밀번호는 기기 밖으로 안 나감)
    let pre: Prelogin = agent()
        .get(&format!("{url}/api/prelogin"))
        .query("username", &username)
        .call()
        .map_err(http_err)?
        .into_json()
        .map_err(|e| anyhow!("서버 응답 파싱 실패: {e}"))?;
    let salt = {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD
            .decode(&pre.salt_b64)
            .map_err(|e| anyhow!("서버 salt 형식 오류: {e}"))?
    };
    let auth_token = crypto::auth_token_for(&password, &salt, &pre.kdf)
        .map_err(|e| anyhow!(e.to_string()))?;

    // 2) 인증된 헤더 다운로드
    let header: serde_json::Value = agent()
        .get(&format!("{url}/api/vault/header"))
        .set("x-user", &username)
        .set("x-auth", &auth_token)
        .call()
        .map_err(http_err)?
        .into_json()
        .map_err(|e| anyhow!("서버 응답 파싱 실패: {e}"))?;

    // 3) 헤더로 로컬 볼트 생성 (비밀번호 검증 포함) 후 설정 저장
    let vault = Vault::create_from_header(&path, &header.to_string(), &password)
        .map_err(|e| anyhow!(e.to_string()))?;
    vault.put_meta("sync.url", &url).map_err(|e| anyhow!(e.to_string()))?;
    vault
        .put_meta("sync.user", &username)
        .map_err(|e| anyhow!(e.to_string()))?;
    vault.put_meta("sync.since", "0").map_err(|e| anyhow!(e.to_string()))?;
    *VAULT.lock().unwrap() = Some(vault);

    // 4) 첫 pull
    sync_now()?;
    Ok(())
}
