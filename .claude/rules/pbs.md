---
paths:
  - "PBS/**/*.txt"
---

# PBS 규칙 (v21.1 형식)

- v21에서 구 PBS 형식 지원이 제거됐다. 예시가 필요하면 인터넷 튜토리얼이 아니라 같은 폴더의
  기존 v21.1 PBS 파일 형식을 따른다.
- 데이터 타입 하나를 여러 파일로 나눌 수 있다: `<기본이름>_<접미사>.txt`
  (예: `trainers_r03.txt`, `map_metadata_r03.txt`). 지역 데이터는 지역별 파일에 넣는다.
- 인코딩은 배포본과 같은 UTF-8 **BOM 있음** + CRLF. 새 PBS 파일도 같은 형식으로 만든다.
- 섹션 헤더 `[ID]`의 ID는 대문자 스네이크(`[GYM_PALLET]`). 다른 파일에서 참조하는 ID를
  바꾸면 `grep`으로 모든 참조를 함께 고친다.
- 커스텀 FM 데이터는 `fm_*.txt` 전용. 스키마는 `Plugins/[030] FM Data/`의 `SCHEMA` 정의가 기준.
- 수정 후 `ruby tools/validate_pbs.rb` 실행. 실제 컴파일 확인은 `run_debug.ps1 -RecompilePbs`.
- 인게임 에디터로 PBS를 만지지 않는다(재작성으로 주석이 사라짐).
