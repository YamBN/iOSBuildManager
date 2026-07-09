# Keeping sideloaded apps alive automatically

Free Apple ID signing expires every **7 days**. iOS Build Manager keeps the
*build* side fresh on your Mac (scheduled rebuilds → new IPA in iCloud). This
guide covers the *device* side: an **on‑iPhone automation** that re‑signs your
already‑installed apps on a schedule using **SideStore**, with **no computer
required**.

Run both and your sideloaded apps essentially never expire.

---

## How it works

SideStore can refresh app signatures **on the device itself** by routing a
local connection through a small on‑device VPN (SideStore's *StosVPN* /
"LocalDev" profile). The trick is to drive that refresh automatically with the
**Shortcuts** app so it happens while you sleep:

```
enable local VPN  →  SideStore "Refresh All"  →  disable local VPN
```

Schedule it for the early morning a couple of times a week (e.g. **Saturday and
Sunday ~4:00 AM**) so the 7‑day window never lapses.

## Prerequisites

- **SideStore** installed and working, with your apps already sideloaded.
- SideStore's VPN profile installed (it's set up the first time SideStore runs).
- iOS 16 or newer recommended (for reliable time‑based automations).

## Set up the Shortcuts automation

1. Open **Shortcuts** → **Automation** tab → **+** → **Create Personal
   Automation**.
2. Choose **Time of Day**:
   - Time: **4:00 AM** (or any quiet hour).
   - Repeat: **Weekly**, and select **Saturday** and **Sunday**.
   - *(Create one automation per day if your iOS version only allows a single
     weekday per Time‑of‑Day automation.)*
3. Tap **Next**, then **New Blank Automation** and add these actions in order:
   1. **Set VPN** → turn **On** the SideStore / local‑dev VPN.
      *(If "Set VPN" doesn't list it, use a "Connect to VPN" toggle shortcut, or
      the SideStore‑provided shortcut if your version ships one.)*
   2. **Wait** → **5 seconds** (let the VPN come up).
   3. **Open App** → **SideStore**, then trigger **Refresh All**.
      *(Newer SideStore builds expose a "Refresh All Apps" shortcut action — use
      it directly instead of Open App if available; it's more reliable.)*
   4. **Wait** → **30–60 seconds** (let the refresh finish).
   5. **Set VPN** → turn **Off** the local‑dev VPN.
4. Tap **Next**, then turn **Ask Before Running → Off** so it runs unattended.
   Confirm **Don't Ask**.

That's it. The automation now re‑signs your apps twice a week automatically.

## Tips & caveats

- **Keep the phone on power and on Wi‑Fi** overnight so the automation can run.
- Some iOS versions still nag before "Open App" automations run. If yours does,
  prefer SideStore's dedicated **Refresh** shortcut action (step 3) which runs
  without opening the app.
- The exact toggle/action names differ between SideStore versions — the flow
  (**VPN on → refresh → VPN off**) is what matters.
- Free Apple IDs are limited to **3 sideloaded apps** and **10 App IDs / 7 days**;
  refreshing existing apps doesn't count against the App‑ID limit.

## The full loop

| Side | Tool | What it does | When |
|------|------|--------------|------|
| Mac | iOS Build Manager → scheduled builds | Rebuild + repackage IPA → iCloud | Weekly, within 7 days |
| iPhone | SideStore + Shortcuts (this guide) | Re‑sign installed apps on device | Sat & Sun, early AM |

Together: the Mac always has a fresh IPA ready, and the iPhone keeps the
installed copies signed — hands‑off.
