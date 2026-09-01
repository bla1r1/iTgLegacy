#!/bin/bash
echo "Starting screenshot capture..."
mkdir -p ~/Desktop/Telegram_Screenshots
for i in {1..5}; do
  idevicescreenshot ~/Desktop/Telegram_Screenshots/screenshot_$i.png
  echo "Took screenshot $i"
  sleep 3
done
echo "Done!"
