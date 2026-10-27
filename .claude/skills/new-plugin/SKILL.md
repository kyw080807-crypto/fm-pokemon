---
name: new-plugin
description: 새 FM 플러그인 폴더를 meta.txt와 함께 만든다. 새 시스템/모듈을 플러그인으로 추가할 때 사용.
---

# 새 플러그인 만들기

1. 번호 대역을 고른다: 000 로깅 / 010 Core(순수 Ruby) / 020 Bridge / 030 Data / 040 UI / 900 Debug.
   기존 폴더와 겹치지 않는 번호(예: `[041] FM Travel UI`)를 쓴다.
2. `Plugins/[NNN] FM <이름>/meta.txt`:
   ```
   Name       = FM <이름>
   Version    = 0.1.0
   Essentials = 21.1
   Requires   = v21.1 Hotfixes
   Requires   = FM Logger
   Credits    = <작성자>
   ```
   의존하는 다른 FM 플러그인도 `Requires`에 추가한다. (Hotfixes의 정확한 Name은
   `Plugins/v21.1 Hotfixes/meta.txt`에서 확인)
3. 코드 파일은 `001_<주제>.rb`, `002_<주제>.rb`처럼 로드 순서대로 번호를 붙인다.
4. Core 대역이면 `tools/test/test_<주제>.rb`도 같이 만들고 `ruby tools/test/run_all.rb`로 확인.
   Core 파일은 엔진 심볼 없이 시스템 Ruby에서 `require` 가능해야 한다.
5. `compile-and-run` 스킬로 `Loaded plugin: FM <이름>` 줄이 뜨는지 확인.
