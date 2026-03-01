# What Are Models?

**Models** are the **data layer** in Swift, i.e. the plain data structures and stateful stores that represent the app's domain objects. They don't know about buttons, screens, or HTTP calls. They just define *what things look like* and *how to persist/mutate them*.

In Swift/SwiftUI this maps almost 1:1 to concepts you already know:

| Swift / SwiftUI concept | Familiar equivalent |
|---|---|
| `struct` | A plain data class / record / POJO / dataclass |
| `class` with `@Published` properties | An observable store (think MobX store, Redux slice, or a ViewModel with reactive state) |
| `ObservableObject` protocol | Marks a class so the UI framework subscribes to its changes (like a reactive signal/store) |
| `@Published` property wrapper | Turns a property into an observable — any SwiftUI view reading it re-renders when it changes |
| `Codable` protocol | Built-in JSON/Plist serialization (like `Serializable` in Java or `dataclasses_json` in Python) |
| `Identifiable` protocol | Requires an `id` field so list/collection diffing works efficiently (similar to a `key` prop in React) |

---

## Existing Models in the SipBuddy App

### 1. `Incident` (struct) — *a single captured event*

```
struct Incident: Identifiable, Hashable
```

This is a **value type** (like a frozen dataclass). It holds everything about one captured incident:

- **`id: UUID`** — unique identifier
- **`startedAt: Date`** — timestamp
- **`location: CLLocation?`** — GPS coordinates (optional, note that we need to literallly go into XCode and change settings to allow this?)
- **`width`, `height`, `expectedFrames`** — metadata about the captured frames
- **`framesPNG: [Data]`** — an ordered array of raw PNG image data, appended progressively as frames arrive
- **`isComplete`** — a *computed property* (no backing storage, re-evaluated on access): returns `true` when all expected frames have been received

Think of it as a DTO / record that also carries some lightweight derived getters.

### 2. `IncidentStore` (class) — *the collection + persistence manager*

```
final class IncidentStore: ObservableObject
```

This is the **stateful store** for all incidents. Key ideas:

- **`@Published var incidents: [Incident]`** — the single source of truth. Any SwiftUI view that reads this property automatically re-renders when the array changes.
- **CRUD methods** like `startIncident()`, `appendFrame()`, `delete()`, `setPlaceName()` mutate the array and then call `saveToDisk()`.
- **Persistence** uses Apple's `PropertyListEncoder` to serialize a private `DiskIncident` (a `Codable` mirror of `Incident`) to a binary plist file on disk. On init, it loads from that file. This is conceptually identical to reading/writing JSON to a file, just in Apple's binary plist format for performance.
- **`NotificationCenter.default.post(...)`** — when an incident becomes complete, it fires an app-wide event (like an event bus / pub-sub).

If you're used to something like a Redux store or a repository pattern, `IncidentStore` is that: it owns the data, exposes mutation methods, and notifies subscribers (Views) reactively.

### 3. `AppState` (class) — *global UI state*

```
final class AppState: ObservableObject
```

A lightweight state container for **UI-level concerns** that don't belong to any single screen:

- **`mode: Mode`** — a simple state machine (`idle`, `sleeping`, `detecting`) backed by a `String` enum so it can be trivially persisted to `UserDefaults` (iOS's key-value store, like `localStorage`).
- **Presentation flags** (`showDevicePicker`, `showExperiments`, `bottomNotice`) — booleans/optionals that drive whether sheets and dialogs are shown.
- **`tab: Tab`** — tracks the selected tab; its `didSet` observer auto-clears the "unseen incident" badge when the user navigates to the incidents tab.
- **`BottomNotice`** — a small nested struct (an ephemeral "command object") carrying a title, message, and action closure, used to present toast-like notices.

This is essentially a **global reactive singleton** — injected once at the top of the view hierarchy and read by any child view that needs it.

### 4. `BuddyContact` (struct) + `BuddyStore` (class) — *emergency contacts*

```
struct BuddyContact: Identifiable, Codable, Equatable
final class BuddyStore: ObservableObject
```

- **`BuddyContact`** is a simple data record: `name`, `phone`, and a `DeliveryMode` enum (`autoSend` vs `askFirst`).
- **`BuddyStore`** manages a list of contacts plus a couple of config flags (`autoSendViaServer`, `webhookURL`). Persistence is via JSON ↔ `UserDefaults`. Every mutation triggers `save()` through Swift's `didSet` property observer (runs a callback every time the property is assigned).

### 5. BLE/Proximity helpers — *small utility models*

- **`ProximityBand`** — an enum (`immediate`, `near`, `far`) classifying BLE signal distance.
- **`SipNearby`** — represents a nearby device discovered via Bluetooth, with computed distance/band from the raw RSSI signal strength.
- **`estimatedMeters(fromRSSI:)`** — a free function implementing a simple radio path-loss model.

---

## Patterns to Notice

| Pattern | What it does | Why |
|---|---|---|
| `struct` for data, `class` for stores | Structs are value types (copied on assign, thread-safe by default). Classes are reference types needed for `ObservableObject`. | SwiftUI requires `ObservableObject` to be a class so it can hold a stable reference and notify subscribers. |
| `@Published` + `didSet` | `@Published` notifies SwiftUI. `didSet` runs side effects (persistence). | Keeps UI reactive *and* data durable with minimal boilerplate. |
| Private `DiskIncident` / `Snapshot` | Internal `Codable` structs that mirror the public model but are optimized for serialization. | Decouples the in-memory model shape from the on-disk format — you can evolve either independently. |
| Computed properties (`isComplete`, `meters`, `band`) | Derived state with no storage. | Avoids stale data — always consistent with the underlying fields. |
| `Identifiable` everywhere | Every model has a `UUID` id. | Required by SwiftUI's `List`/`ForEach` for efficient diffing (same concept as React's `key`). |

---
