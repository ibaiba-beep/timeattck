# timeattck 개발 팁 모음

초보 개발자가 놓치기 쉬운 부분들을 매일 하나씩 기록합니다.

---

## 2026-05-13 | fatalError를 프로덕션에서 쓰면 안 돼요

**문제:** 현재 `DataModel.swift`의 `sharedModelContainer`가 실패하면 `fatalError()`로 앱이 강제 종료됩니다.

```swift
// 현재 코드 — 실 기기에서 앱이 그냥 죽어버림
} catch {
    fatalError("ModelContainer 생성 실패: \(error)")
}
```

**왜 위험한가:** 앱스토어에 출시된 앱에서 `fatalError`는 사용자에게 아무 설명 없이 앱이 꺼지는 최악의 경험을 줍니다. 앱스토어 리뷰에서 크래시로 감지되어 리젝될 수도 있어요.

**개선 방법:** 실패 시 사용자에게 안내 화면을 보여주거나, 인메모리 컨테이너로 fallback합니다.

```swift
} catch {
    // 로그 기록 후 인메모리로 fallback
    print("SwiftData 오류: \(error)")
    let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [fallbackConfig])
}
```

**실전 팁:** 개발 중엔 `fatalError`로 빠르게 문제를 잡고, 출시 전엔 반드시 graceful error handling으로 교체하세요.

---
