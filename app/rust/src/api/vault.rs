//! Flutter에 노출되는 볼트 API. 전역 싱글턴 볼트 상태를 Mutex로 보호.
//! 모든 함수는 Dart 쪽에서 async로 호출된다 (Argon2 등 무거운 작업이
//! UI 스레드를 막지 않음).

use std::sync::Mutex;

use anyhow::{anyhow, Result};
use geumgo_core::{self as core, Vault};

pub(crate) static VAULT: Mutex<Option<Vault>> = Mutex::new(None);

fn core_err(e: core::CoreError) -> anyhow::Error {
    anyhow!(e.to_string())
}

fn with_vault<T>(f: impl FnOnce(&Vault) -> Result<T>) -> Result<T> {
    let guard = VAULT.lock().unwrap();
    match guard.as_ref() {
        Some(v) => f(v),
        None => Err(anyhow!("볼트가 잠겨 있습니다")),
    }
}

// ---- DTO ----

pub struct CustomFieldDto {
    pub label: String,
    pub value: String,
    pub hidden: bool,
}

pub struct PasswordHistoryDto {
    pub password: String,
    pub changed_at: i64,
}

pub struct EntryDto {
    pub id: String,
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub totp: String,
    pub tags: Vec<String>,
    pub favorite: bool,
    pub created_at: i64,
    pub updated_at: i64,
    /// "login" | "note" | "card"
    pub item_type: String,
    pub custom_fields: Vec<CustomFieldDto>,
    pub password_history: Vec<PasswordHistoryDto>,
    pub archived: bool,
}

// Entry는 ZeroizeOnDrop(Drop)이라 필드를 move할 수 없어 clone으로 복사한다.
pub(crate) fn to_dto(e: core::Entry) -> EntryDto {
    EntryDto {
        id: e.id.clone(),
        title: e.title.clone(),
        username: e.username.clone(),
        password: e.password.clone(),
        url: e.url.clone(),
        notes: e.notes.clone(),
        totp: e.totp.clone(),
        tags: e.tags.clone(),
        favorite: e.favorite,
        created_at: e.created_at,
        updated_at: e.updated_at,
        item_type: e.item_type.clone(),
        custom_fields: e
            .custom_fields
            .iter()
            .map(|f| CustomFieldDto {
                label: f.label.clone(),
                value: f.value.clone(),
                hidden: f.hidden,
            })
            .collect(),
        password_history: e
            .password_history
            .iter()
            .map(|h| PasswordHistoryDto {
                password: h.password.clone(),
                changed_at: h.changed_at,
            })
            .collect(),
        archived: e.archived,
    }
}

fn from_dto(d: EntryDto) -> core::Entry {
    core::Entry {
        id: d.id,
        title: d.title,
        username: d.username,
        password: d.password,
        url: d.url,
        notes: d.notes,
        totp: d.totp,
        tags: d.tags,
        favorite: d.favorite,
        created_at: d.created_at,
        updated_at: d.updated_at,
        item_type: if d.item_type.is_empty() {
            core::ITEM_LOGIN.to_string()
        } else {
            d.item_type
        },
        custom_fields: d
            .custom_fields
            .into_iter()
            .map(|f| core::CustomField {
                label: f.label,
                value: f.value,
                hidden: f.hidden,
            })
            .collect(),
        password_history: d
            .password_history
            .into_iter()
            .map(|h| core::PasswordHistoryItem {
                password: h.password,
                changed_at: h.changed_at,
            })
            .collect(),
        archived: d.archived,
    }
}

pub struct StrengthDto {
    pub score: u8,
    pub crack_time: String,
    pub warning: String,
    pub suggestions: Vec<String>,
}

pub struct TotpDto {
    pub code: String,
    pub seconds_remaining: u64,
    pub period: u64,
}

pub struct GenOptionsDto {
    pub length: u32,
    pub lower: bool,
    pub upper: bool,
    pub digits: bool,
    pub symbols: bool,
    pub exclude_ambiguous: bool,
}

// ---- 볼트 수명주기 ----

pub fn vault_exists(path: String) -> bool {
    std::path::Path::new(&path).exists()
}

pub fn create_vault(path: String, password: String) -> Result<()> {
    let v = Vault::create(&path, &password).map_err(core_err)?;
    *VAULT.lock().unwrap() = Some(v);
    Ok(())
}

