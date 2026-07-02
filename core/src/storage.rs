//! 볼트 파일 = SQLite 데이터베이스.
//! meta 테이블에 헤더(JSON, 평문 메타데이터), entries 테이블에 암호문 블롭.
//! 평문 엔트리는 어떤 경로로도 디스크에 닿지 않는다.

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::{CoreError, Result};
use crate::model::{EncryptedEntry, VaultHeader};

pub struct VaultDb {
    conn: Connection,
}

impl VaultDb {
    pub fn create(path: &str, header: &VaultHeader) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS meta (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS entries (
                id         TEXT PRIMARY KEY,
                revision   INTEGER NOT NULL DEFAULT 0,
                deleted    INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL,
                blob       BLOB NOT NULL
            );",
        )?;
        let db = VaultDb { conn };
        db.put_meta("header", &serde_json::to_string(header)?)?;
        Ok(db)
    }

    pub fn open(path: &str) -> Result<Self> {
        if !std::path::Path::new(path).exists() {
            return Err(CoreError::Format(format!("볼트 파일 없음: {path}")));
        }
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        Ok(VaultDb { conn })
    }

    pub fn header(&self) -> Result<VaultHeader> {
        let json = self
            .get_meta("header")?
            .ok_or_else(|| CoreError::Format("헤더 없음 — 볼트 파일이 아님".into()))?;
        Ok(serde_json::from_str(&json)?)
    }

    pub fn put_meta(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO meta(key, value) VALUES(?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn get_meta(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM meta WHERE key = ?1", params![key], |r| {
                r.get(0)
            })
            .optional()?)
    }

    pub fn upsert_entry(&self, e: &EncryptedEntry) -> Result<()> {
        self.conn.execute(
            "INSERT INTO entries(id, revision, deleted, updated_at, blob)
             VALUES(?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(id) DO UPDATE SET
               revision = excluded.revision,
               deleted = excluded.deleted,
               updated_at = excluded.updated_at,
               blob = excluded.blob",
            params![e.id, e.revision, e.deleted as i64, e.updated_at, e.blob],
        )?;
        Ok(())
    }

    pub fn get_entry(&self, id: &str) -> Result<Option<EncryptedEntry>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, revision, deleted, updated_at, blob FROM entries WHERE id = ?1",
                params![id],
                Self::row_to_entry,
            )
            .optional()?)
    }

    /// 삭제 톰스톤 포함 전체 (동기화용).
    pub fn all_entries(&self) -> Result<Vec<EncryptedEntry>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, revision, deleted, updated_at, blob FROM entries")?;
        let rows = stmt.query_map([], Self::row_to_entry)?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    /// 살아있는 엔트리만.
    pub fn live_entries(&self) -> Result<Vec<EncryptedEntry>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, revision, deleted, updated_at, blob FROM entries WHERE deleted = 0",
        )?;
        let rows = stmt.query_map([], Self::row_to_entry)?;
        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    fn row_to_entry(r: &rusqlite::Row<'_>) -> rusqlite::Result<EncryptedEntry> {
        Ok(EncryptedEntry {
            id: r.get(0)?,
            revision: r.get(1)?,
            deleted: r.get::<_, i64>(2)? != 0,
            updated_at: r.get(3)?,
            blob: r.get(4)?,
        })
    }
}
