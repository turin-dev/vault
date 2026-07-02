//! 비밀번호 생성기. OsRng + 거절 샘플링(modulo bias 제거),
//! 선택된 문자 클래스가 각각 최소 1회 등장하도록 보장.

use rand_core::{OsRng, RngCore};

use crate::error::{CoreError, Result};

const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS: &str = "0123456789";
const SYMBOLS: &str = "!@#$%^&*()-_=+[]{};:,.<>?";
/// 헷갈리는 문자: l, I, 1, O, 0, o 등
const AMBIGUOUS: &str = "lI1O0o5S8B";

#[derive(Debug, Clone)]
pub struct GenOptions {
    pub length: u32,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
    pub exclude_ambiguous: bool,
}

impl Default for GenOptions {
    fn default() -> Self {
        Self { length: 20, lower: true, upper: true, digits: true, symbols: true, exclude_ambiguous: false }
    }
}

/// [0, n) 균등 난수 — 거절 샘플링으로 modulo bias 제거.
fn uniform(n: u32) -> u32 {
    debug_assert!(n > 0);
    let zone = u32::MAX - (u32::MAX % n);
    loop {
        let r = OsRng.next_u32();
        if r < zone {
            return r % n;
        }
    }
}

fn pick(chars: &[char]) -> char {
    chars[uniform(chars.len() as u32) as usize]
}

pub fn generate_password(opts: &GenOptions) -> Result<String> {
    let filter = |s: &str| -> Vec<char> {
        s.chars()
            .filter(|c| !opts.exclude_ambiguous || !AMBIGUOUS.contains(*c))
            .collect()
    };
    let mut classes: Vec<Vec<char>> = Vec::new();
    if opts.lower {
        classes.push(filter(LOWER));
    }
    if opts.upper {
        classes.push(filter(UPPER));
    }
    if opts.digits {
        classes.push(filter(DIGITS));
    }
    if opts.symbols {
        classes.push(filter(SYMBOLS));
    }
    if classes.is_empty() {
        return Err(CoreError::InvalidArg("문자 클래스를 하나 이상 선택해야 함".into()));
    }
    let len = opts.length as usize;
    if len < classes.len() || len < 4 {
        return Err(CoreError::InvalidArg("길이가 너무 짧음".into()));
    }

    let all: Vec<char> = classes.iter().flatten().copied().collect();
    // 각 클래스에서 1자씩 확보 후 나머지는 전체 풀에서
    let mut chars: Vec<char> = classes.iter().map(|c| pick(c)).collect();
    while chars.len() < len {
        chars.push(pick(&all));
    }
    // Fisher-Yates 셔플 (OsRng)
    for i in (1..chars.len()).rev() {
        let j = uniform((i + 1) as u32) as usize;
        chars.swap(i, j);
    }
    Ok(chars.into_iter().collect())
}

/// zxcvbn 기반 강도 평가. score: 0(최악)~4(최상).
pub struct Strength {
    pub score: u8,
    pub crack_time_display: String,
    pub warning: String,
    pub suggestions: Vec<String>,
}

pub fn evaluate_strength(password: &str) -> Strength {
    let e = zxcvbn::zxcvbn(password, &[]);
    let (warning, suggestions) = match e.feedback() {
        Some(f) => (
            f.warning().map(|w| w.to_string()).unwrap_or_default(),
            f.suggestions().iter().map(|s| s.to_string()).collect(),
        ),
        None => (String::new(), Vec::new()),
    };
    Strength {
        score: u8::from(e.score()),
        crack_time_display: e
            .crack_times()
            .offline_slow_hashing_1e4_per_second()
            .to_string(),
        warning,
        suggestions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn respects_length_and_classes() {
        let opts = GenOptions { length: 24, ..Default::default() };
        for _ in 0..50 {
            let p = generate_password(&opts).unwrap();
            assert_eq!(p.chars().count(), 24);
            assert!(p.chars().any(|c| c.is_ascii_lowercase()));
            assert!(p.chars().any(|c| c.is_ascii_uppercase()));
            assert!(p.chars().any(|c| c.is_ascii_digit()));
            assert!(p.chars().any(|c| SYMBOLS.contains(c)));
        }
    }

    #[test]
    fn exclude_ambiguous_works() {
        let opts = GenOptions { length: 64, exclude_ambiguous: true, ..Default::default() };
        for _ in 0..20 {
            let p = generate_password(&opts).unwrap();
            assert!(!p.chars().any(|c| AMBIGUOUS.contains(c)), "{p}");
        }
    }

    #[test]
    fn strength_scores_move() {
        assert!(evaluate_strength("password").score <= 1);
        assert!(evaluate_strength("k9#mQ2$vLx7@pW4z!bN8").score >= 3);
    }
}
