---
name: sim-test
description: FM Core(캘린더·재정·리그·시뮬)의 minitest 단위 테스트를 실행하고 실패를 분석한다. Core 로직을 바꾼 뒤 또는 TDD로 새 로직을 만들 때 사용.
---

# FM Core 단위 테스트

1. 전체: `ruby tools/test/run_all.rb`
   한 파일: `ruby -Itools/test tools/test/test_calendar.rb`
   한 테스트: `ruby -Itools/test tools/test/test_calendar.rb -n test_month_rollover`
2. 새 로직은 테스트부터: `tools/test/test_<주제>.rb`에 실패하는 테스트 → 구현 → 통과.
3. 실패 시:
   - `NameError`로 `$game_variables`, `GameData`, `Graphics` 등이 나오면 Core에 엔진 의존이
     새어 들어온 것. 코드를 `[020] FM Bridge`로 옮기거나 인자로 주입한다. 테스트에 스텁을
     추가해 덮지 않는다.
   - 시뮬 결과가 확률적이면 `Random.new(seed)`를 인자로 받게 해 결정적으로 테스트한다.
4. 보고: 통과/실패 수, 고친 내용. 테스트를 지우거나 기대값을 바꿔 통과시켰다면 그 이유를 명시.
