#!/bin/bash

set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APK="$SCRIPT_DIR/Wi-Fi-ON.apk"
PACKAGE="io.github.ksuzukigh.rokidwifion"

pause_and_exit() {
    echo
    read -r -p "Enterキーを押してください..." _ || true
    exit "${1:-1}"
}

find_rokid_serial() {
    local serial model manufacturer fallback="" count=0

    while IFS= read -r serial; do
        [ -z "$serial" ] && continue
        fallback="$serial"
        count=$((count + 1))
        model="$(adb -s "$serial" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r' || true)"
        manufacturer="$(adb -s "$serial" shell getprop ro.product.manufacturer </dev/null 2>/dev/null | tr -d '\r' || true)"
        if [ "$model" = "RG-glasses" ] && [ "$manufacturer" = "Rokid" ]; then
            printf "%s" "$serial"
            return 0
        fi
    done < <(
        adb devices </dev/null |
            awk 'NR > 1 && $2 == "device" { print ($1 ~ /:/ ? "1" : "0"), $1 }' |
            sort -k1,1 -k2,2 |
            awk '{ print $2 }'
    )

    # 型番表記が変わった場合も、接続機器が1台だけなら確認画面へ進める。
    if [ "$count" -eq 1 ]; then
        printf "%s" "$fallback"
        return 0
    fi

    return 1
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
    echo "Rokidへアプリを入れるための接続ソフトを準備しています。"
    echo "ダウンロードに数分かかることがあります。そのままお待ちください..."
    if ! brew install android-platform-tools; then
        echo
        echo "接続ソフトを準備できませんでした。"
        echo "インターネット接続を確認してから、もう一度お試しください。"
        pause_and_exit 1
    fi
fi

# 接続中の全Android機器を調べ、RV101だけを対象にする。USB接続を優先する。
SERIAL="$(find_rokid_serial || true)"

if [ -z "$SERIAL" ]; then
    echo "Rokidを開発用5ピンケーブルでMacへつないでください。"
    echo "接続を最大60秒待ちます...（中止するには control + C）"

    NOTIFIED_UNAUTHORIZED=0
    for attempt in $(seq 1 60); do
        SERIAL="$(find_rokid_serial || true)"
        if [ -n "$SERIAL" ]; then
            echo
            break
        fi

        STATE="$(adb devices </dev/null | awk 'NR > 1 && $1 !~ /:/ { print $2; exit }' || true)"
        if [ "$STATE" = "unauthorized" ] && [ "$NOTIFIED_UNAUTHORIZED" -eq 0 ]; then
            NOTIFIED_UNAUTHORIZED=1
            echo
            echo "Rokidに確認画面が出ています。USB接続を許可してください。"
        fi
        printf "."
        sleep 1
    done
    echo
fi

if [ -z "$SERIAL" ]; then
    echo "Rokidを確認できませんでした。次の順に確認してください。"
    echo
    echo " 1. Rokidのスマホアプリ側で開発者モード（ADB）が有効になっているか"
    echo "    ※ 開発用5ピンケーブルをつなぐだけではADBは有効になりません。"
    echo " 2. ケーブルが充電用ではなく、Rokidの開発用5ピンケーブルか"
    echo " 3. Rokid以外のAndroid端末をMacから外したか"
    echo " 4. ケーブルが両端ともしっかり挿さっているか"
    echo
    echo "確認後、このファイルをもう一度ダブルクリックしてください。"
    pause_and_exit 1
fi

MODEL="$(adb -s "$SERIAL" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r' || true)"
MANUFACTURER="$(adb -s "$SERIAL" shell getprop ro.product.manufacturer </dev/null 2>/dev/null | tr -d '\r' || true)"
if [ "$MODEL" != "RG-glasses" ] || [ "$MANUFACTURER" != "Rokid" ]; then
    echo
    echo "接続機器をRokid AI Glasses RV101として自動で確認できませんでした。"
    echo
    echo "  Macから見えている機器: $MANUFACTURER $MODEL"
    echo "  想定している機器:       Rokid RG-glasses"
    echo
    echo "この機器がRokid AI Glasses本体でない場合は、ここで中止してください。"
    echo "（Rokid以外のAndroid端末がMacにつながっていると、この表示になります）"
    echo
    printf "上に表示された機器がRokid本体で間違いない場合だけ、y を入力してEnter: "
    FORCE=""
    read -r FORCE || true
    case "$FORCE" in
        y|Y|yes|YES) ;;
        *)
            echo "中止しました。ほかのAndroid機器を外し、Rokidをつなぎ直してからお試しください。"
            pause_and_exit 1
            ;;
    esac
fi

echo
echo "接続されている機器: $MANUFACTURER $MODEL"
echo
echo "このRokidに対して、次の2つを行います。"
echo
echo " 1. アプリ「Wi-Fi ON」をインストールします。"
echo " 2. 「Wi-Fi ON」に、システム設定を変更できる権限を与えます。"
echo "    （Rokidを再起動したあとでも、Wi-Fi復旧後にMacから操作できるようにするためです。"
echo "     この権限で変更するのは、Macとの接続に使う設定1つだけです。）"
echo
echo "2が不要な場合は、あとでRokidの設定からWi-Fi ONを削除してください。"
echo
printf "よろしければ y を入力してEnter: "
ANSWER=""
read -r ANSWER || true
case "$ANSWER" in
    y|Y|yes|YES) ;;
    *)
        echo "中止しました。機器と接続を確認してから、もう一度お試しください。"
        pause_and_exit 1
        ;;
esac

echo "Wi-Fi ONをRokidへ入れています..."
if ! adb -s "$SERIAL" install -r "$APK" </dev/null; then
    echo
    echo "インストールできませんでした。よくある原因は次の3つです。"
    echo
    echo " 1. デバッグ署名の旧版や、別の鍵で作った「Wi-Fi ON」が入っている"
    echo "    → Rokidの設定からWi-Fi ONを削除し、もう一度お試しください。"
    echo " 2. RokidのUSBデバッグの許可が取り消されている"
    echo "    → ケーブルを抜き差しし、Rokidに出る確認画面で許可してください。"
    echo " 3. ケーブルが緩んでいる"
    echo "    → 挿し直してから、もう一度お試しください。"
    pause_and_exit 1
fi

echo "Rokid再起動後もMac操作へ戻れるように設定しています..."
if ! adb -s "$SERIAL" shell pm grant "$PACKAGE" android.permission.WRITE_SECURE_SETTINGS </dev/null; then
    echo
    echo "アプリは入りましたが、Mac操作用の接続復旧を設定できませんでした。"
    echo "ケーブルとUSBデバッグの許可を確認して、もう一度お試しください。"
    pause_and_exit 1
fi

echo
echo "インストールが完了しました。"
echo "Rokidのアプリ一覧から『Wi-Fi ON』を開いてください。"
pause_and_exit 0
