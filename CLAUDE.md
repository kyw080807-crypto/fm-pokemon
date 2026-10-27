# FM Pokémon (Essentials v21.1 / mkxp-z / Ruby 3.1)

9지역 FM(풋볼 매니저)형 매니지먼트 팬게임. 비상업 팬게임(Essentials 코드 CC-BY-NC-SA, 수익화 금지).
상세 기획은 `docs/design/` — 작업과 관련된 파일만 읽을 것. 엔진 메모는 `docs/essentials-notes.md`.

## 명령
- 단위 테스트: `ruby tools/test/run_all.rb` (시스템 Ruby 3.1 + minitest, 엔진 불필요)
- PBS 검증: `ruby tools/validate_pbs.rb`
- 실행: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_debug.ps1`
  (PluginScripts.rxdata 삭제 → `Game.exe debug` → 종료 후 `logs/fm_runtime.log` 출력)
- PBS까지 재컴파일: `tools/run_debug.ps1 -RecompilePbs`
- 스모크(게임 화면 없이 엔진 안 검증): `tools/run_debug.ps1 -Smoke` → `FM::Smoke.register`된 검사 실행 후
  자동 종료. 결과는 `logs/fm_runtime.log`, 폰트 렌더링은 `logs/font_test.png`(이미지로 열어 확인)

## 절대 금지 (훅으로도 강제됨)
- `*.rxdata` / `*.dat` 직접 Edit/Write 금지 (Ruby Marshal 바이너리). 맵·이벤트는 사람이 RMXP로 편집.
- `Data/Scripts/` (엔진 코어) 수정 금지. 변경은 `Plugins/`에서 클래스 재오픈 + `alias`로.
- `Game.exe` 또는 RPG Maker XP(`RPGXP.exe`) 실행 중 `Data/`·`PBS/`·`Plugins/` 변경 금지.
- 인게임 PBS 에디터/디버그 에디터로 데이터 수정 금지 (PBS를 재작성해 주석 소실).
- `scripts_extract.rb` / `scripts_combine.rb` 임의 실행 금지.
- v20 이하 튜토리얼 코드(`PokeBattle_*` 등 구 클래스명, 구 PBS 형식) 사용 금지.

## 구조 지도
- `Plugins/[000] FM Logger/` — `logs/fm_runtime.log` 기록, 예외 백트레이스
- `Plugins/[005] FM Font/` — 한글 폰트(Galmuri11/9)로 MessageConfig 교체
- `Plugins/[010] FM Core/` — 순수 Ruby: Calendar, Finance, State(세이브 단위). **RGSS/엔진 비의존**
- `Plugins/[020] FM Bridge/` — 엔진 연결. `SaveData :fm_state`(= `FM::State#to_h`, 순수 데이터 Hash)와
  이벤트용 API(`FM.advance_days`, `FM.balance`, `FM.date_text`). 엔진 접근은 여기서만
- `Plugins/[030] FM Data/` — 커스텀 GameData + 컴파일러 확장 (`PBS/fm_*.txt`)
- `Plugins/[040] FM UI/` — 메뉴 Scene
- `Plugins/[900] FM Debug/` — 스모크 테스트 러너(디버그 전용)
- `PBS/` — 지역별 분할(`trainers_r01.txt` …), FM 데이터는 `fm_*.txt`
- `tools/test/` — FM Core 단위 테스트 / `exports/` — 맵 YAML 덤프(읽기 전용 참고)

## 규칙
- 사용자 노출 문자열은 `_INTL("...")` 필수. 1차 언어는 한국어.
- 텍스트 파일은 UTF-8. .rb/.md는 BOM 없음, PBS .txt는 배포본처럼 BOM + CRLF, .ps1은 BOM 있음(PowerShell 5.1 한글).
- 엔진 API가 불확실하면 추측하지 말고 `Data/Scripts/`를 grep해 실제 시그니처를 확인.
- 이벤트 안 로직은 Script 커맨드 한 줄(`FM.open_facility_menu(:gym)`)만. 실제 로직은 플러그인에.
- 세이브에 들어가는 FM 상태는 `schema_version` 필드를 유지하고, 바꾸면 변환 코드를 함께 작성.

## 완료 기준
변경 후: 단위 테스트 통과 → `run_debug.ps1` 실행 → 콘솔/로그에 컴파일 메시지와
`Loaded plugin` 줄 확인 → `logs/fm_runtime.log`에 에러 없음 → `git diff --stat`으로
바이너리 변경이 섞이지 않았는지 보고. 실행 확인을 못 했으면 못 했다고 말할 것.
