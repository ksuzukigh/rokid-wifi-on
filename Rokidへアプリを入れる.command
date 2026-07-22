#!/bin/bash

set -e
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APK="$SCRIPT_DIR/Wi-Fi-ON.apk"

pause_and_exit() {
    echo
    read -r -p "Enterキーを押してください..."
    exit "${1:-1}"
}

if [ ! -f "$APK" ]; then
    echo "Wi-Fi-ON.apkが見つかりません。ダウンロードしたフォルダを確認してください。"
    pause_and_exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "アプリを入れる準備が必要です。先にHomebrewをインストールしてください。"
        echo "https://brew.sh/ja/"
        pause_and_exit 1
    fi
    echo "Rokidへアプリを入れるためのソフトを準備しています..."
    brew install android-platform-tools
fi

# すでにWi-Fi経由で接続中ならそのまま使う。未接続なら開発用ケーブルを待つ。
SERIAL="$(adb devices | awk 'NR > 1 && $2 == "device" && $1 !~ /:/ { print $1; exit }')"
if [ -z "$SERIAL" ]; then
    SERIAL="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi

if [ -z "$SERIAL" ]; then
    echo "Rokidを開発用5ピンケーブルでMacへつないでください。"
    echo "接続を最大60秒待ちます..."

    for attempt in $(seq 1 60); do
        SERIAL="$(adb devices | awk 'NR > 1 && $2 == "device" && $1 !~ /:/ { print $1; exit }')"
        if [ -n "$SERIAL" ]; then
            break
        fi

        STATE="$(adb devices | awk 'NR > 1 && $1 !~ /:/ { print $2; exit }')"
        if [ "$STATE" = "unauthorized" ]; then
            echo "Rokidに確認画面が出たら、USB接続を許可してください。"
        fi
        sleep 1
    done
fi

if [ -z "$SERIAL" ]; then
    echo "Rokidを確認できませんでした。ケーブルを抜き差しして、もう一度お試しください。"
    pause_and_exit 1
fi

echo "Wi-Fi ONをRokidへ入れています..."
adb -s "$SERIAL" install -r "$APK"

echo
echo "インストールが完了しました。"
echo "Rokidのアプリ一覧から『Wi-Fi ON』を開いてください。"
pause_and_exit 0
