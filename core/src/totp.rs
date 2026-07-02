//! RFC 6238 TOTP. base32 시크릿 또는 otpauth:// URI 지원.

use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Sha256, Sha512};

use crate::error::{CoreError, Result};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TotpAlgo {
    Sha1,
    Sha256,
    Sha512,
}

#[derive(Debug, Clone)]
pub struct TotpConfig {
    pub secret: Vec<u8>,
    pub digits: u32,
    pub period: u64,
    pub algo: TotpAlgo,
}

/// base32 시크릿("JBSWY3DP...") 또는 otpauth://totp/... URI를 파싱.
pub fn parse(input: &str) -> Result<TotpConfig> {
    let input = input.trim();
    if input.starts_with("otpauth://") {
        parse_uri(input)
    } else {
        Ok(TotpConfig {
            secret: decode_base32(input)?,
            digits: 6,
            period: 30,
            algo: TotpAlgo::Sha1,
        })
    }
}

fn decode_base32(s: &str) -> Result<Vec<u8>> {
    let cleaned: String = s
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '=')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    if cleaned.is_empty() {
        return Err(CoreError::Totp("시크릿이 비어 있음".into()));
    }
    data_encoding::BASE32_NOPAD
        .decode(cleaned.as_bytes())
        .map_err(|e| CoreError::Totp(format!("base32 디코드 실패: {e}")))
}

fn parse_uri(uri: &str) -> Result<TotpConfig> {
    let query = uri
        .split_once('?')
        .map(|(_, q)| q)
        .ok_or_else(|| CoreError::Totp("otpauth URI에 쿼리가 없음".into()))?;
    let mut secret = None;
    let mut digits = 6u32;
    let mut period = 30u64;
    let mut algo = TotpAlgo::Sha1;
    for pair in query.split('&') {
        let Some((k, v)) = pair.split_once('=') else { continue };
        match k.to_ascii_lowercase().as_str() {
            "secret" => secret = Some(decode_base32(v)?),
            "digits" => {
                digits = v.parse().map_err(|_| CoreError::Totp("digits 파싱 실패".into()))?
            }
            "period" => {
                period = v.parse().map_err(|_| CoreError::Totp("period 파싱 실패".into()))?
            }
            "algorithm" => {
                algo = match v.to_ascii_uppercase().as_str() {
                    "SHA1" => TotpAlgo::Sha1,
                    "SHA256" => TotpAlgo::Sha256,
                    "SHA512" => TotpAlgo::Sha512,
                    other => return Err(CoreError::Totp(format!("지원 안 하는 알고리즘: {other}"))),
                }
            }
            _ => {}
        }
    }
    let secret = secret.ok_or_else(|| CoreError::Totp("URI에 secret 파라미터 없음".into()))?;
    if !(4..=10).contains(&digits) || period == 0 {
        return Err(CoreError::Totp("digits/period 범위 오류".into()));
    }
    Ok(TotpConfig { secret, digits, period, algo })
}

fn hmac_digest(cfg: &TotpConfig, counter: u64) -> Vec<u8> {
    let msg = counter.to_be_bytes();
    match cfg.algo {
        TotpAlgo::Sha1 => {
            let mut m = <Hmac<Sha1> as Mac>::new_from_slice(&cfg.secret).expect("HMAC 키 길이 제한 없음");
            m.update(&msg);
            m.finalize().into_bytes().to_vec()
        }
        TotpAlgo::Sha256 => {
            let mut m = <Hmac<Sha256> as Mac>::new_from_slice(&cfg.secret).expect("HMAC 키 길이 제한 없음");
            m.update(&msg);
            m.finalize().into_bytes().to_vec()
        }
        TotpAlgo::Sha512 => {
            let mut m = <Hmac<Sha512> as Mac>::new_from_slice(&cfg.secret).expect("HMAC 키 길이 제한 없음");
            m.update(&msg);
            m.finalize().into_bytes().to_vec()
        }
    }
}

/// 특정 시각의 코드 계산.
pub fn code_at(cfg: &TotpConfig, unix_time: u64) -> String {
    let counter = unix_time / cfg.period;
    let digest = hmac_digest(cfg, counter);
    let offset = (digest[digest.len() - 1] & 0x0f) as usize;
    let bin = ((digest[offset] as u32 & 0x7f) << 24)
        | ((digest[offset + 1] as u32) << 16)
        | ((digest[offset + 2] as u32) << 8)
        | (digest[offset + 3] as u32);
    let modulo = 10u32.pow(cfg.digits);
    format!("{:0width$}", bin % modulo, width = cfg.digits as usize)
}

/// 현재 코드와 남은 유효 시간(초).
pub fn current_code(input: &str) -> Result<(String, u64)> {
    let cfg = parse(input)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("시스템 시계가 1970년 이전")
        .as_secs();
    let remaining = cfg.period - (now % cfg.period);
    Ok((code_at(&cfg, now), remaining))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 6238 Appendix B 테스트 벡터 (SHA1, 8자리, 시크릿 "12345678901234567890")
    #[test]
    fn rfc6238_vectors() {
        let secret = b"12345678901234567890".to_vec();
        let cfg = TotpConfig { secret, digits: 8, period: 30, algo: TotpAlgo::Sha1 };
        assert_eq!(code_at(&cfg, 59), "94287082");
        assert_eq!(code_at(&cfg, 1111111109), "07081804");
        assert_eq!(code_at(&cfg, 20000000000), "65353130");
    }

    #[test]
    fn parses_otpauth_uri() {
        let cfg = parse(
            "otpauth://totp/Example:me@x.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8&period=30&algorithm=SHA1",
        )
        .unwrap();
        assert_eq!(cfg.digits, 8);
        assert_eq!(code_at(&cfg, 59), "94287082");
    }

    #[test]
    fn base32_with_spaces_and_lowercase() {
        let cfg = parse("gezd gnbv gy3t qojq gezd gnbv gy3t qojq").unwrap();
        assert_eq!(cfg.digits, 6);
        assert_eq!(code_at(&cfg, 59), "287082");
    }
}
