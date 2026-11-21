#!/bin/zsh
# usage: shots.sh <outdir>   — screenshots every phone + TV screen from the current build
OUT=$1; mkdir -p $OUT
cd ~/Projects/ChoreBlitz
P=94C147CE-9848-4CBB-BA17-DE484ADEA6F6; T=E82CFDF6-475B-4251-A072-B9A11026DA20
xcrun simctl boot $P 2>/dev/null; xcrun simctl boot $T 2>/dev/null
xcrun simctl bootstatus $P -b >/dev/null; xcrun simctl bootstatus $T -b >/dev/null
xcrun simctl status_bar $P override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4 2>/dev/null
xcrun simctl install $P build/Build/Products/Debug-iphonesimulator/ChoreBlitz.app
xcrun simctl install $T build/Build/Products/Debug-appletvsimulator/ChoreBlitzTV.app
phone() { # name me wait args...
  local name=$1 me=$2 w=$3; shift 3
  xcrun simctl terminate $P com.brandonbourne.ChoreBlitz 2>/dev/null
  xcrun simctl spawn $P defaults write com.brandonbourne.ChoreBlitz me "$me"
  xcrun simctl spawn $P defaults write com.brandonbourne.ChoreBlitz seenHint -bool ${HINT:-true}
  xcrun simctl launch $P com.brandonbourne.ChoreBlitz "$@" >/dev/null; sleep $w
  xcrun simctl io $P screenshot $OUT/phone-$name.png >/dev/null 2>&1
}
tv() { # name wait args...
  local name=$1 w=$2; shift 2
  xcrun simctl terminate $T com.brandonbourne.ChoreBlitzTV 2>/dev/null
  xcrun simctl launch $T com.brandonbourne.ChoreBlitzTV "$@" >/dev/null; sleep $w
  xcrun simctl io $T screenshot $OUT/tv-$name.png >/dev/null 2>&1
}
phone warmup kira 4 -demo
phone who "" 3 -demo
HINT=false phone today-kira-hint kira 3 -demo
phone today-braden braden 3 -demo
phone today-reagen reagen 3 -demo
phone idle-kira kira 3 -demoEmpty
phone idle-reagen reagen 3 -demoEmpty
phone finished-kira kira 3 -demoFinished
phone chores kira 3 -demo -screen chores
phone start kira 4 -demoEmpty -screen start
phone edit kira 4 -demo -screen edit
phone detail braden 4 -demo -screen detail
phone game-reagen reagen 3 -demoGame
phone spin reagen 4 -demoGame -screen spin
tv warmup 4 -demo
tv board 4 -demo
tv board-notimer 4 -demo -demoNoTimer
tv fresh 4 -demoFresh
tv idle 4 -demoEmpty
tv finished 4 -demoFinished
tv game 3 -demoGame
xcrun simctl terminate $T com.brandonbourne.ChoreBlitzTV 2>/dev/null
xcrun simctl shutdown all
rm -f $OUT/phone-warmup.png $OUT/tv-warmup.png
ls $OUT
