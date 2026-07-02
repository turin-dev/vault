//! 보안 점검 (Watchtower 대체). 잠금 해제된 엔트리들을 받아
//! 취약·재사용·오래된 비밀번호를 찾고 0~100 보안 점수를 계산한다.
//! 전부 로컬 계산 — 네트워크 없음. 유출 검사(HIBP)는 앱 계층에서 별도로.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::generator::evaluate_strength;
use crate::model::Entry;

/// 비밀번호가 "오래됨"으로 간주되는 기준 (초). 180일.
pub const STALE_SECS: i64 = 180 * 24 * 60 * 60;
/// zxcvbn 점수가 이 값 이하이면 취약.
pub const WEAK_SCORE_MAX: u8 = 2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntryRef {
    pub id: String,
    pub title: String,
    /// 이 항목에만 해당하는 세부 (취약도 점수, 오래된 일수 등)
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReuseGroup {
    /// 이 비밀번호를 공유하는 항목들
    pub entries: Vec<AuditEntryRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditReport {
    /// 0(위험) ~ 100(안전)
    pub score: u8,
    pub total: usize,
    /// 비밀번호가 있는 항목 수 (점수 분모)
    pub with_password: usize,
    pub weak: Vec<AuditEntryRef>,
    pub reused: Vec<ReuseGroup>,
    pub stale: Vec<AuditEntryRef>,
    /// 비밀번호가 비어 있는 항목
    pub empty: Vec<AuditEntryRef>,
}

fn plural_days(secs: i64) -> i64 {
    secs / (24 * 60 * 60)
}

/// 엔트리 목록을 점검. `now`는 오래됨 판정 기준 (unix seconds).
pub fn audit(entries: &[Entry], now: i64) -> AuditReport {
    let total = entries.len();
    let mut weak = Vec::new();
    let mut stale = Vec::new();
    let mut empty = Vec::new();

    // 재사용: 비밀번호값 → 항목들
    let mut by_password: HashMap<&str, Vec<&Entry>> = HashMap::new();
    let mut with_password = 0;

    for e in entries {
        if e.password.is_empty() {
            empty.push(AuditEntryRef {
                id: e.id.clone(),
                title: e.title.clone(),
                detail: "비밀번호 없음".into(),
            });
            continue;
        }
        with_password += 1;
        by_password.entry(e.password.as_str()).or_default().push(e);

        let strength = evaluate_strength(&e.password);
        if strength.score <= WEAK_SCORE_MAX {
            weak.push(AuditEntryRef {
                id: e.id.clone(),
                title: e.title.clone(),
                detail: format!("강도 {}/4", strength.score),
            });
        }

        if e.updated_at > 0 && now - e.updated_at > STALE_SECS {
            let days = plural_days(now - e.updated_at);
            stale.push(AuditEntryRef {
                id: e.id.clone(),
                title: e.title.clone(),
                detail: format!("{days}일 전 변경"),
            });
        }
    }

    // 재사용 그룹 (2개 이상 공유). 큰 그룹부터.
    let mut reused: Vec<ReuseGroup> = by_password
        .into_values()
        .filter(|v| v.len() > 1)
        .map(|v| ReuseGroup {
            entries: v
                .iter()
                .map(|e| AuditEntryRef {
                    id: e.id.clone(),
                    title: e.title.clone(),
                    detail: format!("{}개 항목에서 재사용", v.len()),
                })
                .collect(),
        })
        .collect();
    reused.sort_by(|a, b| b.entries.len().cmp(&a.entries.len()));

    let reused_count: usize = reused.iter().map(|g| g.entries.len()).sum();

    let score = compute_score(with_password, weak.len(), reused_count, stale.len());

    AuditReport {
        score,
        total,
        with_password,
        weak,
        reused,
        stale,
        empty,
    }
}

/// 감점식 점수. 취약/재사용이 강한 감점, 오래됨은 약한 감점.
fn compute_score(with_password: usize, weak: usize, reused: usize, stale: usize) -> u8 {
    if with_password == 0 {
        return 100;
    }
    let n = with_password as f64;
    // 각 문제 비율에 가중치를 곱해 감점
    let weak_ratio = weak as f64 / n;
    let reused_ratio = reused as f64 / n;
    let stale_ratio = stale as f64 / n;

    let penalty = weak_ratio * 55.0 + reused_ratio * 35.0 + stale_ratio * 10.0;
    let score = (100.0 - penalty).clamp(0.0, 100.0);
    score.round() as u8
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, title: &str, password: &str, updated_at: i64) -> Entry {
        Entry {
            id: id.into(),
            title: title.into(),
            username: String::new(),
            password: password.into(),
            url: String::new(),
            notes: String::new(),
            totp: String::new(),
            tags: vec![],
            favorite: false,
            created_at: 0,
            updated_at,
        }
    }

    #[test]
    fn perfect_vault_scores_high() {
        let now = 1_000_000_000;
        let entries = vec![
            entry("1", "A", "k9#mQ2$vLx7@pW4z!bN8", now),
            entry("2", "B", "Zr4!tY7@wQ2#nM9$xK1p", now),
        ];
        let r = audit(&entries, now);
        assert!(r.weak.is_empty());
        assert!(r.reused.is_empty());
        assert_eq!(r.score, 100);
    }

    #[test]
    fn detects_weak_reused_stale() {
        let now = 1_000_000_000;
        let old = now - STALE_SECS - 1;
        let entries = vec![
            entry("1", "A", "password", now),   // 취약
            entry("2", "B", "password", now),   // 취약 + 재사용
            entry("3", "C", "k9#mQ2$vLx7@pW4z!bN8", old), // 오래됨
        ];
        let r = audit(&entries, now);
        assert_eq!(r.weak.len(), 2);
        assert_eq!(r.reused.len(), 1);
        assert_eq!(r.reused[0].entries.len(), 2);
        assert_eq!(r.stale.len(), 1);
        assert!(r.score < 60, "score was {}", r.score);
    }

    #[test]
    fn empty_password_tracked_not_scored() {
        let now = 1_000_000_000;
        let entries = vec![
            entry("1", "A", "", now),
            entry("2", "B", "k9#mQ2$vLx7@pW4z!bN8", now),
        ];
        let r = audit(&entries, now);
        assert_eq!(r.empty.len(), 1);
        assert_eq!(r.with_password, 1);
        assert_eq!(r.score, 100);
    }
}
