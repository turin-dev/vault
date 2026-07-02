//! 가져오기/내보내기 (portability). 다른 비밀번호 관리자에서 넘어오거나
//! 백업을 만들 때 사용. CSV는 사람이 읽을 수 있는 평문이므로 호출 측에서
//! 취급에 주의해야 한다 (내보낸 파일은 암호화되지 않음).

use crate::error::{CoreError, Result};
use crate::model::{Entry, ITEM_LOGIN};

/// 아주 단순한 CSV 파서. 따옴표로 감싼 필드와 이스케이프("")를 지원.
fn parse_csv(text: &str) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut field = String::new();
    let mut record = Vec::new();
    let mut in_quotes = false;
    let mut chars = text.chars().peekable();

    while let Some(c) = chars.next() {
        if in_quotes {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    field.push('"');
                    chars.next();
                } else {
                    in_quotes = false;
                }
            } else {
                field.push(c);
            }
        } else {
            match c {
                '"' => in_quotes = true,
                ',' => {
                    record.push(std::mem::take(&mut field));
                }
                '\r' => {}
                '\n' => {
                    record.push(std::mem::take(&mut field));
                    rows.push(std::mem::take(&mut record));
                }
                _ => field.push(c),
            }
        }
    }
    // 마지막 레코드 (개행 없이 끝난 경우)
    if !field.is_empty() || !record.is_empty() {
        record.push(field);
        rows.push(record);
    }
    rows
}

fn csv_escape(s: &str) -> String {
    if s.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

/// 헤더 이름을 소문자로 정규화해 열 인덱스를 찾는다.
fn find_col(header: &[String], names: &[&str]) -> Option<usize> {
    header.iter().position(|h| {
        let h = h.trim().to_lowercase();
        names.iter().any(|n| h == *n)
    })
}

/// 범용 CSV → 엔트리 목록. Bitwarden / 1Password / Chrome / KeePass 등의
/// 흔한 헤더 이름을 자동 인식한다. id/시각은 호출 측(add_entry)에서 채운다.
pub fn parse_generic_csv(text: &str) -> Result<Vec<Entry>> {
    let rows = parse_csv(text);
    let mut it = rows.into_iter();
    let header = it
        .next()
        .ok_or_else(|| CoreError::Format("빈 CSV입니다".into()))?;

    let c_title = find_col(&header, &["name", "title", "account", "item"]);
    let c_user = find_col(&header, &["username", "user", "login_username", "login", "email"]);
    let c_pass = find_col(&header, &["password", "login_password", "pass"]);
    let c_url = find_col(&header, &["url", "uri", "login_uri", "website"]);
    let c_notes = find_col(&header, &["notes", "note", "comment", "comments"]);
    let c_totp = find_col(&header, &["totp", "otpauth", "otp", "login_totp", "2fa"]);

    if c_title.is_none() && c_user.is_none() && c_pass.is_none() {
        return Err(CoreError::Format(
            "인식 가능한 열(name/username/password)이 없습니다".into(),
        ));
    }

    let get = |row: &[String], idx: Option<usize>| -> String {
        idx.and_then(|i| row.get(i)).cloned().unwrap_or_default().trim().to_string()
    };

    let mut out = Vec::new();
    for row in it {
        if row.iter().all(|f| f.trim().is_empty()) {
            continue;
        }
        let title = {
            let t = get(&row, c_title);
            if t.is_empty() { get(&row, c_url) } else { t }
        };
        let username = get(&row, c_user);
        let password = get(&row, c_pass);
        if title.is_empty() && username.is_empty() && password.is_empty() {
            continue;
        }
        out.push(Entry {
            id: String::new(),
            title: if title.is_empty() { "(제목 없음)".into() } else { title },
            username,
            password,
            url: get(&row, c_url),
            notes: get(&row, c_notes),
            totp: get(&row, c_totp),
            tags: vec![],
            favorite: false,
            created_at: 0,
            updated_at: 0,
            item_type: ITEM_LOGIN.into(),
            custom_fields: vec![],
            password_history: vec![],
            archived: false,
        });
    }
    Ok(out)
}

/// 엔트리 목록 → CSV (Bitwarden 호환에 가까운 헤더). 평문 백업.
pub fn to_csv(entries: &[Entry]) -> String {
    let mut out = String::from("name,username,password,url,notes,totp\n");
    for e in entries {
        let cols = [
            &e.title,
            &e.username,
            &e.password,
            &e.url,
            &e.notes,
            &e.totp,
        ];
        let line: Vec<String> = cols.iter().map(|c| csv_escape(c)).collect();
        out.push_str(&line.join(","));
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bitwarden_style() {
        let csv = "folder,favorite,type,name,notes,fields,login_uri,login_username,login_password,login_totp\n\
                   ,,login,GitHub,my note,,https://github.com,octocat,hunter2,JBSWY3DPEHPK3PXP\n";
        let entries = parse_generic_csv(csv).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].title, "GitHub");
        assert_eq!(entries[0].username, "octocat");
        assert_eq!(entries[0].password, "hunter2");
        assert_eq!(entries[0].url, "https://github.com");
        assert_eq!(entries[0].totp, "JBSWY3DPEHPK3PXP");
    }

    #[test]
    fn handles_quoted_fields_with_commas() {
        let csv = "name,username,password,notes\n\
                   \"Bank, Personal\",me,\"p,w\"\"x\",\"line1\nline2\"\n";
        let entries = parse_generic_csv(csv).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].title, "Bank, Personal");
        assert_eq!(entries[0].password, "p,w\"x");
        assert_eq!(entries[0].notes, "line1\nline2");
    }

    #[test]
    fn csv_roundtrip() {
        let csv = "name,username,password,url,notes,totp\n\
                   Site,\"a,b\",pw,https://x.com,note,\n";
        let entries = parse_generic_csv(csv).unwrap();
        let out = to_csv(&entries);
        let reparsed = parse_generic_csv(&out).unwrap();
        assert_eq!(reparsed[0].username, "a,b");
        assert_eq!(reparsed[0].title, "Site");
    }

    #[test]
    fn rejects_unrecognized() {
        let csv = "colA,colB\n1,2\n";
        assert!(parse_generic_csv(csv).is_err());
    }
}
