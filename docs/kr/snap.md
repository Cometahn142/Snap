# Snap API 레퍼런스

Snap의 공개 API는 견고한 타입 정의, 최적화된 직렬화, 그리고 오버헤드가 적은 처리량에 중점을 둡니다.

## 핵심 메서드

### `Snap.channel(name: string, definition: table)`
서버와 클라이언트 간의 고유한 통신 도메인을 등록합니다.
- `name`: 채널의 전역 식별자.
- `definition`: `Snap.event` 및 `Snap.request`로 생성된 패킷 항목을 포함하는 딕셔너리.

### `Snap.event(schema: DataType, reliability: string?)`
단방향 네트워크 이벤트 페이로드를 정의합니다.
- `schema`: 기대하는 `DataType` 스키마 유효성 검사 규칙.
- `reliability`: 네트워킹 표준. `"Reliable"` 또는 `"Unreliable"`. 기본값은 `"Reliable"`.

### `Snap.request(requestSchema: DataType, responseSchema: DataType)`
양방향 논블로킹(Yielding) RPC 인터페이스를 정의합니다.
- `requestSchema`: 요청 시 전송할 페이로드 스키마.
- `responseSchema`: 응답 시 반환할 페이로드 스키마.

## 내장 데이터 타입

Snap은 네트워크 인코딩을 위해 최적화된 원시 타입 및 조합기(Combinators)를 제공합니다:

### 원시 / 숫자 타입
- 정수: `uint8`, `uint16`, `uint32`, `int8`, `int16`, `int32`.
- 가변 길이 정수: `uvarint`, `varint`.
- 소수: `float32`, `float64`.
- 공통: `bool`, `char`, `string`, `null`, `auto`, `unknown`, `inst` (Roblox 인스턴스).

### Roblox 엔진 타입
- `vector3`, `vector3int16`, `color3`, `color3b`, `cframe`.

### 조합기 (Combinators)
- `struct(fields: table)` - 엄격한 키 기반 맵.
- `array(elementType: DataType)` - 정렬된 목록.
- `map(keyType, valueType)` - 타입이 지정된 딕셔너리.
- `optional(innerType)` - Nullable 포인터.
- `flags(names: table)` - 비트 패킹된 불리언 토글 세트.

## 메모리 관리: 테이블 풀링 (Table Pooling)

지속적인 전송 루프 중 가비지 컬렉션(GC) 오버헤드를 완화하기 위해 Snap은 선택적 테이블 풀링을 지원합니다.

`struct`와 `array`는 모두 확장된 `read` 시그니처를 노출합니다:
`read(buffer: buffer, offset: number, target: table?) -> (table, number)`

`target` 매개변수에 기존 배열이나 맵을 제공하면 기본 할당을 무시하고, 역직렬화된 상태를 재사용된 메모리에 직접 기록합니다.
