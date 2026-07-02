# 금고 (Geumgo)

셀프호스팅 비밀번호 관리자. Windows / Ubuntu(Linux) / Android 네이티브 설치형 앱 + zero-knowledge 동기화 서버.

## 구조

```
geumgo/
├── core/     # geumgo-core — Rust 보안 코어 (암호화, 볼트, 저장소, TOTP, 생성기)
├── app/      # Flutter 앱 (Linux/Windows/Android) — flutter_rust_bridge로 코어 연결
├── server/   # geumgo-server — 동기화 서버 (axum, 암호문 블롭만 저장)
└── .github/workflows/build.yml  # Windows/Linux/Android 빌드 CI
```

## 보안 설계

**키 계층**

```
마스터 비밀번호
  └─ Argon2id(64MiB, t=3) ──► master_key           (파생 즉시 사용 후 폐기)
       ├─ HKDF "geumgo:v1:wrap" ──► wrap_key        (볼트 키 래핑 전용)
       └─ HKDF "geumgo:v1:auth" ──► auth_token      (서버 인증 전용)
랜덤 256bit ──► vault_key                            (실제 엔트리 암호화 키)
```

- **AEAD**: XChaCha20-Poly1305, 엔트리별 개별 암호화 (AAD = 엔트리 ID → 블롭 바꿔치기 방지)
- **메모리**: 키·엔트리 평문은 `zeroize` — 잠그거나 드롭되면 0으로 덮임
- **디스크**: 볼트 파일(SQLite)에는 암호문 블롭만. 평문은 어떤 경로로도 디스크에 닿지 않음
- **서버(zero-knowledge)**: 서버가 갖는 것 = 사용자명, SHA-256(auth_token), 볼트 헤더(공개 KDF 파라미터), 암호문 블롭. 마스터 비밀번호·볼트 키는 절대 서버로 가지 않음. DB가 통째로 유출돼도 비밀번호 추측 1회당 Argon2id 64MiB 비용
- **비밀번호 변경**: vault_key 래핑만 교체 — 전체 재암호화 불필요, 서버 토큰 로테이트
- **자동 잠금**: 앱이 백그라운드로 가면 즉시 잠금. 클립보드 복사는 30초 후 자동 삭제
- 암호화는 전부 검증된 RustCrypto 크레이트 사용, 자체 구현 없음

**동기화**: 엔트리 단위 리비전 + last-write-wins(updated_at). 삭제는 톰스톤으로 전파.
새 기기 합류: `GET /api/prelogin` → salt/KDF 수신 → 로컬에서 auth_token 유도 → 헤더 다운로드 → 비밀번호로 vault_key 언랩.

## 기능

- 로그인 항목 (아이디/비밀번호/URL/메모/태그/즐겨찾기)
- TOTP 일회용 코드 (RFC 6238, base32/otpauth URI, 실시간 갱신)
- 비밀번호 생성기 (OsRng, modulo-bias 제거, 문자 클래스 보장)
- 강도 평가 (zxcvbn)
- 검색, Material 3 UI (라이트/다크)

## 빌드

```bash
# 코어 + 서버 테스트
cargo test -p geumgo-core -p geumgo-server

# 데스크톱 (Linux)
cd app && flutter build linux --release

# Android APK
cd app && flutter build apk --release

# Windows은 GitHub Actions에서 빌드 (.github/workflows/build.yml)

# 동기화 서버
cargo build --release -p geumgo-server   # 또는 server/Dockerfile
```

## 서버 API

| 메서드 | 경로 | 설명 |
|---|---|---|
| GET | `/api/health` | 헬스체크 |
| POST | `/api/register` | 계정 생성 (username, auth_token, header) |
| GET | `/api/prelogin?username=` | salt + KDF 파라미터 (새 기기 합류용) |
| GET | `/api/vault/header` | 볼트 헤더 (인증 필요) |
| POST | `/api/account/rotate` | 비밀번호 변경 시 토큰/헤더 교체 |
| POST | `/api/sync` | push + pull (since_revision 기준 증분) |

인증: `X-User` + `X-Auth`(hex 토큰) 헤더. TLS는 리버스 프록시에서 종료.
