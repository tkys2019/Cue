# Cue

Queue it now. Cue it later.

Cue is a lightweight buffer for thoughts you don't want to keep in your head.

It is not a task manager.
It stores short cues that help you resume interrupted thoughts quickly.

```
⌘⌘ popup
Enter
⌘⌘ close
```

---

以下は日本語の作業メモです。記載内容はコードと Xcode プロジェクト設定から確認したものです。実機での動作確認結果ではありません。「未確認」と書いた項目は、コードからは判断できなかったものです。

## 概要

Cue は、思いついた短いメモ（Cue）をすぐ書き留めて、あとで再開するための小さなアプリです。タスク管理アプリではありません。

| プラットフォーム | ターゲット | 役割 |
| --- | --- | --- |
| macOS | `Cue` | メニューバー常駐アプリ。⌘ を2回押すとパネルが開閉する |
| iOS (iPhone) | `CueiOS` | 入力・一覧・編集・共有・リマインダー送信 |
| iOS ウィジェット | `CueWidget` | ロック画面ウィジェット（最新3件） |
| watchOS | `CueWatch` | 入力・最新 Cue の閲覧。iPhone と同期する |
| watchOS ウィジェット | `CueWatchWidget` | コンプリケーション |

**Mac と iPhone の間でデータは同期しません。** macOS 版は `UserDefaults.standard` に保存し、ネットワーク接続も無効です（`ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`）。同期するのは iPhone と Apple Watch の間だけです。

## 実装済みの機能

### macOS（`Cue/`）

- Dock には表示されず、メニューバーに電球アイコンが常駐します（`NSApp.setActivationPolicy(.accessory)`）。
- **⌘ を単独で2回押す**（間隔 0.35 秒以内）か、アイコンを左クリックすると、パネル（360×300）を画面中央に開閉します。⌘ と他のキーを組み合わせた操作では反応しません。
- 入力欄で Enter を押すと追加します。前後の空白は除去され、空文字は無視されます。
- 一覧は新しい順に並びます。テキストをクリックするとクリップボードにコピーされ、「Copied」と表示されます。`×` で削除します。
- Cue を右クリックして「Send to Reminders」を選ぶと、デフォルトのリマインダーリストに追加します。成功した Cue は削除されます。
- 「Select」で選択モードになります。Select All、Copy（改行区切り）が使えます。選択中の行を右クリックすると、選択した Cue をまとめてリマインダーへ送れます（1回のコミットで保存し、失敗時は何も保存せず Cue も残します）。
- メニューバーアイコンを右クリックするとメニューが開きます。
  - Appearance: Show timestamps / Background（System・Light・Dark）/ Transparency（60〜100%）
  - Quick Launch: Launch at Login（初回起動時に自動で登録されます。OFF にした後は再登録しません）、ショートカット表示 ⌘⌘
  - About: Version / GitHub
  - Quit Cue

### iOS（`CueiOS/`、iPhone のみ）

- Return で追加します。新しい順に一覧表示します。
- タップするとコピーし、「（先頭14文字）Copied」と表示します。
- 長押しすると、その場で編集できます（Return で保存。ID と作成日時は保持）。
- `✓` を押すと Cue を消します（「Clear」表示）。
- 右スワイプ（「リマインダー」）でリマインダーへ、左スワイプ（「共有」）で共有シートへ送れます。いずれも成功・完了した場合だけ Cue を削除します。
- 選択モード（Select / Select All / Copy）では、選択中の行をスワイプすると選択分をまとめて送れます。
- 歯車アイコンから設定画面を開けます。項目は Show timestamps / Background / Lock portrait orientation（既定 ON）/ Version / GitHub です。
- データは App Group の `UserDefaults` に保存します。旧バージョンの `UserDefaults.standard` にデータがあり、App Group 側が空の場合に限り、一度だけコピーします（元データは残します）。

### iOS ロック画面ウィジェット（`CueWidget/`）

- `accessoryRectangular` に最新3件を表示します。iPhone アプリでデータが変わると更新します（定期更新はしません）。

### watchOS（`CueWatch/`、`CueWatchWidget/`）

