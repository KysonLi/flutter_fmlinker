# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`fmlink` (泛媒关联 / "Pan-Media Link") is a Flutter client app for the **ISLI** (International Standard Link Identifier) ecosystem. Users scan ISLI codes (typically printed in books) to link physical publications to digital resources — text, images, audio, video, 3D models, and HTML. The app also supports publishing publications, managing link/scan history, discovery, and account management.

The app targets Android, iOS, and **HarmonyOS (`ohos/`)**.

## Common Commands

```bash
flutter pub get                 # install/refresh dependencies
flutter run -d <device>         # run on a device/emulator (e.g. windows, chrome, <device-id>)
flutter analyze                 # static analysis (flutter_lints via analysis_options.yaml)
flutter test                    # run all tests (currently only test/widget_test.dart)
flutter test test/widget_test.dart   # run a single test file
flutter build apk               # release build (or ios / windows / web / etc.)
```

The base API URL and server are production (`http://apigateway.mpreader.com:11999` in `lib/common/constants.dart`); there is no staging/dev switch.

## Architecture

### Service layer — singleton + normalized response contract

Every service (`ApiService`, `AuthService`, `UserService`, `LinkService`, `PublishService`, `DiscoverService`) is a singleton:

```dart
static final FooService _instance = FooService._internal();
factory FooService() => _instance;
FooService._internal();
```

`ApiService` (`lib/services/api_service.dart`) is the single Dio entry point and the **only** place that should talk to the network. Key behaviors:

- A request interceptor injects the auth token header from `Constants.token` on every request.
- `validateStatus` returns `true` for all HTTP status codes — HTTP errors are **not** thrown; they flow into the same response handling as successes.
- All methods (`get`/`post`/`delete`/`upload`/`download`) return a **normalized `Map<String, dynamic>`** — never throw on business errors. The canonical shape is:

  ```dart
  {'status': bool, 'data': dynamic, 'msg': String}
  ```

- API success is determined by `_handleResponse`: the raw body's `resultCode`/`status` field equals `'00000000'` or `'0'`. Anything else is a failure whose message is resolved by `ErrorHandler.messageFor` (error-code lookup → server message → generic fallback).

> Gotcha: the normalized map key is `'msg'`, but a few call sites read `result['message']`. When touching service-result handling, use the canonical `status` / `data` / `msg` keys.

Higher-level services (`AuthService`, `LinkService`, …) wrap `ApiService`, returning the same normalized map. UI code checks `result['status'] == true`.

### Auth & token storage (dual location)

Login state lives in two places that must stay in sync:

- `SharedPreferences` keys (`Constants.kToken`, `kUserInfo`, `kUserId`) — the persistent source of truth, read via `UserService`.
- `Constants.token` — the **in-memory** static field the Dio interceptor actually reads.

Because `Constants.token` is `null` at startup and only the interceptor reads it, code that performs authenticated calls after a cold start (or after long idle) must call `UserService.refreshToken()` to re-hydrate `Constants.token` from storage before the request. `saveToken`/`clearUserInfo` keep both in sync; manual edits to one must update the other.

### Routing — go_router with flat route table

All routes are declared as a flat list of `GoRoute`s in `lib/routes/app_router.dart` (`AppRouter.router`), consumed by `MaterialApp.router` in `main.dart`. Two conventions for passing data to a destination:

- **Simple scalars** → URL query parameters, read via `state.uri.queryParameters[...]` (e.g. `/publication-detail?goodsId=...`, `/webview?url=...&title=...`).
- **Objects / multiple fields** → `state.extra`, cast to `Map<String, dynamic>` (or a model like `PublisherModel`). New screens that need rich input should follow the `extra`-as-map pattern (see `/publication-source-list`).

### App shell & navigation state

`MainScreen` (`lib/screens/main/main_screen.dart`) hosts a 5-tab `BottomNavigationBar` (关联/Publish/Scan/Discover/Profile). The active tab index lives in `TabProvider` (a `ChangeNotifier` provided at the app root via `provider`). To programmatically switch tabs from anywhere, call `context.read<TabProvider>().switchTab(index)` — this is how deep links return to a specific tab.

There is **no auth guard** in the router; login gating is done ad-hoc in screens.

### Global UI infrastructure

- `EasyLoading` is globally configured in `main.dart` (custom theme, `#409EFF` accent) and wired in via `MaterialApp.router`'s `builder: EasyLoading.init()`. Use `EasyLoading.show()/showError()/dismiss()` for loading and toast feedback.
- `Skeletonizer` is used for loading placeholders; `easy_refresh` for pull-to-refresh; `cached_network_image` for remote images.
- HTML resources are rendered with `webview_flutter` (`WebViewScreen`), and bundled help pages live under `assets/html/`.

### Domain concepts

- **ISLI code**: composed of `serviceCode` + `prefixCode` + `suffixCode` + a computed check bit. `ISLICodeUtil` (`lib/utils/isli_code_util.dart`) computes the check bit (weighted sum, mod-10) and builds the hyphenated full code. This is the core identifier scanned and resolved throughout the app.
- **Goods** = a publication (book). **Source** = a digital resource attached to a goods/publication. **Targets** = the resolved resources for a scanned ISLI code. These map to `/target-goods/app/v1/...` endpoints (see `LinkService`).
- **Resource types** are integer-coded (`Constants.resourceType*`, mirrored by the `ISLITargetType` enum in `isli_constants.dart`). Pricing strategies (`PricingStrategy` in the same file) are string constants like `CHAIN_UNIFORM_PRICE`.

### Error messaging

Backend error codes (e.g. `01010121`, `LOGIN-00030003`, `TARGET-GOODS-00030002`) are mapped to bilingual messages loaded from `assets/json/FMErrorStrings.json` by `ErrorHandler` (`lib/utils/error_handler.dart`), the single source of truth for user-facing error text. `ApiService` uses it for every response and connection error; UI code can call `ErrorHandler().messageFor(...)` / `fromError(e)` directly.

## Conventions

- Comments, UI text, and many identifiers are in **Chinese** — match this when editing existing code.
- Asset folders registered in `pubspec.yaml`: `assets/images/`, `assets/icons/`, `assets/html/`, `assets/html/book/`. Add new assets to one of these or declare a new folder entry.
- Print-based logging is pervasive in services (`print('GET请求: ...')`); follow that style for network debugging rather than introducing a logger.
