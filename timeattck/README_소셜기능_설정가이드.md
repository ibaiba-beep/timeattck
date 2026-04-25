# timeattck 소셜 기능 설정 가이드

## 파일 구성

| 파일 | 역할 |
|------|------|
| `SocialDataService.swift` | 프로토콜 + 데이터 모델 (Firebase/CloudKit 공통) |
| `FirebaseSocialService.swift` | Firebase 구현체 |
| `SocialViewModel.swift` | SwiftUI ViewModel |
| `SocialView.swift` | UI 뷰 (친구 통계 / 랭킹 / 공유 목표) |

---

## Step 1 — Firebase 프로젝트 설정

1. [console.firebase.google.com](https://console.firebase.google.com) → 새 프로젝트 생성
2. iOS 앱 추가 → Bundle ID 입력 (Xcode → General에서 확인)
3. `GoogleService-Info.plist` 다운로드 → Xcode 프로젝트 루트에 추가
4. Firebase Console → Authentication → Apple 로그인 활성화
5. Firebase Console → Firestore → 데이터베이스 생성

---

## Step 2 — Xcode에서 패키지 추가

File → Add Package Dependencies:
```
https://github.com/firebase/firebase-ios-sdk
```

추가할 패키지:
- FirebaseAuth
- FirebaseFirestore
- FirebaseFunctions (랭킹 집계용, 나중에 추가 가능)

---

## Step 3 — 파일을 Xcode에 추가

1. 다운로드한 4개 파일을 Xcode 프로젝트 폴더에 복사
2. Xcode → File → Add Files to "timeattck" → 4개 파일 선택

---

## Step 4 — 앱 진입점에 Firebase 초기화

```swift
// timeattckApp.swift
import FirebaseCore

@main
struct timeattckApp: App {
    init() {
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## Step 5 — ContentView에 소셜 탭 추가

```swift
// ContentView.swift 의 TabView에 추가
TabView {
    // 기존 탭들...
    TimerView()
        .tabItem { Label("타이머", systemImage: "timer") }
    ReportView()
        .tabItem { Label("리포트", systemImage: "chart.bar") }

    // 새로 추가
    SocialView()
        .tabItem { Label("소셜", systemImage: "person.2") }
}
```

---

## Firestore 보안 규칙

Firebase Console → Firestore → Rules 탭에 붙여넣기:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 유저 문서: 본인만 수정, 친구는 읽기 가능
    match /users/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == uid;
    }

    // 타임 레코드: 본인만 수정, isPublic이면 모두 읽기
    match /timeRecords/{recordId} {
      allow read: if resource.data.isPublic == true
                  || request.auth.uid == resource.data.uid;
      allow write: if request.auth.uid == resource.data.uid;
    }

    // 친구 요청: 발신자/수신자만 접근
    match /friendRequests/{requestId} {
      allow read, write: if request.auth.uid == resource.data.fromUID
                         || request.auth.uid == resource.data.toUID;
      allow create: if request.auth.uid == request.resource.data.fromUID;
    }

    // 공유 목표: 참여자만 접근
    match /sharedGoals/{goalId} {
      allow read, write: if request.auth.uid in resource.data.participants;
      allow create: if request.auth.uid in request.resource.data.participants;
    }

    // 랭킹: 인증된 사용자 읽기 가능
    match /weeklyRankings/{weekKey} {
      allow read: if request.auth != null;
    }
  }
}
```

---

## CloudKit으로 전환할 때

`SocialDataService.swift`는 그대로 유지하고, `FirebaseSocialService.swift`만 `CloudKitSocialService.swift`로 교체:

```swift
// SocialViewModel.swift 의 init 한 줄만 변경
init(service: SocialDataService = CloudKitSocialService()) { ... }
```

---

## 개발 순서 (추천)

1. **Firebase 설정 + Apple Sign-In** 테스트
2. **친구 추가 + 요청 수락** 플로우 확인
3. **친구 통계 보기** (SocialView 연결)
4. **공유 목표 설정**
5. **주간 랭킹** (Cloud Functions 집계 스크립트 추가)