- 「＋ Cue」から、システム入力（音声入力・手書き・キーボード）で Cue を追加します。まず Watch 内（App Group コンテナの `WatchCues.json`）に保存し、そのあと iPhone へ送ります。成功時は「Cue'd」、失敗時は「Not saved」と触覚フィードバックで知らせます。
- 最新 20 件を表示し、タップで全文を見られます。**Watch 上では編集・削除できません。**
- iPhone 側のデータを正とします。
  - Watch → iPhone: `transferUserInfo`。ID を保持し、重複は無視します。iPhone は受信済み ID を最大100件まで記録します。
  - iPhone → Watch: `updateApplicationContext` で最新20件のスナップショットを送ります。
  - 未送信の Cue は、iPhone がスナップショットで受信を確認するまで Watch に表示し続けます。
- コンプリケーションの種類は次のとおりです。
  - Rectangular: 「Cue」と最新2件
  - Inline: 「💡」と最新1件
  - Circular / Corner: ＋ボタン

  いずれもタップすると `cue://capture` を開き、入力画面が起動します。

### 保存データの形式

- キー `"cues"` に `[CueItem]` を JSON で保存します。`CueItem` は `id`（UUID）、`text`、`createdAt`（任意。古いデータにはありません）を持ちます（`Shared/CueItem.swift`）。
- 設定値は `UserDefaults.standard` に保存します。キーは `showTimestamps`、`background`、`transparency`（macOS）、`launchAtLogin`（macOS）、`lockPortraitOrientation`（iOS）、`watchReceivedIDs`（iOS）です。

## 構想段階・未実装

リポジトリ内に、ロードマップや今後の構想を書いたドキュメントは見つかりませんでした。以下は**現時点で実装されていないことをコード上で確認した**項目です。今後実装する予定かどうかは不明です。

- Mac と iPhone の間のデータ同期（iCloud 等）
- macOS での Cue 編集、iOS の「共有」に相当する機能
- Apple Watch 上での Cue の編集・削除
- iPad 向けのレイアウト（iOS ターゲットは iPhone のみ。`TARGETED_DEVICE_FAMILY = 1`）
- Xcode のテストターゲットと CI（`.github/` はありません）
- ライセンスファイル

## ディレクトリ構成

```
Cue/              macOS アプリ（MenuBarController がパネルと ⌘⌘ 監視を担当）
CueiOS/           iPhone アプリ（WatchConnector が Watch との同期を担当）
CueWidget/        iOS ロック画面ウィジェット
CueWatch/         watchOS アプリ（PhoneConnector が iPhone との同期を担当）
CueWatchWidget/   watchOS コンプリケーション
Shared/           全ターゲット共通（CueItem, CueSettings, WatchSync）
Config/           Info.plist と entitlements（App Group 設定）
Tests/            単体実行するリグレッションチェック（Xcode ターゲット外）
icon.png          アプリアイコンの元画像
Cue.xcodeproj     Xcode プロジェクト（フォルダ同期グループ方式）
```

`Cue.xcodeproj` はフォルダ同期グループ（`PBXFileSystemSynchronizedRootGroup`）を使っています。上記フォルダにファイルを追加すれば、対応するターゲットに自動で含まれます。`Shared/` は全5ターゲットに含まれます。

## 必要環境

project.pbxproj から確認した値です。

