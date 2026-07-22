# Wi-Fi ON for Rokid Glasses

<p align="center"><img src="docs/images/wifi-on-overview.png" width="760" alt="Rokid GlassesでWi-Fi ONを開き、自宅Wi-Fiへ再接続する流れ"></p>

Rokid Glasses RV101のWi-Fiが切れたとき、メガネ単体で復旧するための小さなアプリです。

アプリ一覧から「Wi-Fi ON」を開くだけで、Wi-Fiを自動的にオンにし、以前使ったWi-Fiへ再接続します。普段の復旧ではMacも開発用5ピンケーブルも必要ありません。

## できること

1. Rokidで「Wi-Fi ON」を開く
2. アプリがWi-Fiを自動的にオンにする
3. 登録済みのWi-Fiへ自動的に再接続する

黒い画面に「Wi-Fiはオンです」「自宅Wi-Fiに接続しました」と表示されれば完了です。

## 最初の準備

### 1. この一式をMacへ保存する

GitHub画面上部の緑色の「Code」ボタンを押し、「Download ZIP」を選びます。ダウンロードしたZIPファイルをダブルクリックして開いてください。

### 2. Rokidへアプリを入れる

1. Rokidを開発用5ピンケーブルでMacへつなぎます。
2. `Rokidへアプリを入れる.command`をダブルクリックします。
3. RokidにUSB接続の確認が出た場合は許可します。
4. 「インストールが完了しました」と表示されたら準備完了です。

Macに止められた場合は、ファイルを右クリックして「開く」を選び、確認画面でもう一度「開く」を押してください。

ターミナルに「プロセスが完了しました」と出たら設定は終了しています。ウィンドウ左上の赤いボタン、または`command + W`で閉じてください。

## 普段の使い方

1. Rokidのアプリ一覧を開きます。
2. 「Wi-Fi ON」を選んで起動します。
3. 「Wi-Fiはオンです」と表示されるまで少し待ちます。

アプリを閉じたあともWi-Fiはオンのままです。このアプリが裏で動き続けることはありません。

## 自動でオンにならなかった場合

AndroidやRokidの更新などで自動操作が許可されなかった場合は、アプリが正式なWi-Fi設定画面を開きます。

Wi-Fiの行が選ばれているので、右テンプルを1回タップしてください。これは「Photo to Mac」がWi-Fi設定を開いたときと同じ操作です。

## 注意

- 以前接続したことがあるWi-Fiへ再接続するアプリです。
- 初めて使うWi-Fiでは、Rokidの設定画面でネットワーク名とパスワードを登録してください。
- Rokidが省電力動作や写真・動画の同期後にWi-Fiを切った場合は、もう一度「Wi-Fi ON」を開いてください。
- Rokid Glasses RV101の実機で確認しています。他の機種での動作は未確認です。

## 関連ツール

- [Photo to Mac](https://github.com/ksuzukigh/rokid-photo-to-mac)：Rokidで撮った写真をMacへ直接送信
- [Rokid Glasses Mac Control](https://github.com/ksuzukigh/rokid-mac-control)：Rokidの画面をMacに表示し、マウスとキーボードで操作

## 実機確認

Mac操作ツールのWi-Fi監視を停止した状態で、次を確認しています。

- Rokidの正式な設定画面からWi-Fiをオフ
- 「Wi-Fi ON」の起動だけでWi-Fiがオンへ復旧
- 自宅Wi-Fiへ自動再接続
- アプリを完全終了した30秒後も接続を維持
- 自動操作に失敗した場合は正式なWi-Fi設定を開く予備経路を搭載

<details>
<summary>開発者向け情報</summary>

### 仕組み

RV101はAndroid 12です。このアプリは、Androidに残されている旧来アプリ向けの互換動作を利用して、`WifiManager.setWifiEnabled(true)`を先に試します。

自動操作が拒否された場合、または8秒以内にオンにならなかった場合は、`Settings.ACTION_WIFI_SETTINGS`で正式な設定画面を開きます。

アプリはWi-Fiを常時監視するサービスではありません。起動時の復旧だけを行います。

### Androidアプリを自分で作り直す場合

JDK 17、Android SDKが必要です。

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
./gradlew assembleDebug
```

</details>
