# Crime Near Me (native iPhone app)

SwiftUI + Apple MapKit. No map token, nothing to renew.
Crime data: data.police.uk (England, Wales and Northern Ireland). Postcodes: postcodes.io.

## Build on Codemagic (no Mac needed)
1. Push this folder to a GitHub repo.
2. In Codemagic, add the repo and run the **Crime Near Me (native)** workflow.
   - XcodeGen creates the Xcode project from `project.yml`.
   - It signs with bundle ID `com.stevenwilliams.crimemap` and uploads to TestFlight (app ID 6836432396).

## Files
- `Sources/` – the Swift code
  - `CrimeMapView.swift` – Apple map, coloured pins, clusters, search circle
  - `ContentView.swift` – search bar, month picker, filter chips
  - `Sheets.swift` – filter panel and "crimes here" list
  - `PoliceAPI.swift` – police and postcode lookups
- `Resources/Assets.xcassets` – app icon, launch logo, colours
- `icon-alt-blue.png` – alternative icon. To use it, replace `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Using the app
- Search a postcode, tap the location button, or press and hold the map.
- After moving the map, tap **Search this area**.
- Tap a red cluster to list every crime at that spot. Tap a single dot for its details.
- **Filter** chooses crime types (remembered between launches). Chips give quick on/off.

## Downloadable history (2010 onwards)
1. Set up the **crime-near-me-data** repo (see its README) and run its GitHub Action once.
2. In `Sources/HistoryConfig.swift`, replace `YOUR_GITHUB_USERNAME` with your GitHub username.
3. Rebuild. In the app, tap the clock button to download a police force's history.
   Downloaded months appear in the month picker under "Downloaded history", and are included in **All dates**.

History is free for now. To make it a paid extra later, add an in-app purchase and change
`HistoryAccess.isUnlocked` in `Sources/HistoryConfig.swift`.
