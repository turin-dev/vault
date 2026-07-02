//! 볼트 수명주기: 생성/열기/잠금, 엔트리 CRUD.
//!
//! 키 구조:
//!   master_key = Argon2id(password, salt)          — 파생 즉시 서브키만 쓰고 폐기
//!   wrap_key   = HKDF(master_key, "geumgo:v1:wrap") — 볼트 키 래핑 전용
//!   vault_key  = 랜덤 256bit                        — 실제 엔트리 암호화 키
//! 비밀번호 변경 시 vault_key는 그대로 두고 래핑만 다시 하므로
//! 전체 재암호화가 필요 없다.

use base64::{engine::general_purpose::STANDARD as B64, Engine};

use crate::crypto::{self, KdfParams, SecretKey, INFO_WRAP, SALT_LEN};
use crate::error::{CoreError, Result};
use crate::model::{EncryptedEntry, Entry, VaultHeader};
use crate::storage::VaultDb;

const WRAP_AAD: &[u8] = b"geumgo:v1:vaultkey";

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("시스템 시계가 1970년 이전")
        .as_secs() as i64
}

fn entry_aad(id: &str) -> Vec<u8> {
    format!("geumgo:v1:entry:{id}").into_bytes()
}

/// 잠금 해제된 볼트. 드롭되면 vault_key가 zeroize된다.
pub struct Vault {
    db: VaultDb,
    vault_key: SecretKey,
    /// 동기화 서버 인증 토큰 (마스터 키의 HKDF 서브키, hex)
    pub auth_token: String,
}

impl Vault {
    /// 새 볼트 생성. path에 파일이 이미 있으면 실패.
    pub fn create(path: &str, master_password: &str) -> Result<Vault> {
        if std::path::Path::new(path).exists() {
            return Err(CoreError::InvalidArg(format!("이미 존재하는 파일: {path}")));
        }
        if master_password.is_empty() {
            return Err(CoreError::InvalidArg("마스터 비밀번호가 비어 있음".into()));
        }
        let kdf = KdfParams::default();
        let salt = crypto::random_bytes(SALT_LEN);
        let master = crypto::derive_master_key(master_password, &salt, &kdf)?;
        let wrap_key = crypto::derive_subkey(&master, INFO_WRAP);
        let vault_key = SecretKey::random();
        let wrapped = crypto::seal(&wrap_key, vault_key.as_bytes(), WRAP_AAD);

        let header = VaultHeader {
            version: 1,
            kdf,
            salt_b64: B64.encode(&salt),
            wrapped_key_b64: B64.encode(&wrapped),
            created_at: now(),
        };
        let db = VaultDb::create(path, &header)?;
        let auth_token = crypto::derive_auth_token(&master);
        Ok(Vault { db, vault_key, auth_token })
    }

    /// 새 기기 합류: 서버에서 받은 헤더(JSON)로 빈 볼트 파일을 만들고 연다.
    /// 같은 salt/wrapped key를 쓰므로 서버의 암호문 블롭을 그대로 복호화할 수 있다.
    /// 비밀번호가 틀리면 파일을 남기지 않는다.
    pub fn create_from_header(path: &str, header_json: &str, master_password: &str) -> Result<Vault> {
        if std::path::Path::new(path).exists() {
            return Err(CoreError::InvalidArg(format!("이미 존재하는 파일: {path}")));
        }
        let header: VaultHeader = serde_json::from_str(header_json)?;
        VaultDb::create(path, &header)?;
        match Self::open(path, master_password) {
            Ok(v) => Ok(v),
            Err(e) => {
                let _ = std::fs::remove_file(path);
                Err(e)
            }
        }
    }

    /// 서버 업로드용 헤더 JSON.
    pub fn header_json(&self) -> Result<String> {
        Ok(serde_json::to_string(&self.db.header()?)?)
    }