pub fn unlock_vault(path: String, password: String) -> Result<()> {
    let v = Vault::open(&path, &password).map_err(core_err)?;
    *VAULT.lock().unwrap() = Some(v);
    Ok(())
}

/// 잠금 — Vault 드롭으로 vault_key가 메모리에서 zeroize된다.
pub fn lock_vault() {
    *VAULT.lock().unwrap() = None;
}

pub fn is_unlocked() -> bool {
    VAULT.lock().unwrap().is_some()
}

pub fn change_master_password(new_password: String) -> Result<()> {
    let mut guard = VAULT.lock().unwrap();
    match guard.as_mut() {
        Some(v) => v.change_master_password(&new_password).map_err(core_err),
        None => Err(anyhow!("볼트가 잠겨 있습니다")),
    }
}

// ---- 엔트리 CRUD ----

pub fn list_entries() -> Result<Vec<EntryDto>> {
    with_vault(|v| {
        Ok(v.list_entries()
            .map_err(core_err)?
            .into_iter()
            .map(to_dto)
            .collect())
    })
}

pub fn get_entry(id: String) -> Result<EntryDto> {
    with_vault(|v| Ok(to_dto(v.get_entry(&id).map_err(core_err)?)))
}

pub fn add_entry(entry: EntryDto) -> Result<EntryDto> {
    with_vault(|v| Ok(to_dto(v.add_entry(from_dto(entry)).map_err(core_err)?)))
}

pub fn update_entry(entry: EntryDto) -> Result<EntryDto> {
    with_vault(|v| Ok(to_dto(v.update_entry(from_dto(entry)).map_err(core_err)?)))
}

pub fn delete_entry(id: String) -> Result<()> {
    with_vault(|v| v.delete_entry(&id).map_err(core_err))
}

// ---- 아카이브 ----

pub fn list_archived() -> Result<Vec<EntryDto>> {
    with_vault(|v| {
        Ok(v.list_archived()
            .map_err(core_err)?
            .into_iter()
            .map(to_dto)
            .collect())
    })
}

pub fn set_archived(id: String, archived: bool) -> Result<()> {
    with_vault(|v| v.set_archived(&id, archived).map_err(core_err))
}

// ---- 가져오기 / 내보내기 ----

/// 범용 CSV 텍스트를 가져와 항목으로 추가. 추가된 개수 반환.
pub fn import_csv(text: String) -> Result<u32> {
    let entries = core::parse_generic_csv(&text).map_err(core_err)?;
    with_vault(|v| v.import_entries(entries).map_err(core_err))
}

/// 활성 항목을 CSV 평문으로 내보냄 (암호화되지 않음).
pub fn export_csv() -> Result<String> {
    with_vault(|v| {
        let entries = v.list_entries().map_err(core_err)?;
        Ok(core::to_csv(&entries))
    })
}

// ---- 도구 ----

pub fn generate_password(opts: GenOptionsDto) -> Result<String> {
    let o = core::GenOptions {
        length: opts.length,
        lower: opts.lower,
        upper: opts.upper,
        digits: opts.digits,
        symbols: opts.symbols,
        exclude_ambiguous: opts.exclude_ambiguous,
    };
    core::generate_password(&o).map_err(core_err)
}

pub struct PassphraseOptionsDto {
    pub word_count: u32,
    pub separator: String,
    pub capitalize: bool,
    pub add_number: bool,
}

pub fn generate_passphrase(opts: PassphraseOptionsDto) -> Result<String> {
    let o = core::PassphraseOptions {
        word_count: opts.word_count,
        separator: opts.separator,
        capitalize: opts.capitalize,
        add_number: opts.add_number,
    };
    core::generate_passphrase(&o).map_err(core_err)
}

pub fn password_strength(password: String) -> StrengthDto {
    let s = core::evaluate_strength(&password);
    StrengthDto {
        score: s.score,
        crack_time: s.crack_time_display,
        warning: s.warning,
        suggestions: s.suggestions,
    }
}

pub fn totp_now(input: String) -> Result<TotpDto> {
    let cfg = geumgo_core::totp::parse(&input).map_err(core_err)?;
    let (code, seconds_remaining) = geumgo_core::totp::current_code(&input).map_err(core_err)?;
    Ok(TotpDto { code, seconds_remaining, period: cfg.period })
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
