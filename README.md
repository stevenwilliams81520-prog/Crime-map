# Crime Map (iPhone)

Street-level crime map for England, Wales and Northern Ireland using data.police.uk.

## Build on Codemagic (no Mac needed)
1. Push this folder to a new GitHub repo (don't commit `node_modules`, `ios` or `www/vendor`).
2. In App Store Connect, create the app with bundle ID `com.stevenwilliams.crimemap`
   (or change it in `capacitor.config.json` and `codemagic.yaml`).
3. In Codemagic, add the repo. It will pick up `codemagic.yaml` and use your "Berfau ASC" integration.
4. Run the **Crime Map iOS** workflow. The build goes to TestFlight.

## Test in a browser first
`npm install && npm run build`, then serve the `www` folder (for example `npx serve www`).

## Before App Store submission
- Add an app icon and splash (`npx @capacitor/assets generate` with a 1024×1024 `assets/icon.png`).
- Privacy label: Location (not linked to you, not used for tracking).
- In the description, explain that locations are approximate and the data lags 1–2 months.
