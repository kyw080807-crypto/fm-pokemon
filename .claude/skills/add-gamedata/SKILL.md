---
name: add-gamedata
description: 커스텀 PBS 파일(fm_*.txt)과 그것을 읽는 GameData 클래스 + 컴파일러 확장을 추가한다. 도시·시설·리그·스폰서 같은 FM 수치 데이터를 PBS로 뺄 때 사용.
---

# 커스텀 GameData 추가

**먼저 엔진 코드를 읽는다. 아래 이름은 출발점일 뿐, 실제 시그니처가 기준이다.**

1. 참고 구현 읽기:
   - `Data/Scripts/` 에서 `class TrainerType` 이 있는 GameData 파일 (단순한 PBS→GameData 예)
   - `Data/Scripts/` 에서 `def compile_trainer_types` 와 `compile_pbs_file_message_start`,
     `pbEachFileSection`(또는 v21.1의 해당 헬퍼), `pbGetCsvRecord` 를 grep
   - v21에서 PBS/.dat 목록이 하드코딩에서 등록 방식으로 바뀌었다. 새 데이터 타입을 컴파일 목록에
     등록하는 방법(예: `Compiler.register` 류 혹은 `GameData` 쪽 상수)을 grep으로 찾는다.
   - 찾은 내용은 `docs/essentials-notes.md`에 경로와 함께 기록.
2. `Plugins/[030] FM Data/00N_<타입>.rb`에 `module GameData; class Fm<타입>` 정의
   (`DATA = {}`, `DATA_FILENAME = "fm_<타입>.dat"`, `PBS_BASE_FILENAME = "fm_<타입>"`, `SCHEMA`),
   1번에서 확인한 패턴대로 작성.
3. 컴파일 메서드와 등록 코드를 같은 플러그인에 추가.
4. `PBS/fm_<타입>.txt`에 샘플 2~3개 섹션. 지역별이면 `fm_<타입>_r01.txt`.
5. `tools/validate_pbs.rb`의 `SCHEMAS`에 같은 키/타입/참조 규칙 추가.
6. `ruby tools/validate_pbs.rb` → `compile-and-run` 스킬(`-RecompilePbs`) →
   `Data/fm_<타입>.dat`가 생성됐는지, 로그에 에러가 없는지 확인.
