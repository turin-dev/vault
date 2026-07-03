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

- 항목 종류: 로그인 / 보안 메모 / 카드
- 로그인 항목 (아이디/비밀번호/URL/메모/태그/즐겨찾기)
- 커스텀 필드 (일반/숨김 타입) — 복구 코드·PIN·보안질문 등
- 비밀번호 변경 이력 (변경 시 이전 값 자동 보관, 최대 25개)
- TOTP 일회용 코드 (RFC 6238, base32/otpauth URI, 실시간 갱신)
- 비밀번호 생성기 (OsRng, modulo-bias 제거) + 패스프레이즈 생성기 (EFF 7776 단어)
- 강도 평가 (zxcvbn)
- **보안 대시보드**: 취약·재사용·오래된 비밀번호 점검 + HIBP 유출 검사(k-익명성)
- 보관함(아카이브) + 복원
- 가져오기/내보내기 (범용 CSV — Bitwarden/1Password/Chrome/KeePass 자동 인식)
- **Android 자동완성** (AutofillService): 다른 앱·브라우저 로그인 화면에서 아이디/비밀번호 자동 채움. **키보드 인라인 추천(Android 11+)** + 드롭다운 모두 지원
- 검색, Material 3 다크 UI (Pretendard)

### 자동완성 동작 방식
- Kotlin `GeumgoAutofillService`가 Rust 코어(`librust_lib_app.so`)의 JNI 함수를 호출한다.
  Flutter 엔진과 **같은 프로세스·같은 .so**라 잠금 해제된 in-memory 볼트를 공유 — 자동완성용 별도 평문 저장 없음(zero-knowledge 유지).
- 볼트가 잠겨 있으면 "잠금 해제" 항목을 띄우고, 해제 상태면 요청 도메인/앱에 맞는 자격증명을 제시.
- 이를 위해 잠금 정책을 조정: 백그라운드 진입 시 **UI만 잠그고 키는 메모리에 유지**(유휴 5분 또는 명시적 잠금 시 완전 파기). 업계 표준(Bitwarden/1Password) 모델.
- 활성화: 안드로이드 설정 → 일반 → 자동완성 서비스 → "금고" 선택.

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
