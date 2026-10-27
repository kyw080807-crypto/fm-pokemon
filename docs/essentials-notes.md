# Essentials v21.1 엔진 메모

엔진 코드에서 직접 확인한 사실만 적는다. 형식: `사실 — 파일 경로 (확인일)`.

## 미확인 (처음 프로젝트를 열면 Claude에게 grep으로 확인시킬 것)
- [ ] v21.1 Hotfixes의 meta.txt `Name` 값 (FM 플러그인 `Requires`에 그대로 써야 함) — Hotfixes 미설치
- [ ] 커스텀 PBS/GameData를 컴파일 목록에 등록하는 방법 (compile_* 헬퍼 이름, 등록 API)
- [ ] Extract Text가 Plugins/ 와 추출된 Data/Scripts/ 를 스캔하는지
- [ ] `messages_core.dat`가 PBS 컴파일로 재생성되는지 (아니면 `.gitignore` 예외 유지)

## 확인됨 (v21.1 태그 ea7b5d56 + Hotfixes 1.0.9 기준)
- 예외 처리 진입점은 `pbPrintException(e)` — `Data/Scripts/001_Technical/001_Debugging/003_Errors.rb:31` (2026-10-27)
- errorlog.txt는 `RTP.getSaveFileName("errorlog.txt")` → 세이브 폴더 `%APPDATA%\<Game.ini Title>\`
  (현재 `%APPDATA%\Pokemon Essentials v21.1\`)에 생성. 플러그인 로드 오류도 같은 방식 —
  `003_Errors.rb:53-54`, `005_PluginManager.rb:382-383` (2026-10-27).
  주의: master 브랜치는 프로젝트 폴더에 썼다(버전 차이). `tools/run_debug.ps1`은 두 곳 모두 확인함.
- 실행 확인: `Game.exe debug`로 PBS 전체 컴파일(.dat 24개) + 플러그인 컴파일 성공, FM Logger 로드됨 (2026-10-27)
- 폰트: mkxp-z는 `Fonts/`의 폰트를 **타이포그래픽 패밀리(name ID 16)**, 없으면 ID 1 이름으로 등록.
  Galmuri11.ttf → `"Galmuri11"` (`"Galmuri11 Regular"`는 못 찾음). 같은 패밀리의 두 파일(Condensed)은 충돌.
  이름 확인: `ruby tools/font_names.rb <ttf>`. 못 찾으면 오류 없이 Liberation Sans로 대체되어 한글이 □ (2026-10-27)
- 폰트 세로 위치: `bitmap.text_offset_y`는 글자를 **위로** 올림. Power Green은 8, Galmuri11(24px)은 0이
  32px 줄 안에서 같은 위치 — `MessageConfig::FONT_Y_OFFSET` 등 (2026-10-27)
- `Bitmap#to_file(path)` 사용 가능(mkxp-z) → 화면 없이 렌더링 결과를 PNG로 확인 (2026-10-27)
- 플러그인 안에서 `exit`는 PluginManager가 SystemExit을 잡아 "Error in Plugin"으로 보고함 → `exit!(0)` 사용 (2026-10-27)
- 플러그인 meta.txt: `Optional`/`Exact`는 버전이 없으면 무시됨 — `005_PluginManager.rb:435-441` (2026-10-27)
- 시작 순서: `PluginManager.runPlugins` → `Compiler.main` → `Game.initialize` → `Game.set_up_system` → `pbCallTitle`
  — `Data/Scripts/999_Main/999_Main.rb:25-35`. **플러그인 로드 시점에는 GameData가 비어 있다**(Species 등 조회 불가).
  데이터가 필요한 코드는 `pbCallTitle` 등 그 뒤로 미룬다(FM Debug 스모크가 그렇게 함) (2026-10-27)
- Generation 9 Pack 3.3.8 (Caruban): `Requires = v21.1 Hotfixes,1.0.9`. 새 PBS는 `*_Gen_9_Pack.txt` 6개로 자동 추가,
  기본 PBS 5개(abilities/items/moves/pokemon/pokemon_forms) + pokemon_metrics는 팩의 바닐라 갱신본으로 덮어씀.
  `Graphics/Pokemon`은 팩의 1~9세대 리사이즈 스프라이트로 교체. 설치 후 전체 컴파일·부팅·스모크 통과 (2026-10-27)
- SaveData: `SaveData.register(:id) { ensure_class; save_value {}; load_value {|v|}; new_game_value {} }`.
  저장 해시가 키를 갖고 있지 않으면(옛 세이브) new_game_value로 채움 — `002_SaveData_Value.rb:195,220-229` (2026-10-27)
- 폰트 상수: `FONT_NAME`/`FONT_SIZE`, `SMALL_FONT_NAME`/`SMALL_FONT_SIZE`, `NARROW_FONT_NAME`/`NARROW_FONT_SIZE`
  (기본값 "Power Green" 27 / "Power Green Small" 21 / "Power Green Narrow" 27) — `Data/Scripts/007_Objects and windows/002_MessageConfig.rb:13-20` (2026-10-27)
- PBS 배포 파일은 UTF-8 **BOM 있음** + CRLF (`PBS/abilities.txt`로 확인) → `.gitattributes`의 `*.txt eol=crlf`와 일치 (2026-10-27)
- Windows에서 Git Bash가 없으면 Claude Code 훅에 `"shell": "powershell"`이 필요하다.
  없으면 훅이 실패하고 모든 Edit/Write가 차단된다. (2026-10-27)

## 사람이 할 초기 세팅
1. Essentials v21.1 패키지(eeveeexpo.com/essentials) 압축 해제
2. Maruno17/pokemon-essentials 레포를 그 위에 덮어쓰기 (스크립트 → Data/Scripts/*.rb)
3. v21.1 Hotfixes 플러그인 설치
4. RMXP에서 Playtest 한 번 (Ctrl 누른 채) 으로 전체 컴파일
5. 한글 폰트(예: Galmuri11, OFL) 를 Fonts/ 에 넣고 MessageConfig 폰트 이름 수정
6. 이 키트(CLAUDE.md, .claude/, Plugins/[0xx] FM *, tools/, docs/) 복사
7. Ruby 3.1 설치 (`gem install minitest`), Git + Git LFS 설치 후 `git init`, `git lfs install`
