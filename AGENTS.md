# 전역 코딩 가이드

이 파일은 모든 Codex 세션에 적용되는 공통 규칙입니다.

---

## 언어

항상 한국어로 응답한다. 기술 용어와 코드 식별자는 원래 형태를 유지한다.

---

## 개발 워크플로우

### 표준 기능 구현 순서

```
1. GitHub 코드 검색으로 기존 구현 탐색
2. 라이브러리 공식 문서 확인 (Context7 MCP 사용)
3. 구현 계획 수립 (복잡한 기능은 계획 먼저)
4. 테스트 먼저 작성 (RED → GREEN → REFACTOR)
5. 코드 리뷰 자가 체크
6. 커밋 (conventional commits 형식)
```

### 자동으로 실행해야 할 품질 검사

JS/TS 파일 수정 후:
```bash
npx prettier --write <파일>
npx tsc --noEmit
```

---

## 코딩 규칙

### 불변성 (CRITICAL)

항상 새 객체 생성, 기존 객체 직접 수정 금지:
```
WRONG:  obj.field = value   (뮤테이션)
CORRECT: { ...obj, field: value }  (새 객체)
```

### 파일 구조

- 함수: **50줄 이하**
- 파일: **200–400줄 표준, 800줄 최대**
- 기능/도메인 단위로 구성

### 에러 처리

- 모든 레벨에서 에러 명시적 처리
- 에러 무시(silent swallow) 금지
- 서버: 상세 컨텍스트 로깅
- UI: 사용자 친화적 메시지

### 입력 검증

- 시스템 경계(사용자 입력, 외부 API)에서 반드시 검증
- 스키마 기반 검증 라이브러리 사용
- 빠른 실패(fail fast), 명확한 오류 메시지

### 주석

기본적으로 주석 작성 금지. WHY가 명확하지 않은 경우에만:
- 숨겨진 제약 조건
- 미묘한 불변식
- 특정 버그 우회

---

## TypeScript/JavaScript 규칙

### 타입

- 내보내는 함수는 명시적 타입 필수
- `any` 금지 → `unknown` + 타입 내로잉
- `interface` — 확장 가능한 객체
- `type` — 유니온, 인터섹션, 유틸리티

```typescript
// ❌ 금지
function handle(err: any) { return err.message }

// ✅ 올바른 방법
function handle(err: unknown): string {
  if (err instanceof Error) return err.message
  return '알 수 없는 오류'
}
```

### 비동기

```typescript
async function load(id: string): Promise<Data> {
  try {
    return await fetchData(id)
  } catch (error: unknown) {
    throw new Error(getErrorMessage(error))
  }
}
```

### console.log 금지

프로덕션 코드에 `console.log` 사용 금지 — 로거 라이브러리 사용.

---

## 보안 필수 체크 (커밋 전)

- [ ] 하드코딩된 시크릿 없음 (API 키, 비밀번호, 토큰)
- [ ] 모든 사용자 입력 검증
- [ ] SQL 인젝션 방지 (파라미터 쿼리)
- [ ] XSS 방지
- [ ] 인증/인가 검증
- [ ] 오류 메시지가 민감 정보 노출하지 않음

### 시크릿 관리

```typescript
// ❌ 절대 금지
const apiKey = "sk-proj-xxxxx"

// ✅ 환경변수
const apiKey = process.env.API_KEY
if (!apiKey) throw new Error('API_KEY 미설정')
```

---

## 테스트 요건

최소 80% 커버리지:

1. **단위 테스트** — 함수, 유틸리티
2. **통합 테스트** — API, DB
3. **E2E 테스트** — 핵심 흐름

TDD: 테스트 먼저(RED) → 구현(GREEN) → 리팩터(IMPROVE)

---

## 코드 리뷰 자가 체크리스트

- [ ] 가독성 좋고 이름이 명확한가
- [ ] 함수 50줄 이하인가
- [ ] 파일 800줄 이하인가
- [ ] 중첩 4단계 이하인가
- [ ] 에러 명시적으로 처리했는가
- [ ] 하드코딩된 값 없는가
- [ ] 뮤테이션 없는가
- [ ] 새 기능에 테스트 있는가

---

## Git 커밋 형식

```
<type>: <설명>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

---

## API 응답 형식

```typescript
interface ApiResponse<T> {
  success: boolean
  data?: T
  error?: string
  meta?: { total: number; page: number; limit: number }
}
```
