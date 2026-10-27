---
name: compile-and-run
description: 플러그인/PBS 변경 후 강제 재컴파일하고 Game.exe를 디버그 모드로 실행해 로그를 확인한다. 게임에서 실제로 동작하는지 확인해야 할 때 사용.
---

# 컴파일 + 디버그 실행

Claude는 게임 창에서 Ctrl/Shift를 누를 수 없으므로, 출력 파일을 지워 재컴파일을 강제한다.

1. 먼저 단위 테스트가 통과하는지 확인: `ruby tools/test/run_all.rb`
2. RPG Maker XP가 열려 있으면 중단하고 사용자에게 닫아 달라고 요청한다(훅도 막는다).
3. 실행:
   - 플러그인만 바꿨으면 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_debug.ps1`
   - PBS도 바꿨으면 같은 명령에 `-RecompilePbs`
   스크립트는 게임 창이 닫힐 때까지 기다린다. 사용자에게 "게임 창에서 확인 후 닫아 달라"고 말한다.
   스모크 시나리오가 있으면 `-Smoke`로 자동 종료시킨다.
4. 스크립트 출력에서 확인할 것 (mkxp-z 콘솔 창은 Claude가 읽을 수 없다):
   - `=== session start` 줄이 있는가. 없으면 FM Logger가 로드되지 않은 것 = 플러그인 컴파일 실패
   - `logs/fm_runtime.log`의 ERROR / 백트레이스
   - 콘솔의 "Checking plugins" 뒤 컴파일 메시지와 `Loaded plugin` 줄은 사용자에게 확인을 부탁한다
   - errorlog.txt (위치는 `docs/essentials-notes.md`에 기록된 경로)
5. 에러가 있으면 백트레이스의 파일:줄을 열어 원인을 찾고 고친 뒤 1번부터 반복.
6. 보고: 무엇을 확인했고 무엇을 확인하지 못했는지(예: 화면 표시는 사용자가 봐야 함) 명확히.
