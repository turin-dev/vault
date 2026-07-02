use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("잘못된 마스터 비밀번호이거나 손상된 볼트입니다")]
    InvalidPasswordOrCorrupt,

    #[error("KDF 파라미터 오류: {0}")]
    Kdf(String),

    #[error("볼트 파일 형식 오류: {0}")]
    Format(String),

    #[error("저장소 오류: {0}")]
    Storage(#[from] rusqlite::Error),

    #[error("직렬화 오류: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("TOTP 오류: {0}")]
    Totp(String),

    #[error("엔트리를 찾을 수 없음: {0}")]
    EntryNotFound(String),

    #[error("잘못된 인자: {0}")]
    InvalidArg(String),
}

pub type Result<T> = std::result::Result<T, CoreError>;
