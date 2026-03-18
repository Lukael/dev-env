# Spec Kit 사용 방법

이 프로젝트는 **GitHub Spec Kit** 기반의 **Spec-Driven Development** 워크플로우를 사용합니다.  
Spec Kit은 기능을 바로 구현하는 대신, 먼저 **원칙 → 요구사항 → 구현 계획 → 작업 분해 → 구현** 순서로 정리하여 개발을 진행하도록 돕습니다.  

---

## 1. Spec Kit이란?

Spec Kit은 아이디어를 바로 코드로 옮기기보다, 아래 순서로 구조화해서 개발하는 방식입니다.

1. 프로젝트 원칙 정의
2. 만들고 싶은 기능의 요구사항 정의
3. 기술 스택과 아키텍처 계획 작성
4. 작업 단위로 분해
5. 구현 진행

이 흐름을 통해 기능 요구사항과 구현 의도를 더 명확하게 유지할 수 있습니다.

---

## 2. 사전 준비

Spec Kit 공식 README에서는 `Specify CLI` 설치 후 프로젝트를 초기화하는 방식을 안내합니다.  
대표적으로 아래 두 가지 방식이 있습니다.  [oai_citation:3‡GitHub](https://github.com/github/spec-kit)

### 방법 A. 전역처럼 설치해서 사용

```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

설치 후:

# 새 프로젝트 생성
specify init <PROJECT_NAME>

# 현재 프로젝트에 초기화
specify init . --ai claude

# 또는 현재 폴더에 바로 초기화
specify init --here --ai claude

# 설치 상태 확인
specify check
⸻
```

## 3. 기본 사용 과정

Spec Kit의 기본 개발 흐름은 아래와 같습니다.  ￼

### Step 1. 프로젝트 원칙 정의

AI assistant에서 다음 명령으로 프로젝트 운영 원칙을 정의합니다.
```
/speckit.constitution
Create principles focused on code quality, testing standards, user experience consistency, and performance requirements
```
예를 들면 다음과 같은 항목을 원칙으로 둘 수 있습니다.
	•	코드 품질 기준
	•	테스트 작성 기준
	•	UI/UX 일관성
	•	성능 요구사항
	•	문서화 규칙

이 원칙은 이후 spec, plan, tasks 작성의 기준이 됩니다.  ￼

⸻

### Step 2. 요구사항(spec) 작성

무엇을 만들지와 왜 필요한지를 정의합니다.
이 단계에서는 기술 구현 방법보다 기능 요구사항과 사용자 시나리오에 집중합니다.  ￼
```
/speckit.specify
Build an application that can help me organize my photos in separate photo albums. Albums are grouped by date and can be re-organized by dragging and dropping on the main page. Albums are never in other nested albums. Within each album, photos are previewed in a tile-like interface.
```
작성 팁:
	•	무엇을 만들지 명확하게 적기
	•	누가 어떻게 사용할지 적기
	•	왜 필요한지 적기
	•	이 단계에서는 기술 스택을 너무 빨리 고정하지 않기

⸻

### Step 3. 기술 계획(plan) 작성

이제 구현에 필요한 기술 스택, 구조, 저장 방식 등을 정의합니다.  ￼
```
/speckit.plan
The application uses Vite with minimal number of libraries. Use vanilla HTML, CSS, and JavaScript as much as possible. Images are not uploaded anywhere and metadata is stored in a local SQLite database.
```
이 단계에서 주로 정하는 내용:
	•	프론트엔드 / 백엔드 기술
	•	데이터 저장 방식
	•	아키텍처 방향
	•	외부 라이브러리 사용 범위
	•	배포/운영 고려사항

⸻

### Step  4. 작업 단위(tasks) 생성

계획을 바탕으로 실제 구현 가능한 작업 목록으로 분해합니다.  ￼
```
/speckit.tasks
```
예시 작업:
	•	프로젝트 초기 세팅
	•	데이터 모델 작성
	•	API 구현
	•	UI 컴포넌트 구현
	•	테스트 코드 작성
	•	문서 정리

⸻

### Step 5. 구현 실행

분해된 작업을 기준으로 구현을 진행합니다.  ￼
```
/speckit.implement
```
이 단계에서는 앞에서 정의한:
	•	constitution
	•	specify
	•	plan
	•	tasks

를 기준으로 실제 코드를 작성하고 검증합니다.

⸻

## 4. 추천 사용 순서

실무에서는 아래 순서로 진행하는 것을 추천합니다.

1. specify init
2. /speckit.constitution
3. /speckit.specify
4. /speckit.plan
5. /speckit.tasks
6. /speckit.implement

⸻

## 5. 작성 팁

specify 단계
	•	“어떻게”보다 “무엇을”에 집중
	•	사용자 동작과 기대 결과를 명확히 작성
	•	기능 범위를 지나치게 넓히지 않기

plan 단계
	•	기술 스택과 구조를 분명하게 작성
	•	데이터 흐름, 저장 방식, 배포 방식까지 포함
	•	유지보수성과 확장성을 함께 고려

tasks 단계
	•	작업을 너무 크게 잡지 않기
	•	검증 가능한 단위로 나누기
	•	테스트/문서 작업도 포함하기

⸻

## 6. 참고문헌
•	https://engineering.cocone.io/ko/2025/11/13/spec-kit-sdd-github-review/
•	https://tech.kakaopay.com/post/ifkakao-agentic-coding/