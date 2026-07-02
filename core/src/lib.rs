//! Geumgo(금고) — 비밀번호 관리자 보안 코어.
//!
//! 설계 원칙:
//! - 평문 비밀은 잠금 해제된 프로세스 메모리에만 존재 (디스크/서버는 항상 암호문)
//! - 키는 zeroize — 드롭 시 메모리에서 지워짐
//! - 서버는 zero-knowledge: 암호문 블롭과 인증 서브키 해시만 보관
//! - 검증된 크레이트만 사용 (RustCrypto 계열), 자체 암호 구현 없음
//!   (TOTP의 HMAC 조합은 RFC 6238 표준 구성)

pub mod audit;
pub mod crypto;
pub mod error;
pub mod generator;
pub mod model;
pub mod storage;
pub mod totp;
pub mod vault;

pub use audit::{audit, AuditEntryRef, AuditReport, ReuseGroup};
pub use error::{CoreError, Result};
pub use generator::{evaluate_strength, generate_password, GenOptions, Strength};
pub use model::{EncryptedEntry, Entry, VaultHeader};
pub use vault::Vault;
