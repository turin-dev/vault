//! 암호화 기본 요소.
//!
//! - KDF: Argon2id (파라미터는 볼트 헤더에 저장 — 나중에 상향 가능)
//! - AEAD: XChaCha20-Poly1305, 랜덤 24바이트 논스, 출력 = nonce || ciphertext
//! - 키 분리: HKDF-SHA256으로 마스터 키에서 용도별 서브키 유도
//!   (암호화 키와 서버 인증 키가 절대 같은 키가 되지 않도록)

use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::{CoreError, Result};

pub const SALT_LEN: usize = 16;
pub const KEY_LEN: usize = 32;
pub const NONCE_LEN: usize = 24;

/// 마스터 키에서 볼트 키 암호화용 서브키를 유도할 때 쓰는 info 라벨.
pub const INFO_WRAP: &[u8] = b"geumgo:v1:wrap";
/// 동기화 서버 인증용 서브키 라벨. 서버로 전송되는 값은 이 서브키뿐이며
/// 여기서 마스터 키나 암호화 키를 역산할 수 없다.
pub const INFO_AUTH: &[u8] = b"geumgo:v1:auth";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct KdfParams {
    pub algo: String,
    pub m_cost_kib: u32,
    pub t_cost: u32,
    pub p_cost: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        // OWASP 권장 이상: 64 MiB, 3 iterations. 저사양 폰에서도 ~1초 이내.
        Self {
            algo: "argon2id".into(),
            m_cost_kib: 64 * 1024,
            t_cost: 3,
            p_cost: 1,
        }
    }
}

/// 드롭 시 메모리를 0으로 덮는 32바이트 비밀 키.
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct SecretKey(pub(crate) [u8; KEY_LEN]);

impl SecretKey {
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }

    pub fn random() -> Self {
        let mut k = [0u8; KEY_LEN];
        OsRng.fill_bytes(&mut k);
        SecretKey(k)
    }

    pub fn from_bytes(b: &[u8]) -> Result<Self> {
        let arr: [u8; KEY_LEN] = b
            .try_into()
            .map_err(|_| CoreError::Format("키 길이가 32바이트가 아님".into()))?;
        Ok(SecretKey(arr))
    }
}

pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut v = vec![0u8; len];
    OsRng.fill_bytes(&mut v);
    v
}

/// 마스터 비밀번호 → 마스터 키 (Argon2id).
pub fn derive_master_key(password: &str, salt: &[u8], params: &KdfParams) -> Result<SecretKey> {
    if params.algo != "argon2id" {
        return Err(CoreError::Kdf(format!("지원하지 않는 KDF: {}", params.algo)));
    }
    let argon_params = Params::new(params.m_cost_kib, params.t_cost, params.p_cost, Some(KEY_LEN))
        .map_err(|e| CoreError::Kdf(e.to_string()))?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon_params);
    let mut out = [0u8; KEY_LEN];
    argon
        .hash_password_into(password.as_bytes(), salt, &mut out)
        .map_err(|e| CoreError::Kdf(e.to_string()))?;
    Ok(SecretKey(out))
}

/// HKDF-SHA256으로 용도별 서브키 유도.
pub fn derive_subkey(master: &SecretKey, info: &[u8]) -> SecretKey {
    let hk = Hkdf::<Sha256>::new(None, &master.0);
    let mut out = [0u8; KEY_LEN];
    hk.expand(info, &mut out).expect("HKDF expand: 32바이트는 항상 유효");
    SecretKey(out)
}

/// AEAD 암호화. 반환값 = nonce(24B) || ciphertext+tag.
pub fn seal(key: &SecretKey, plaintext: &[u8], aad: &[u8]) -> Vec<u8> {
    let cipher = XChaCha20Poly1305::new(key.0.as_ref().into());
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce);
    let ct = cipher
        .encrypt(XNonce::from_slice(&nonce), Payload { msg: plaintext, aad })
        .expect("XChaCha20-Poly1305 암호화는 실패하지 않음");
    let mut out = Vec::with_capacity(NONCE_LEN + ct.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ct);
    out
}

/// AEAD 복호화. 키가 틀리거나 변조되면 InvalidPasswordOrCorrupt.
pub fn open(key: &SecretKey, blob: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    if blob.len() < NONCE_LEN + 16 {
        return Err(CoreError::Format("암호문이 너무 짧음".into()));
    }
    let (nonce, ct) = blob.split_at(NONCE_LEN);
    let cipher = XChaCha20Poly1305::new(key.0.as_ref().into());
    cipher
        .decrypt(XNonce::from_slice(nonce), Payload { msg: ct, aad })
        .map_err(|_| CoreError::InvalidPasswordOrCorrupt)
}

/// 동기화 서버 인증 토큰(hex). 마스터 키의 HKDF 서브키라 서버는
/// 이 값으로 볼트를 복호화할 수 없다. 서버 측에서 다시 Argon2 해시해 저장.
pub fn derive_auth_token(master: &SecretKey) -> String {
    let auth = derive_subkey(master, INFO_AUTH);
    hex::encode(auth.0)
}

/// 새 기기 합류용: 서버 prelogin이 준 salt/kdf로 볼트 파일 없이 인증 토큰 유도.
pub fn auth_token_for(password: &str, salt: &[u8], params: &KdfParams) -> Result<String> {
    let master = derive_master_key(password, salt, params)?;
    Ok(derive_auth_token(&master))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_open_roundtrip() {
        let key = SecretKey::random();
        let blob = seal(&key, b"hello", b"aad1");
        assert_eq!(open(&key, &blob, b"aad1").unwrap(), b"hello");
    }

    #[test]
    fn open_fails_on_wrong_key_or_aad() {
        let key = SecretKey::random();
        let other = SecretKey::random();
        let blob = seal(&key, b"hello", b"aad1");
        assert!(open(&other, &blob, b"aad1").is_err());
        assert!(open(&key, &blob, b"aad2").is_err());
    }

    #[test]
    fn kdf_is_deterministic_and_salt_sensitive() {
        let p = KdfParams { m_cost_kib: 8, t_cost: 1, p_cost: 1, ..Default::default() };
        let s1 = random_bytes(SALT_LEN);
        let k1 = derive_master_key("pw", &s1, &p).unwrap();
        let k2 = derive_master_key("pw", &s1, &p).unwrap();
        assert_eq!(k1.0, k2.0);
        let s2 = random_bytes(SALT_LEN);
        let k3 = derive_master_key("pw", &s2, &p).unwrap();
        assert_ne!(k1.0, k3.0);
    }

    #[test]
    fn subkeys_differ_by_info() {
        let m = SecretKey::random();
        let a = derive_subkey(&m, INFO_WRAP);
        let b = derive_subkey(&m, INFO_AUTH);
        assert_ne!(a.0, b.0);
    }
}