    /// 기존 볼트 열기. 비밀번호가 틀리면 InvalidPasswordOrCorrupt.
    pub fn open(path: &str, master_password: &str) -> Result<Vault> {
        let db = VaultDb::open(path)?;
        let header = db.header()?;
        let salt = B64
            .decode(&header.salt_b64)
            .map_err(|_| CoreError::Format("salt base64 오류".into()))?;
        let wrapped = B64
            .decode(&header.wrapped_key_b64)
            .map_err(|_| CoreError::Format("wrapped key base64 오류".into()))?;
        let master = crypto::derive_master_key(master_password, &salt, &header.kdf)?;
        let wrap_key = crypto::derive_subkey(&master, INFO_WRAP);
        let key_bytes = crypto::open(&wrap_key, &wrapped, WRAP_AAD)?;
        let vault_key = SecretKey::from_bytes(&key_bytes)?;
        let auth_token = crypto::derive_auth_token(&master);
        Ok(Vault { db, vault_key, auth_token })
    }

    /// 마스터 비밀번호 변경 — vault_key 래핑만 갱신, 엔트리 재암호화 없음.
    pub fn change_master_password(&mut self, new_password: &str) -> Result<()> {
        if new_password.is_empty() {
            return Err(CoreError::InvalidArg("새 비밀번호가 비어 있음".into()));
        }
        let kdf = KdfParams::default();
        let salt = crypto::random_bytes(SALT_LEN);
        let master = crypto::derive_master_key(new_password, &salt, &kdf)?;
        let wrap_key = crypto::derive_subkey(&master, INFO_WRAP);
        let wrapped = crypto::seal(&wrap_key, self.vault_key.as_bytes(), WRAP_AAD);

        let mut header = self.db.header()?;
        header.kdf = kdf;
        header.salt_b64 = B64.encode(&salt);
        header.wrapped_key_b64 = B64.encode(&wrapped);
        self.db.put_meta("header", &serde_json::to_string(&header)?)?;
        self.auth_token = crypto::derive_auth_token(&master);
        Ok(())
    }

    // ---- 엔트리 CRUD ----

    pub fn add_entry(&self, mut entry: Entry) -> Result<Entry> {
        if entry.id.is_empty() {
            entry.id = Entry::new_id();
        }
        let t = now();
        entry.created_at = t;
        entry.updated_at = t;
        self.write_entry(&entry, 0)?;
        Ok(entry)
    }

    /// 비밀번호 이력에 담을 최대 개수.
    const MAX_HISTORY: usize = 25;

    pub fn update_entry(&self, mut entry: Entry) -> Result<Entry> {
        let existing_enc = self
            .db
            .get_entry(&entry.id)?
            .ok_or_else(|| CoreError::EntryNotFound(entry.id.clone()))?;
        let prev = self.decrypt_entry(&existing_enc)?;

        // 비밀번호가 실제로 바뀌었으면 이전 값을 이력에 자동 보관
        if !prev.password.is_empty() && prev.password != entry.password {
            let mut history = entry.password_history.clone();
            history.insert(
                0,
                crate::model::PasswordHistoryItem {
                    password: prev.password.clone(),
                    changed_at: prev.updated_at,
                },
            );
            history.truncate(Self::MAX_HISTORY);
            entry.password_history = history;
        }

        entry.updated_at = now();
        // 로컬 수정은 서버 리비전을 유지 — 동기화 때 서버가 새 리비전 부여
        self.write_entry(&entry, existing_enc.revision)?;
        Ok(entry)
    }

    /// 엔트리 목록을 일괄 추가 (가져오기). 추가된 개수 반환.
    pub fn import_entries(&self, entries: Vec<Entry>) -> Result<u32> {
        let mut count = 0;
        for e in entries {
            self.add_entry(e)?;
            count += 1;
        }
        Ok(count)
    }

    /// 아카이브 토글.
    pub fn set_archived(&self, id: &str, archived: bool) -> Result<()> {
        let mut e = self.get_entry(id)?;
        e.archived = archived;
        self.update_entry(e)?;
        Ok(())
    }

