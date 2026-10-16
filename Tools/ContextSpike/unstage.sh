#!/bin/zsh
# Closes what stage.sh opened, without saving, and nothing else.
cd "${0:A:h}"
for name in "Acme Q3 proposal.docx" "Best man speech.docx" "Acme offsite plan.docx"; do
  osascript -e "tell application \"Microsoft Word\" to close (every document whose name is \"$name\") saving no" 2>/dev/null
done
for name in "acme-q3-pricing.csv" "fantasy-football-2026.csv"; do
  osascript -e "tell application \"Microsoft Excel\" to close (every workbook whose name is \"$name\") saving no" 2>/dev/null
done
for name in "acme-call-notes.txt" "chapter-3.txt" "CheckoutViewController crash.log"; do
  osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$name\") saving no" 2>/dev/null
done
osascript -e 'tell application "Xcode" to close (every document whose name is "SessionControls.swift") saving no' 2>/dev/null
for match in documentation/foundationmodels Crash_Bandicoot bbc.co.uk/sport/football swift-format/issues sourdough wiki/Groomsman; do
  osascript -e "tell application \"Safari\" to close (every window whose URL of current tab contains \"$match\")" 2>/dev/null
done
echo unstaged