| 項目 | 値 |
| --- | --- |
| macOS Deployment Target | 26.7 |
| iOS Deployment Target | 26.0 |
| watchOS Deployment Target | 26.0 |
| Swift 言語モード | 5.0（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`） |
| 外部依存 | なし（SwiftPM / CocoaPods 不使用） |
| 使用フレームワーク | SwiftUI, AppKit, UIKit, EventKit, WidgetKit, WatchConnectivity, ServiceManagement |

- **Xcode**: ターゲットは Xcode 26.3 で作成され、watchOS ターゲットは 27.0 で追加されています（`CreatedOnToolsVersion`）。ビルドできる最低バージョンは未確認です。
- **macOS / Apple Developer アカウント**: 署名は Automatic で、特定の Development Team が設定されています。自分の環境では Signing & Capabilities で自分の Team を選び直す必要があります。実機（iPhone / Watch）での実行や App Group の利用に有料の Apple Developer Program が必要かどうかは未確認です。

## セットアップ

1. リポジトリを clone し、`Cue.xcodeproj` を Xcode で開きます。
2. 各ターゲット（`Cue`、`CueiOS`、`CueWidget`、`CueWatch`、`CueWatchWidget`）の Signing & Capabilities で Team を選びます。
3. 自分の Team で実機に入れる場合は、Bundle Identifier と App Group ID を自分用に変更する必要があります。App Group ID は次の場所に直書きされているので、すべて揃えて変更してください。
   - `Config/*.entitlements`（4ファイル）
   - `CueiOS/CueStore.swift`、`CueWidget/CueWidget.swift`、`Shared/WatchSync.swift`
   - 確認コマンド: `grep -rn "group\." --include=*.swift --include=*.entitlements .`
   - あわせて、`CueWatch` の `WKCompanionAppBundleIdentifier` を iOS アプリの Bundle ID と一致させます。`Config/CueWatchInfo.plist` の URL 名も Bundle ID を含みます。
4. macOS ターゲット `Cue` の Bundle ID は `devplaceholder.…` のままです。macOS 版に entitlements ファイルはなく、サンドボックス設定はビルド設定（`ENABLE_APP_SANDBOX` 等）で行っています。

## 起動方法

共有スキームは `Cue`（macOS）と `CueiOS`（iOS）の2つです。

- **macOS**: スキーム `Cue`、実行先「My Mac」で Run します。起動するとメニューバーに電球アイコンが出ます。`Cue` ターゲットの `SUPPORTED_PLATFORMS` には iOS も含まれていますが、コードは AppKit 専用なので、Mac 向けにビルドしてください。
- **iOS**: スキーム `CueiOS` で iPhone（実機またはシミュレータ）を選んで Run します。`CueiOS` は `CueWidget` と `CueWatch` に依存し、それらを埋め込みます。
- **watchOS**: `CueWatch` は `CueiOS` に埋め込まれています。Watch 単体の共有スキームはありません（Xcode が自動生成するスキームを使うかどうかは環境次第で、未確認です）。
- コマンドラインからのビルド例（未検証）:
  ```sh
  xcodebuild -project Cue.xcodeproj -scheme Cue -destination 'platform=macOS' build
  xcodebuild -project Cue.xcodeproj -scheme CueiOS -destination 'generic/platform=iOS Simulator' build
  ```

### 実行時に必要な許可

- **リマインダー**: 初めて送信するときにフルアクセスを求めます（`NSRemindersFullAccessUsageDescription`）。拒否した場合は「Failed」と表示され、Cue は残ります。
- **macOS の ⌘⌘**: `NSEvent.addGlobalMonitorForEvents` で監視しています。コード内でアクセシビリティや入力監視の許可を求める処理はありません。他のアプリが前面にあるときにも動作するか、そのために許可が必要かは未確認です。
- **macOS のログイン時起動**: `SMAppService.mainApp` を使います。システム設定のログイン項目に表示されます。

## テスト

Xcode のテストターゲットはありません。`Tests/` 内の2ファイルは、`@main` を持つ単体実行用のリグレッションチェックです。`swiftc` で対象ソースと一緒にコンパイルして実行し、成功すると `... regression checks passed` と表示されます。失敗すると `precondition` でクラッシュします。

以下のコマンドはファイル冒頭のコメントと `#if IOS_STORE` から組み立てたもので、**実行確認はしていません**（macOS と Xcode のコマンドラインツールが必要です）。

```sh
mkdir -p build

# Watch 同期ロジック（Shared/WatchSync.swift）
swiftc Shared/CueItem.swift Shared/WatchSync.swift Tests/WatchSyncRegression.swift -o build/WatchSyncRegression
./build/WatchSyncRegression

# macOS 版 CueStore
swiftc Shared/CueItem.swift Cue/CueStore.swift Tests/CueStoreRegression.swift -o build/CueStoreRegression-macOS
./build/CueStoreRegression-macOS

# iOS 版 CueStore（-D IOS_STORE。WidgetKit を import するため macOS 上でビルドできるかは未確認）
swiftc -D IOS_STORE Shared/CueItem.swift CueiOS/CueStore.swift Tests/CueStoreRegression.swift -o build/CueStoreRegression-iOS
./build/CueStoreRegression-iOS
```

`build/` は `.gitignore` 済みです。テストは一意な名前の一時 `UserDefaults` スイートと一時ファイルだけを使い、終了時に削除します。

UI・リマインダー連携・ウィジェット・Watch 同期の実機動作には、自動テストがありません。
