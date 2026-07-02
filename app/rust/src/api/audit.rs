//! 보안 점검 API. 로컬 점검은 core::audit, 유출 검사는 HIBP Pwned Passwords
//! range API를 k-익명성으로 호출한다 — 비밀번호의 SHA1 앞 5자만 전송하고
//! 나머지는 로컬에서 대조하므로 전체 비밀번호도, 전체 해시도 서버로 가지 않는다.

use std::collections::HashMap;

use anyhow::{anyhow, Result};
use sha1::{Digest, Sha1};

use super::vault::VAULT;
use geumgo_core::Vault;

fn with_vault<T>(f: impl FnOnce(&Vault) -> Result<T>) -> Result<T> {
    let guard = VAULT.lock().unwrap();
    match guard.as_ref() {
        Some(v) => f(v),
        None => Err(anyhow!("볼트가 잠겨 있습니다")),
    }
}

// ---- 로컬 점검 DTO ----

pub struct AuditEntryRefDto {
    pub id: String,
    pub title: String,
    pub detail: String,
}

pub struct ReuseGroupDto {
    pub entries: Vec<AuditEntryRefDto>,
}

pub struct AuditReportDto {
    pub score: u8,
    pub total: usize,
    pub with_password: usize,
    pub weak: Vec<AuditEntryRefDto>,
    pub reused: Vec<ReuseGroupDto>,
    pub stale: Vec<AuditEntryRefDto>,
    pub empty: Vec<AuditEntryRefDto>,
}

fn map_ref(r: geumgo_core::AuditEntryRef) -> AuditEntryRefDto {
    AuditEntryRefDto {
        id: r.id,
        title: r.title,
        detail: r.detail,
    }
}

/// 로컬 보안 점검 (네트워크 없음).
pub fn audit_vault() -> Result<AuditReportDto> {
    with_vault(|v| {
        let r = v.audit().map_err(|e| anyhow!(e.to_string()))?;
        Ok(AuditReportDto {
            score: r.score,
            total: r.total,
            with_password: r.with_password,
            weak: r.weak.into_iter().map(map_ref).collect(),
            reused: r
                .reused
                .into_iter()
                .map(|g| ReuseGroupDto {
                    entries: g.entries.into_iter().map(map_ref).collect(),
                })
                .collect(),
            stale: r.stale.into_iter().map(map_ref).collect(),
            empty: r.empty.into_iter().map(map_ref).collect(),
        })
    })
}

// ---- 유출 검사 (HIBP k-익명성) ----

pub struct BreachHitDto {
    pub id: String,
    pub title: String,
    /// 이 비밀번호가 유출 데이터에서 발견된 횟수
    pub count: u64,
}

pub struct BreachReportDto {
    pub checked: usize,
    pub hits: Vec<BreachHitDto>,
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(std::time::Duration::from_secs(20))
        .build()
}

/// 비밀번호 하나의 유출 횟수를 조회. prefix(5자)만 전송.
fn breach_count(agent: &ureq::Agent, password: &str) -> Result<u64> {
    let hash = hex::encode_upper(Sha1::digest(password.as_bytes()));
    let (prefix, suffix) = hash.split_at(5);
    let body = agent
        .get(&format!("https://api.pwnedpasswords.com/range/{prefix}"))
        // 응답 패딩 요청 — 반환 크기로 추측당하는 것 방지
        .set("Add-Padding", "true")
        .call()
        .map_err(|e| anyhow!("유출 DB에 연결할 수 없습니다: {e}"))?
        .into_string()
        .map_err(|e| anyhow!("응답 읽기 실패: {e}"))?;
    for line in body.lines() {
        // 형식: SUFFIX:COUNT
        let Some((suf, cnt)) = line.trim().split_once(':') else { continue };
        if suf.eq_ignore_ascii_case(suffix) {
            return Ok(cnt.trim().parse().unwrap_or(0));
        }
    }
    Ok(0)
}

/// 볼트의 모든 비밀번호를 유출 검사. 같은 비밀번호는 한 번만 조회한다.
pub fn check_breaches() -> Result<BreachReportDto> {
    let entries = with_vault(|v| v.list_entries().map_err(|e| anyhow!(e.to_string())))?;
    let agent = agent();

    // 비밀번호 → 유출 횟수 캐시 (중복 요청 방지)
    let mut cache: HashMap<String, u64> = HashMap::new();
    let mut hits = Vec::new();
    let mut checked = 0;

    for e in &entries {
        if e.password.is_empty() {
            continue;
        }
        checked += 1;
        let count = match cache.get(&e.password) {
            Some(c) => *c,
            None => {
                let c = breach_count(&agent, &e.password)?;
                cache.insert(e.password.clone(), c);
                c
            }
        };
        if count > 0 {
            hits.push(BreachHitDto {
                id: e.id.clone(),
                title: e.title.clone(),
                count,
            });
        }
    }
    hits.sort_by(|a, b| b.count.cmp(&a.count));
    Ok(BreachReportDto { checked, hits })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 네트워크 필요: cargo test -p rust_lib_app -- --ignored breach
    #[test]
    #[ignore]
    fn hibp_flags_known_leaked_password() {
        let agent = agent();
        // "password"는 유출 데이터에 수백만 건 존재
        let leaked = breach_count(&agent, "password").unwrap();
        assert!(leaked > 1000, "expected many hits, got {leaked}");
        // 랜덤에 가까운 강한 문자열은 0이어야 함
        let safe = breach_count(&agent, "k9#mQ2$vLx7@pW4z!bN8-geumgo-unique").unwrap();
        assert_eq!(safe, 0);
    }
}
