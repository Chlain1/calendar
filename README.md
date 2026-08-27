# CalendarApp

A SwiftUI-based iOS calendar app for local event management with synchronization through CalDAV and Apple Calendar. The app combines a weekly view, local SwiftData storage, and automatic sync logic with remote servers and the system calendar.

## Overview

CalendarApp is built to combine multiple calendar sources into one shared weekly view:

- CalDAV accounts for Nextcloud, ownCloud, Radicale, or similar servers
- Apple Calendar via EventKit
- local event storage in the app with SwiftData
- background synchronization for CalDAV accounts

The project is structured as a native iOS application and learning/prototype repository that demonstrates the core pieces of modern calendar integration: authentication, synchronization, parsing, and iCalendar serialization.

## Features

- weekly view with daily/time-grid and all-day events
- add, edit, and view calendar events for CalDAV-backed calendars
- CalDAV account setup with username, server URL, and password/app token
- automatic discovery of principal URL and calendar home set
- synchronization with CTag checks and delta updates
- integration with Apple Calendar through EventKit for display and sync
- Apple Calendar entries are mirrored read-only and cannot be edited from this app
- secure storage of CalDAV credentials in the Keychain
- background refresh for regular sync

## Requirements

- Xcode 15 or newer
- iOS 17 or newer
- an Apple Developer account for running on a device
- access to a CalDAV-compatible server

## Project structure

```text
calendar/
├── README.md
├── LICENSE
├── ExportOptions.plist
├── CalendarApp/
│   ├── CalendarAppApp.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   ├── Models/
│   │   ├── CalendarAccount.swift
│   │   ├── CalendarCollection.swift
│   │   └── CalendarEvent.swift
│   ├── CalDAV/
│   │   ├── CalDAVClient.swift
│   │   ├── ICalParser.swift
│   │   ├── ICalSerializer.swift
│   │   └── SyncManager.swift
│   ├── EventKit/
│   │   └── EventKitManager.swift
│   ├── Utilities/
│   │   ├── Color+Hex.swift
│   │   └── Keychain.swift
│   ├── ViewModels/
│   │   └── CalendarViewModel.swift
│   └── Views/
│       ├── AddEditEventView.swift
│       ├── EventDetailView.swift
│       ├── SettingsView.swift
│       └── WeekView.swift
└── CalendarApp.xcodeproj/
    └── project.pbxproj
```

## Core components

### App startup and initialization

- [CalendarApp/CalendarAppApp.swift](CalendarApp/CalendarAppApp.swift) starts the app and sets up the SwiftData container and synchronization managers.
- On app launch, the CalDAV and EventKit sync flows are triggered initially.

### Data models

- [CalendarApp/Models/CalendarAccount.swift](CalendarApp/Models/CalendarAccount.swift) describes a CalDAV or Apple Calendar account.
- [CalendarApp/Models/CalendarCollection.swift](CalendarApp/Models/CalendarCollection.swift) models individual calendar collections, such as server calendars or Apple calendars.
- [CalendarApp/Models/CalendarEvent.swift](CalendarApp/Models/CalendarEvent.swift) contains event data including dirty flags, ETags, links, and EventKit identifiers.

### CalDAV synchronization

- [CalendarApp/CalDAV/CalDAVClient.swift](CalendarApp/CalDAV/CalDAVClient.swift) handles HTTP requests, authentication, and CalDAV endpoints.
- [CalendarApp/CalDAV/ICalParser.swift](CalendarApp/CalDAV/ICalParser.swift) parses iCalendar data from CalDAV servers.
- [CalendarApp/CalDAV/ICalSerializer.swift](CalendarApp/CalDAV/ICalSerializer.swift) serializes local events back into iCalendar format.
- [CalendarApp/CalDAV/SyncManager.swift](CalendarApp/CalDAV/SyncManager.swift) performs the main sync flow: resolving collections, pushing local changes, and pulling remote updates.

### Apple Calendar

- [CalendarApp/EventKit/EventKitManager.swift](CalendarApp/EventKit/EventKitManager.swift) mirrors Apple calendars into the app and synchronizes them via EventKit.
- This integration is intentionally read-only: the app reads events from the system Calendar and displays them in the weekly view, but it does not write changes back to the Apple Calendar database.
- Any edits to Apple Calendar entries should be made in the native Apple Calendar app.
- The CalDAV sync path is the editable path in this project; Apple Calendar data is treated as a read-only mirror.

### UI

- [CalendarApp/Views/WeekView.swift](CalendarApp/Views/WeekView.swift) renders the weekly calendar view.
- [CalendarApp/Views/SettingsView.swift](CalendarApp/Views/SettingsView.swift) provides account and sync setup.
- [CalendarApp/Views/AddEditEventView.swift](CalendarApp/Views/AddEditEventView.swift) and [CalendarApp/Views/EventDetailView.swift](CalendarApp/Views/EventDetailView.swift) cover event creation, editing, and detail viewing.

## Usage

### 1. Open the project

```bash
open CalendarApp.xcodeproj
```

or open it directly in Xcode.

### 2. Run the app

- select the `CalendarApp` target
- choose a simulator or physical iPhone device
- sign the app with your team

### 3. Add a CalDAV account

- open the app settings
- tap `Add Account`
- enter the name, server URL, username, and password/app token
- the app will then test the connection to the server

### 4. Connect Apple Calendar

- in the `Apple Calendar` section, tap `Connect Apple Calendar`
- grant the app access to your calendars
- synchronization starts automatically after authorization
- these entries are displayed as a read-only mirror from the system calendar and are not edited from within this app

## Architecture notes

- SwiftData is used for local persistence.
- CalDAV credentials are stored in the Keychain instead of app storage.
- synchronization runs asynchronously and checks dirty flags plus remote ETags.
- the CalDAV flow supports creating, updating, and deleting events locally and syncing them with the server.
- the Apple Calendar flow is intentionally read-only and is used to display system calendar data inside the app without mutating the original EventKit store.
- background syncing is prepared using `BGAppRefreshTask`.

## License

This project is licensed under the terms in [LICENSE](LICENSE).

## Note

This is a working but intentionally minimal prototype calendar app. It is a strong base for extensions such as:

- multiple views (month/year)
- recurring events
- push-based synchronization
- better error handling and UI feedback
- support for multiple accounts with stronger filtering and visibility logic

This is a project I set up, as I could not find a good Week-View Calendar on Apple.