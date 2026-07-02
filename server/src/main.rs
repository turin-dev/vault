//! Geumgo 동기화 서버 — zero-knowledge.
//!
//! 서버가 아는 것: 사용자명, 인증 토큰의 SHA-256, 볼트 헤더(공개 KDF 파라미터),
//! 암호문 블롭. 마스터 비밀번호도 볼트 키도 절대 서버에 오지 않는다.
//! 인증 토큰 자체가 클라이언트에서 Argon2id로 스트레칭된 서브키라
//! DB가 통째로 유출돼도 비밀번호 무차별 대입에는 건당 Argon2 비용이 든다.
//!
//! TLS는 앞단(Traefik)에서 종료한다.

use std::sync::{Arc, Mutex};

use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

type ApiError = (StatusCode, String);
type ApiResult<T> = Result<Json<T>, ApiError>;

fn bad(code: StatusCode, msg: &str) -> ApiError {
    (code, msg.to_string())
}

fn internal<E: std::fmt::Display>(e: E) -> ApiError {
    tracing::error!("internal error: {e}");
    (StatusCode::INTERNAL_SERVER_ERROR, "server error".into())
}

struct App {
    db: Mutex<Connection>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_target(false).init();

    let db_path = std::env::var("GEUMGO_DB").unwrap_or_else(|_| "geumgo-server.db".into());
    let conn = Connection::open(&db_path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS accounts (
            id        INTEGER PRIMARY KEY,
            username  TEXT NOT NULL UNIQUE,
            auth_hash BLOB NOT NULL,
            header    TEXT NOT NULL,
            revision  INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries (
            account_id INTEGER NOT NULL REFERENCES accounts(id),
            id         TEXT NOT NULL,
            revision   INTEGER NOT NULL,
            deleted    INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            blob       TEXT NOT NULL,
            PRIMARY KEY (account_id, id)
        );
        CREATE INDEX IF NOT EXISTS idx_entries_rev ON entries(account_id, revision);",
    )?;

    let state = Arc::new(App { db: Mutex::new(conn) });
    let app = Router::new()
        .route("/api/health", get(|| async { "ok" }))
        .route("/api/register", post(register))
        .route("/api/prelogin", get(prelogin))
        .route("/api/vault/header", get(get_header))
        .route("/api/account/rotate", post(rotate))
        .route("/api/sync", post(sync))
        .with_state(state);

    let addr = std::env::var("GEUMGO_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());
    tracing::info!("geumgo-server listening on {addr}, db={db_path}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

// ---- 인증 ----

fn hash_token(token_hex: &str) -> Result<[u8; 32], ApiError> {
    let raw = hex::decode(token_hex)
        .map_err(|_| bad(StatusCode::BAD_REQUEST, "auth token must be hex"))?;
    if raw.len() != 32 {
        return Err(bad(StatusCode::BAD_REQUEST, "auth token must be 32 bytes"));
    }
    Ok(Sha256::digest(&raw).into())
}

fn valid_username(u: &str) -> bool {
    (3..=64).contains(&u.len())
        && u.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "._-@".contains(c))
}

/// X-User / X-Auth 헤더 검증 → account id.
fn authenticate(app: &App, headers: &HeaderMap) -> Result<i64, ApiError> {
    let user = headers
        .get("x-user")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| bad(StatusCode::UNAUTHORIZED, "missing x-user"))?;
    let token = headers
        .get("x-auth")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| bad(StatusCode::UNAUTHORIZED, "missing x-auth"))?;
    let given = hash_token(token)?;

    let db = app.db.lock().unwrap();
    let row: Option<(i64, Vec<u8>)> = db
        .query_row(
            "SELECT id, auth_hash FROM accounts WHERE username = ?1",
            params![user],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .map_err(internal)?;
    // 존재하지 않는 계정도 상수 시간 비교를 거쳐 타이밍 차이를 줄인다
    let (id, stored) = row.unwrap_or((-1, vec![0u8; 32]));
    if stored.ct_eq(&given).into() && id >= 0 {
        Ok(id)
    } else {
        Err(bad(StatusCode::UNAUTHORIZED, "invalid credentials"))
    }
}

// ---- 요청/응답 ----

#[derive(Deserialize)]
struct RegisterReq {
    username: String,
    auth_token: String,
    header: serde_json::Value,
}

#[derive(Serialize)]
struct OkResp {
    ok: bool,
}

async fn register(
    State(app): State<Arc<App>>,
    Json(req): Json<RegisterReq>,
) -> ApiResult<OkResp> {
    if !valid_username(&req.username) {
        return Err(bad(
            StatusCode::BAD_REQUEST,
            "username: 3-64 chars, [a-z0-9._-@]",
        ));
    }
    let auth_hash = hash_token(&req.auth_token)?;
    let header = serde_json::to_string(&req.header).map_err(internal)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    let db = app.db.lock().unwrap();
    let n = db
        .execute(
            "INSERT OR IGNORE INTO accounts(username, auth_hash, header, created_at)
             VALUES(?1, ?2, ?3, ?4)",
            params![req.username, auth_hash.as_slice(), header, now],
        )
        .map_err(internal)?;
    if n == 0 {
        return Err(bad(StatusCode::CONFLICT, "username already exists"));
    }
    Ok(Json(OkResp { ok: true }))
}

#[derive(Deserialize)]
struct PreloginQuery {
    username: String,
}

async fn prelogin(
    State(app): State<Arc<App>>,
    Query(q): Query<PreloginQuery>,
) -> ApiResult<serde_json::Value> {
    let db = app.db.lock().unwrap();
    let header: Option<String> = db
        .query_row(
            "SELECT header FROM accounts WHERE username = ?1",
            params![q.username],
            |r| r.get(0),
        )
        .optional()
        .map_err(internal)?;
    let header =
        header.ok_or_else(|| bad(StatusCode::NOT_FOUND, "unknown user"))?;
    let full: serde_json::Value = serde_json::from_str(&header).map_err(internal)?;
    // salt와 KDF 파라미터만 공개 — wrapped key는 인증 후에만
    Ok(Json(serde_json::json!({
        "kdf": full.get("kdf"),
        "salt_b64": full.get("salt_b64"),
    })))
}

async fn get_header(
    State(app): State<Arc<App>>,
    headers: HeaderMap,
) -> ApiResult<serde_json::Value> {
    let id = authenticate(&app, &headers)?;
    let db = app.db.lock().unwrap();
    let header: String = db
        .query_row(
            "SELECT header FROM accounts WHERE id = ?1",
            params![id],
            |r| r.get(0),
        )
        .map_err(internal)?;
    Ok(Json(serde_json::from_str(&header).map_err(internal)?))
}

#[derive(Deserialize)]
struct RotateReq {
    new_auth_token: String,
    new_header: serde_json::Value,
}

/// 마스터 비밀번호 변경 시 인증 토큰 + 헤더 교체.
async fn rotate(
    State(app): State<Arc<App>>,
    headers: HeaderMap,
    Json(req): Json<RotateReq>,
) -> ApiResult<OkResp> {
    let id = authenticate(&app, &headers)?;
    let new_hash = hash_token(&req.new_auth_token)?;
    let header = serde_json::to_string(&req.new_header).map_err(internal)?;
    let db = app.db.lock().unwrap();
    db.execute(
        "UPDATE accounts SET auth_hash = ?1, header = ?2 WHERE id = ?3",
        params![new_hash.as_slice(), header, id],
    )
    .map_err(internal)?;
    Ok(Json(OkResp { ok: true }))
}

#[derive(Serialize, Deserialize)]
struct WireEntry {
    id: String,
    revision: i64,
    deleted: bool,
    updated_at: i64,
    /// base64(nonce || ciphertext) — 서버는 열 수 없다
    blob: String,
}

#[derive(Deserialize)]
struct SyncReq {
    since_revision: i64,
    entries: Vec<WireEntry>,
}

#[derive(Serialize)]
struct SyncResp {
    server_revision: i64,
    entries: Vec<WireEntry>,
}

async fn sync(
    State(app): State<Arc<App>>,
    headers: HeaderMap,
    Json(req): Json<SyncReq>,
) -> ApiResult<SyncResp> {
    let id = authenticate(&app, &headers)?;
    if req.entries.len() > 5000 {
        return Err(bad(StatusCode::PAYLOAD_TOO_LARGE, "too many entries"));
    }
    for e in &req.entries {
        if e.id.len() > 64 || e.blob.len() > 1_000_000 {
            return Err(bad(StatusCode::PAYLOAD_TOO_LARGE, "entry too large"));
        }
    }

    let mut db = app.db.lock().unwrap();
    let tx = db.transaction().map_err(internal)?;

    let mut revision: i64 = tx
        .query_row(
            "SELECT revision FROM accounts WHERE id = ?1",
            params![id],
            |r| r.get(0),
        )
        .map_err(internal)?;

    // 클라이언트 push 반영 — last-write-wins by updated_at
    for e in &req.entries {
        let stored_updated: Option<i64> = tx
            .query_row(
                "SELECT updated_at FROM entries WHERE account_id = ?1 AND id = ?2",
                params![id, e.id],
                |r| r.get(0),
            )
            .optional()
            .map_err(internal)?;
        let accept = match stored_updated {
            Some(t) => e.updated_at >= t,
            None => true,
        };
        if accept {
            revision += 1;
            tx.execute(
                "INSERT INTO entries(account_id, id, revision, deleted, updated_at, blob)
                 VALUES(?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(account_id, id) DO UPDATE SET
                   revision = excluded.revision,
                   deleted = excluded.deleted,
                   updated_at = excluded.updated_at,
                   blob = excluded.blob",
                params![id, e.id, revision, e.deleted as i64, e.updated_at, e.blob],
            )
            .map_err(internal)?;
        }
    }
    tx.execute(
        "UPDATE accounts SET revision = ?1 WHERE id = ?2",
        params![revision, id],
    )
    .map_err(internal)?;

    // 클라이언트가 모르는 변경분 pull
    let entries = {
        let mut stmt = tx
            .prepare(
                "SELECT id, revision, deleted, updated_at, blob FROM entries
                 WHERE account_id = ?1 AND revision > ?2",
            )
            .map_err(internal)?;
        let rows = stmt
            .query_map(params![id, req.since_revision], |r| {
                Ok(WireEntry {
                    id: r.get(0)?,
                    revision: r.get(1)?,
                    deleted: r.get::<_, i64>(2)? != 0,
                    updated_at: r.get(3)?,
                    blob: r.get(4)?,
                })
            })
            .map_err(internal)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(internal)?
    };
    tx.commit().map_err(internal)?;

    Ok(Json(SyncResp { server_revision: revision, entries }))
}