    /// 톰스톤 삭제 (동기화 전파를 위해 행 자체는 남긴다).
    pub fn delete_entry(&self, id: &str) -> Result<()> {
        let mut e = self
            .db
            .get_entry(id)?
            .ok_or_else(|| CoreError::EntryNotFound(id.to_string()))?;
        e.deleted = true;
        e.updated_at = now();
        e.blob = crypto::seal(&self.vault_key, b"{}", &entry_aad(id));
        self.db.upsert_entry(&e)?;
        Ok(())
    }

    pub fn get_entry(&self, id: &str) -> Result<Entry> {
        let enc = self
            .db
            .get_entry(id)?
            .filter(|e| !e.deleted)
            .ok_or_else(|| CoreError::EntryNotFound(id.to_string()))?;
        self.decrypt_entry(&enc)
    }

    /// 활성(아카이브 아닌) 항목.
    pub fn list_entries(&self) -> Result<Vec<Entry>> {
        Ok(self.all_live_entries()?.into_iter().filter(|e| !e.archived).collect())
    }

    /// 아카이브된 항목만.
    pub fn list_archived(&self) -> Result<Vec<Entry>> {
        Ok(self.all_live_entries()?.into_iter().filter(|e| e.archived).collect())
    }

    fn all_live_entries(&self) -> Result<Vec<Entry>> {
        let mut out = Vec::new();
        for enc in self.db.live_entries()? {
            out.push(self.decrypt_entry(&enc)?);
        }
        out.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
        Ok(out)
    }

    /// 잠금 해제된 활성 엔트리에 대해 보안 점검을 수행.
    pub fn audit(&self) -> Result<crate::audit::AuditReport> {
        let entries = self.list_entries()?;
        Ok(crate::audit::audit(&entries, now()))
    }

    // ---- 동기화 지원 ----

    pub fn export_encrypted(&self) -> Result<Vec<EncryptedEntry>> {
        self.db.all_entries()
    }

    /// 서버에서 받은 암호문 엔트리 반영 (last-write-wins by updated_at).
    pub fn import_encrypted(&self, incoming: &[EncryptedEntry]) -> Result<u32> {
        let mut applied = 0;
        for inc in incoming {
            let keep = match self.db.get_entry(&inc.id)? {
                Some(local) => inc.updated_at > local.updated_at
                    || (inc.updated_at == local.updated_at && inc.revision > local.revision),
                None => true,
            };
            if keep {
                // 볼트 키로 열리는지 검증 후 저장 — 오염된 블롭 유입 방지
                if !inc.deleted {
                    crypto::open(&self.vault_key, &inc.blob, &entry_aad(&inc.id))?;
                }
                self.db.upsert_entry(inc)?;
                applied += 1;
            }
        }
        Ok(applied)
    }

    pub fn set_revision(&self, id: &str, revision: i64) -> Result<()> {
        if let Some(mut e) = self.db.get_entry(id)? {
            e.revision = revision;
            self.db.upsert_entry(&e)?;
        }
        Ok(())
    }

    pub fn get_meta(&self, key: &str) -> Result<Option<String>> {
        self.db.get_meta(key)
    }

    pub fn put_meta(&self, key: &str, value: &str) -> Result<()> {
        self.db.put_meta(key, value)
    }

    // ---- 내부 ----

    fn write_entry(&self, entry: &Entry, revision: i64) -> Result<()> {
        let plain = serde_json::to_vec(entry)?;
        let blob = crypto::seal(&self.vault_key, &plain, &entry_aad(&entry.id));
        self.db.upsert_entry(&EncryptedEntry {
            id: entry.id.clone(),
            revision,
            deleted: false,
            updated_at: entry.updated_at,
            blob,
        })?;
        Ok(())
    }

