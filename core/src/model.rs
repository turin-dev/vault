//! 볼트 데이터 모델. Entry의 평문은 잠금 해제된 메모리에만 존재하며
//! 디스크/서버에는 항상 엔트리 단위로 AEAD 암호화된 블롭으로 저장된다.

use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::KdfParams;

/// 볼트 파일 헤더(평문 저장). 비밀 정보는 wrapped_key_b64 안에만 있고
/// 그것도 마스터 키 없이는 열 수 없다.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultHeader {
    pub version: u32,
    pub kdf: KdfParams,
    /// Argon2id 솔트 (base64)
    pub salt_b64: String,
    /// 볼트 키를 마스터 서브키로 감싼 블롭 (base64).
    /// 이 블롭이 열리면 비밀번호가 맞다는 뜻 — 별도 verifier 불필요.
    pub wrapped_key_b64: String,
    /// 생성 시각 (unix seconds)
    pub created_at: i64,
}

/// 로그인 항목 하나. 드롭 시 필드 메모리를 0으로 덮는다.
#[derive(Debug, Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop, PartialEq)]
pub struct Entry {
    pub id: String,
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    /// base32 시크릿 또는 otpauth:// URI. 비어 있으면 TOTP 없음.
    pub totp: String,
    pub tags: Vec<String>,
    pub favorite: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

impl Entry {
    pub fn new_id() -> String {
        uuid::Uuid::new_v4().to_string()
    }
}

/// 디스크/서버에 저장되는 형태. blob은 seal(vault_key, json(Entry), aad=id).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedEntry {
    pub id: String,
    /// 동기화용 단조 증가 리비전 (서버가 부여). 0 = 아직 미동기화.
    pub revision: i64,
    pub deleted: bool,
    pub updated_at: i64,
    #[serde(with = "serde_bytes_b64")]
    pub blob: Vec<u8>,
}

/// serde에서 Vec<u8>을 base64 문자열로 직렬화 (JSON 교환용).
mod serde_bytes_b64 {
    use base64::{engine::general_purpose::STANDARD as B64, Engine};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(v: &Vec<u8>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&B64.encode(v))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        B64.decode(s.as_bytes()).map_err(serde::de::Error::custom)
    }
}
