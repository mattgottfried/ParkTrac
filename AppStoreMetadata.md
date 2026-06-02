# ThrillTrack — App Store Metadata

## App Name
ThrillTrack

## Subtitle (30 chars max)
Disney & Universal Wait Times

## Description (4000 chars max — paste this into App Store Connect)

Skip the guesswork and get back to the fun.

ThrillTrack gives you live ride wait times, smart planning tools, and personal tracking for Walt Disney World and Universal Orlando — all in one app built for real park fans.

**Live Wait Times**
See every attraction's current wait time on an interactive map with color-coded pins. Green means go — red means come back later. Filter by park, search by name, or flip to the Shows tab to catch live entertainment schedules. The map auto-zooms to whichever park you're standing in.

**Smart Day Planner**
Build your day in minutes. The Smart Planner picks the optimal ride order based on predicted wait times and locks your show times in place. Add Lightning Lane return windows with a 10-minute notification before they close. Drag and reorder your plan on the fly.

**Personal Stats & History**
Log every ride with "Rode It!" Track which parks you visit most, your all-time ride count, and your top attractions. The Wait Accuracy tracker compares the posted wait time to how long you actually waited — so you'll know which rides always lie.

**Bucket List**
Work through every restaurant and hotel at both resorts. Rate each one, track your visits, and watch your progress grow. Every party member gets their own rating, so you'll always remember who loved it (and who didn't).

**Annual Pass Tools**
Set your pass tier, see your upcoming block-out dates on a crowd calendar, and track exactly how much your pass has saved you in gate tickets, dining discounts, and merch savings.

**Crowd Calendar**
See predicted crowd levels for any date up to a year out. Tap a day to get arrival advice tailored to how busy it'll be.

**More**
- Character meet locations and typical times
- Height checker for every ride
- Spending tracker by category (food, merch, Lightning Lane)
- Park hours for every park, every day
- AP perks & discount tracker

ThrillTrack is built for families and park enthusiasts who want to spend less time waiting and more time doing.

## Keywords (100 chars max — comma separated, no spaces after commas)
disney world,universal orlando,wait times,theme park,ride times,disney,universal,park map,crowd

## Support URL
(Needs an http:// URL — easiest options:)
- GitHub repo: https://github.com/YOUR_USERNAME/thrilltrack (make a public repo and use the URL)
- Or create a free page at https://thrilltrack.carrd.co with a contact form
- Or use a GitHub Gist for support info: https://gist.github.com/YOUR_USERNAME/...

## Privacy Policy URL
(Same options — paste the Gist URL from the template below. Gist URLs start with https://)

---

## Privacy Policy Template (paste into a GitHub Gist at gist.github.com)

**ThrillTrack Privacy Policy**
Last updated: May 2026

ThrillTrack ("the App") is a personal utility app for tracking theme park wait times and visits.

**Data We Collect**
- Location: Used only to center the map on the park you're visiting. Not stored, not shared, not linked to your identity.
- All other data (ride logs, ratings, spending, planner items) is stored locally on your device and optionally synced via iCloud to your own iCloud account. We never access it.

**Data We Do Not Collect**
We do not collect analytics, crash reports, advertising identifiers, or any personal information beyond what you explicitly enter.

**Third-Party Services**
- themeparks.wiki API: Fetches live wait time data. No personal data is sent.
- open-meteo.com API: Fetches local weather. No personal data is sent.
- iCloud (Apple): Optional sync of your personal data to your own iCloud account, governed by Apple's privacy policy.

**Contact**
mattgottfried@outlook.com

---

## App Store Connect — Privacy Nutrition Labels

Data Type: Location
- Collected: Yes
- Linked to identity: No
- Used for tracking: No
- Purpose: App Functionality

Data Type: Device ID
- Collected: Yes (by Google AdMob for ad serving)
- Linked to identity: No
- Used for tracking: No
- Purpose: Third-Party Advertising

Data Type: Usage Data
- Collected: Yes (by Google AdMob)
- Linked to identity: No
- Used for tracking: No
- Purpose: Third-Party Advertising

NOTE: Since we are NOT implementing ATT (App Tracking Transparency prompt),
AdMob runs in limited ads mode — no IDFA, no cross-app tracking.
All "Used for tracking" fields stay No.

---

## Age Rating Questionnaire Answers
- Made for Kids: No
- Cartoon/Fantasy Violence: None
- Realistic Violence: None
- Sexual Content: None
- Nudity: None
- Horror/Fear: None
- Mature/Suggestive Themes: None
- Gambling: None
- Medical/Treatment Info: None
- Alcohol/Tobacco/Drugs: None
→ Result: 4+

---

## IAP Setup in App Store Connect
Product Type: Non-Consumable
Reference Name: Remove Ads
Product ID: com.mattgottfried.parktrac.removeads
Price: $2.99 (Tier 3)
Display Name: Remove Ads
Description: Removes all ads from ThrillTrack permanently.

---

## Categories
Primary: Travel
Secondary: Utilities

---

## Pricing
Free (with $2.99 IAP to remove ads)

---

## Screenshots Needed (take from Xcode Simulator)
In Xcode: open the iPhone 17 Pro Max simulator, run the app, then
use the simulator's File → Save Screen (Cmd+S) for each screen.

Recommended 5 screens:
1. Wait Times map with ride pins visible (expand the bottom panel)
2. Ride detail sheet (tap any ride — shows wait time, predictions, Rode It button)
3. Smart Planner result (My Day tab → wand icon → pick some rides → Build My Schedule)
4. Stats view (Stats tab — shows restaurant progress, crowd calendar)
5. Settings → Unlock section (shows the Remove Ads IAP)

Size required: 1320 × 2868 px (iPhone 17 Pro Max gives this automatically)

---

## Upload Steps
1. Open Xcode → Window → Organizer
2. Select the ThrillTrack archive → Distribute App
3. Choose App Store Connect → Upload
4. Let Xcode sign and upload the build
5. In App Store Connect, go to your app → + next to Build
6. Select the uploaded build
7. Fill in all metadata above
8. Submit for Review