    fn decrypt_entry(&self, enc: &EncryptedEntry) -> Result<Entry> {
        let plain = crypto::open(&self.vault_key, &enc.blob, &entry_aad(&enc.id))?;
        Ok(serde_json::from_slice(&plain)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> String {
        let dir = std::env::temp_dir().join("geumgo-core-tests");
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join(format!("{name}-{}.gmg", uuid::Uuid::new_v4()));
        p.to_string_lossy().into_owned()
    }

    fn sample_entry(title: &str) -> Entry {
        Entry {
            id: String::new(),
            title: title.into(),
            username: "me@example.com".into(),
            password: "s3cret!".into(),
            url: "https://example.com".into(),
            notes: "메모".into(),
            totp: String::new(),
            tags: vec!["work".into()],
            favorite: false,
            created_at: 0,
            updated_at: 0,
            item_type: crate::model::ITEM_LOGIN.into(),
            custom_fields: vec![],
            password_history: vec![],
            archived: false,
        }
    }

    #[test]
    fn create_open_roundtrip() {
        let path = tmp("roundtrip");
        {
            let v = Vault::create(&path, "hunter2-correct-horse").unwrap();
            v.add_entry(sample_entry("GitHub")).unwrap();
        }
        let v = Vault::open(&path, "hunter2-correct-horse").unwrap();
        let list = v.list_entries().unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].title, "GitHub");
        assert_eq!(list[0].password, "s3cret!");
    }

    #[test]
    fn wrong_password_rejected() {
        let path = tmp("wrongpw");
        Vault::create(&path, "correct").unwrap();
        assert!(matches!(
            Vault::open(&path, "wrong"),
            Err(CoreError::InvalidPasswordOrCorrupt)
        ));
    }

    #[test]
    fn crud_and_tombstone() {
        let path = tmp("crud");
        let v = Vault::create(&path, "pw-for-test").unwrap();
        let e = v.add_entry(sample_entry("A")).unwrap();

        let mut e2 = v.get_entry(&e.id).unwrap();
        e2.password = "new-pass".into();
        v.update_entry(e2).unwrap();
        assert_eq!(v.get_entry(&e.id).unwrap().password, "new-pass");

        v.delete_entry(&e.id).unwrap();
        assert!(v.get_entry(&e.id).is_err());
        assert_eq!(v.list_entries().unwrap().len(), 0);
        // 톰스톤은 동기화용으로 남는다
        let all = v.export_encrypted().unwrap();
        assert_eq!(all.len(), 1);
        assert!(all[0].deleted);
    }

    #[test]
    fn change_password_keeps_entries() {
        let path = tmp("chpw");
        let mut v = Vault::create(&path, "old-password").unwrap();
        v.add_entry(sample_entry("Keep")).unwrap();
        let old_auth = v.auth_token.clone();
        v.change_master_password("new-password").unwrap();
        assert_ne!(old_auth, v.auth_token);
        drop(v);

        assert!(Vault::open(&path, "old-password").is_err());
        let v = Vault::open(&path, "new-password").unwrap();
        assert_eq!(v.list_entries().unwrap()[0].title, "Keep");
    }

    #[test]
    fn import_lww() {
        let path_a = tmp("sync-a");
        let path_b = tmp("sync-b");
        let va = Vault::create(&path_a, "shared-pw").unwrap();
        let e = va.add_entry(sample_entry("Synced")).unwrap();

        // B는 같은 비밀번호의 다른 볼트 — 실제로는 서버에서 같은 헤더를 받아
        // 같은 vault_key를 갖지만, 여기서는 A의 블롭을 그대로 가져갈 수 없다.
        // 같은 볼트 파일을 복사해 같은 키를 공유하는 시나리오로 검증.
        drop(va);
        std::fs::copy(&path_a, &path_b).unwrap();
        let va = Vault::open(&path_a, "shared-pw").unwrap();
        let vb = Vault::open(&path_b, "shared-pw").unwrap();

        let mut newer = va.get_entry(&e.id).unwrap();
        newer.password = "rotated".into();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        va.update_entry(newer).unwrap();

        let applied = vb.import_encrypted(&va.export_encrypted().unwrap()).unwrap();
        assert_eq!(applied, 1);
        assert_eq!(vb.get_entry(&e.id).unwrap().password, "rotated");
    }
}
