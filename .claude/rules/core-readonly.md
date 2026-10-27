---
paths:
  - "Data/Scripts/**"
  - "Plugins/v21.1 Hotfixes/**"
---

# 엔진 코어: 읽기 전용

이 경로는 Essentials v21.1 코어와 공식 Hotfixes다. **읽기만** 한다.
- 동작을 바꿔야 하면 `Plugins/[0xx] FM */`에서 클래스를 재오픈하고 `alias`로 감싼다.
- 여기서 읽은 메서드 시그니처·상수명은 `docs/essentials-notes.md`에 파일 경로와 함께 적어 둔다
  (다음에 다시 grep하지 않도록).
- Hotfixes가 같은 메서드를 이미 덮어쓰고 있을 수 있으니, 코어와 Hotfixes 양쪽을 모두 확인한다.
