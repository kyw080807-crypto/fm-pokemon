---
paths:
  - "Plugins/**/*.rb"
  - "Plugins/**/meta.txt"
---

# 플러그인 Ruby 규칙

- 모든 FM 플러그인 폴더에 `meta.txt` 필수(없으면 폴더 전체가 무시됨). 의존성은 `Requires`로 명시하고,
  폴더명 접두사(`[010]`)는 보조 수단으로만 쓴다. 로드 순서는 폴더명이 아니라 의존성으로만 보장된다.
- `Optional`/`Exact`는 **버전이 없으면 조용히 무시된다**: `Optional = FM Bridge,0.1.0` 처럼 쓴다
  (`Data/Scripts/001_Technical/005_PluginManager.rb:435-441`). `Requires`는 버전 없이도 동작.
- 엔진 메서드 오버라이드는 재정의가 아니라 `alias` 감싸기:
  ```ruby
  class Battle
    alias __fm_pbEndOfRoundPhase pbEndOfRoundPhase
    def pbEndOfRoundPhase
      __fm_pbEndOfRoundPhase
      FM::Bridge.on_round_end(self)
    end
  end
  ```
  alias 이름은 `__fm_<원래이름>`. 같은 메서드를 두 번 alias하지 않도록 grep으로 확인.
- 감쌀 메서드는 반드시 `Data/Scripts/`와 `Plugins/v21.1 Hotfixes/`를 grep해 현재 시그니처 확인 후 작성.
- `[010] FM Core` 안에서는 `$game_*`, `Sprite`, `Bitmap`, `Graphics`, `Input`, `GameData`,
  `pbMessage` 등 엔진 심볼 사용 금지. 필요하면 인자로 받거나 `FM::Bridge`에 둔다.
  (단위 테스트가 시스템 Ruby에서 이 파일들을 그대로 `require`하기 때문)
- 네임스페이스는 `module FM`. 전역 메서드/전역 변수 추가 금지.
- 사용자 노출 문자열은 `_INTL`. 단, FM Core는 엔진 비의존이므로 문자열 대신 심볼/키를 반환하고
  UI/Bridge 쪽에서 `_INTL`로 변환한다.
- 디버그 출력은 `echoln`이 아니라 `FM::Log.info/warn/error` (콘솔 + `logs/fm_runtime.log`).
- 스타일은 레포의 `.rubocop.yml`을 따른다.
