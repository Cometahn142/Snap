# 설치 방법

Snap은 Roblox를 위한 고성능 스키마 기반 네트워킹 라이브러리입니다. 이 가이드는 Snap을 프로젝트에 통합하는 방법을 다룹니다.

## 방법 1: Wally

종속성 관리를 위해 Wally를 사용하는 경우, `wally.toml` 파일을 업데이트하세요:

```toml
[dependencies]
Snap = "cometahn142/snap@^0.3.0"
```

작업 공간에서 설치 명령을 실행합니다:
```bash
wally install
```

Sourcemap 및 파일 동기화 도구(예: Rojo)가 패키지를 `ReplicatedStorage`에 올바르게 노출하도록 설정하세요.

## 방법 2: 수동 설치

패키지 관리자를 사용하지 않는 경우:
1. 리포지토리에서 `src` 디렉토리를 추출합니다.
2. `Snap`이라는 이름의 `ModuleScript`로 Roblox 환경에 포함합니다.
3. 클라이언트와 서버 모두 접근 가능한 공유 위치(예: `ReplicatedStorage`)에 배치합니다.

## 검증

설정을 확인하려면 모듈을 불러오고 기본 채널을 선언해 보세요:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Snap = require(ReplicatedStorage.Packages.Snap)

local TestChannel = Snap.channel("TestChannel", {
	Message = Snap.event(Snap.string)
})
```

스크립트가 오류 없이 실행되면 설치가 완료된 것입니다.
