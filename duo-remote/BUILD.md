# Mac Remote (Duo) — build and install

Source: ~/Projects/DuoRemote (copied from the project's duo-remote/src folder).

1. `cd ~/Projects/DuoRemote && xcodegen generate` (brew install xcodegen if missing).
2. Fold API check: grep the iOS SDK headers for a fold/hinge/posture API, e.g.
   `grep -rli "hinge\|foldstate\|posture\|devicefold" $(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/UIKit.framework/Headers | head`.
   If one exists, use it in `RemoteViewController.mode` (laptop when half-folded, full when flat). Otherwise keep the shape-based default plus the layout button.
3. Build for device: `xcodebuild -project DuoRemote.xcodeproj -scheme DuoRemote -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates build`. Fix compile errors (the code was written without a compiler).
4. Install on the plugged-in Duo: `xcrun devicectl list devices`, then `xcrun devicectl device install app --device <id> <path to DuoRemote.app>`.
5. Test on the Mac itself: with Screen Sharing on, `nc -z localhost 5900`. The app signs in with the Mac account username + password (ARD auth, security type 30).

Key choices
- Protocol: RFB 3.8, ZRLE + CopyRect + Raw, DesktopSize and Cursor pseudo-encodings, 32bpp BGRX.
- ⌘ is sent as Super_L (0xffeb). If ⌘ shortcuts don't work, try Meta_L (0xffe7) in UI/Keys.swift.
- Two-finger scroll direction: `TrackpadView.naturalScrolling`.
