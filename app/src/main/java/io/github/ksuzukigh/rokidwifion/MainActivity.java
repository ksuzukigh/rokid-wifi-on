package io.github.ksuzukigh.rokidwifion;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * RV101でWi-Fiを復旧するための小さなランチャーアプリ。
 * まず完全自動を試し、失敗した場合だけ正式なWi-Fi設定へ案内する。
 */
public final class MainActivity extends Activity {
    private static final String TAG = "RokidWifiOn";
    private static final String ROKID_SETTINGS_ACTION =
            "com.rokid.os.master.assist.server.cmd";
    private static final String ROKID_ASSIST_SERVER_PACKAGE =
            "com.rokid.os.sprite.assistserver";
    private static final String ROKID_WIFI_ENABLED_SETTING =
            "[{\"key\":\"settings_wifi_enable\",\"value\":\"true\"}]";
    private static final long AUTO_TIMEOUT_MS = 8000;
    private static final long STABILITY_CHECK_MS = 30000;
    private static final long POLL_MS = 500;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;
    private TextView detail;
    private WifiManager wifi;
    private boolean attempting;
    private boolean waitingForSettings;
    private boolean wirelessDebuggingRequested;
    private boolean wirelessDebuggingActionAttempted;
    private boolean wirelessDebuggingActionSucceeded;
    private long automaticStartedAt;
    private long enabledAt;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        makeUi();
    }

    @Override protected void onResume() {
        super.onResume();
        if (waitingForSettings) {
            waitingForSettings = false;
            if (isWifiEnabled()) {
                showEnabled();
                watchStability();
            } else {
                showManualNeeded();
            }
            return;
        }
        if (!attempting) {
            handler.postDelayed(this::startAutomaticEnable, 350);
        }
    }

    @Override protected void onPause() {
        // 画面を離れたら予約済みの確認を止める。戻ったときはonResumeからやり直す。
        handler.removeCallbacksAndMessages(null);
        attempting = false;
        // 開き直したときは接続待ちとMac操作用接続を最初から確認する。
        enabledAt = 0;
        wirelessDebuggingRequested = false;
        super.onPause();
    }

    @Override protected void onStop() {
        // 画面を閉じて次に開くときは、明示操作をもう一度求める。
        wirelessDebuggingActionAttempted = false;
        wirelessDebuggingActionSucceeded = false;
        super.onStop();
    }

    @Override protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private void makeUi() {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setGravity(Gravity.CENTER);
        panel.setPadding(38, 38, 38, 38);
        panel.setBackgroundColor(Color.BLACK);
        panel.setClickable(true);
        panel.setFocusable(true);
        panel.setOnClickListener(v -> onUserTap());

        TextView title = new TextView(this);
        title.setText("Wi-Fi ON");
        title.setTextColor(Color.rgb(120, 255, 155));
        title.setTextSize(27);
        title.setGravity(Gravity.CENTER);
        panel.addView(title);

        status = new TextView(this);
        status.setText("Wi-Fiを確認中…");
        status.setTextColor(Color.WHITE);
        status.setTextSize(28);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, 32, 0, 24);
        panel.addView(status);

        detail = new TextView(this);
        detail.setText("そのままお待ちください");
        detail.setTextColor(Color.LTGRAY);
        detail.setTextSize(16);
        detail.setGravity(Gravity.CENTER);
        panel.addView(detail);

        setContentView(panel);
        panel.requestFocus();
    }

    private void startAutomaticEnable() {
        persistRokidWifiEnabled();

        if (isWifiEnabled()) {
            showEnabled();
            watchStability();
            return;
        }

        attempting = true;
        automaticStartedAt = System.currentTimeMillis();
        status.setText("Wi-Fiをオンにしています…");
        detail.setText("まず自動で復旧を試します");

        boolean accepted = false;
        try {
            accepted = wifi != null && wifi.setWifiEnabled(true);
            Log.i(TAG, "Automatic Wi-Fi enable requested; accepted=" + accepted);
        } catch (SecurityException error) {
            Log.w(TAG, "Automatic Wi-Fi enable is not permitted", error);
        } catch (RuntimeException error) {
            Log.w(TAG, "Automatic Wi-Fi enable failed", error);
        }

        if (!accepted) {
            handler.postDelayed(this::openWifiSettings, 500);
            return;
        }
        handler.postDelayed(this::pollAutomaticEnable, POLL_MS);
    }

    /**
     * RV101はAndroid標準のWi-Fi状態とは別に、Rokid独自の設定値も保持している。
     * これをオンにしないと、再起動時にSpriteWifiServiceがWi-Fiをオフへ戻す。
     */
    private void persistRokidWifiEnabled() {
        try {
            Intent intent = new Intent(ROKID_SETTINGS_ACTION);
            intent.setPackage(ROKID_ASSIST_SERVER_PACKAGE);
            intent.putExtra("cmd_type", "setting_change");
            intent.putExtra("value", ROKID_WIFI_ENABLED_SETTING);
            sendBroadcast(intent);
            Log.i(TAG, "Rokid Wi-Fi preference enable requested");
        } catch (RuntimeException error) {
            // 将来のファームウェアでRokid独自経路が変わっても、
            // Android標準の自動オンと設定画面への予備経路は継続する。
            Log.w(TAG, "Could not update Rokid Wi-Fi preference", error);
        }
    }

    private void pollAutomaticEnable() {
        if (isWifiEnabled()) {
            attempting = false;
            enabledAt = System.currentTimeMillis();
            showEnabled();
            watchStability();
            return;
        }
        if (System.currentTimeMillis() - automaticStartedAt >= AUTO_TIMEOUT_MS) {
            attempting = false;
            Log.i(TAG, "Automatic enable timed out; opening official settings");
            openWifiSettings();
            return;
        }
        handler.postDelayed(this::pollAutomaticEnable, POLL_MS);
    }

    private void watchStability() {
        if (!isWifiEnabled()) {
            Log.i(TAG, "Wi-Fi was disabled again; opening official settings");
            attempting = false;
            openWifiSettings();
            return;
        }

        if (isWifiConnected()) {
            showConnectedActions();
        } else {
            detail.setText("Wi-Fi接続を待っています…");
        }

        if (enabledAt == 0) enabledAt = System.currentTimeMillis();
        if (System.currentTimeMillis() - enabledAt < STABILITY_CHECK_MS) {
            handler.postDelayed(this::watchStability, POLL_MS);
        } else if (isWifiConnected()) {
            showConnectedActions();
        } else {
            detail.setText("Wi-Fiはオンです。接続先を確認するにはタップ");
        }
    }

    /**
     * 初回セットアップで権限が付与されている場合だけ、Android標準の
     * 暗号化されたワイヤレスデバッグを有効化する。これによりRV101の
     * 再起動後も、Wi-Fi復旧後にMac操作ツールが再接続できる。
     */
    private boolean enableWirelessDebuggingIfPermitted() {
        if (wirelessDebuggingRequested) return true;
        if (checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
                != PackageManager.PERMISSION_GRANTED) {
            return false;
        }

        try {
            boolean updated = Settings.Global.putInt(
                    getContentResolver(), "adb_wifi_enabled", 1);
            if (updated) {
                wirelessDebuggingRequested = true;
                Log.i(TAG, "Secure wireless debugging enable requested");
                Toast.makeText(
                        this,
                        "Mac操作用の接続をオンにしました",
                        Toast.LENGTH_LONG
                ).show();
                return true;
            }
        } catch (SecurityException error) {
            Log.w(TAG, "Wireless debugging permission was not granted", error);
        } catch (RuntimeException error) {
            Log.w(TAG, "Could not enable secure wireless debugging", error);
        }
        return false;
    }

    private boolean isWifiEnabled() {
        return wifi != null && wifi.isWifiEnabled();
    }

    @SuppressWarnings("deprecation")
    private boolean isWifiConnected() {
        ConnectivityManager connectivity =
                (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo info = connectivity == null
                ? null : connectivity.getNetworkInfo(ConnectivityManager.TYPE_WIFI);
        return info != null && info.isConnected();
    }

    private void showEnabled() {
        attempting = false;
        status.setText("Wi-Fiはオンです");
        status.setTextColor(Color.rgb(120, 255, 155));
        detail.setText(isWifiConnected()
                ? connectedActionMessage()
                : "Wi-Fi接続を待っています…");
    }

    private void showConnectedActions() {
        detail.setText(connectedActionMessage());
    }

    private String connectedActionMessage() {
        if (wirelessDebuggingActionSucceeded) {
            return "Mac操作用の接続はオンです\nもう一度タップで閉じます";
        }
        if (wirelessDebuggingActionAttempted) {
            return "Mac操作用の接続をオンにできませんでした\nもう一度タップで閉じます";
        }
        return "Wi-Fiに接続しました\nMacから操作するときだけタップ";
    }

    private void showManualNeeded() {
        status.setText("Wi-Fiはまだオフです");
        status.setTextColor(Color.WHITE);
        detail.setText("テンプルを1回押して設定を開きます");
    }

    private void onUserTap() {
        if (isWifiEnabled() && isWifiConnected()) {
            if (!wirelessDebuggingActionAttempted) {
                wirelessDebuggingActionAttempted = true;
                wirelessDebuggingActionSucceeded =
                        enableWirelessDebuggingIfPermitted();
                if (wirelessDebuggingActionSucceeded) {
                    status.setText("Mac操作用の接続はオンです");
                }
                showConnectedActions();
                return;
            }
            finish();
            return;
        }
        openWifiSettings();
    }

    private void openWifiSettings() {
        handler.removeCallbacksAndMessages(null);
        attempting = false;
        waitingForSettings = true;
        status.setText("正式な設定でオンにします");
        status.setTextColor(Color.WHITE);
        detail.setText("Wi-Fiの項目でテンプルを1回押してください");
        Toast.makeText(this, "テンプルを1回押してWi-Fiをオン", Toast.LENGTH_LONG).show();
        try {
            startActivity(new Intent(Settings.ACTION_WIFI_SETTINGS));
        } catch (RuntimeException error) {
            Log.e(TAG, "Could not open Wi-Fi settings", error);
            waitingForSettings = false;
            status.setText("Wi-Fi設定を開けませんでした");
            detail.setText("画面をタップして再試行してください");
        }
    }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            onUserTap();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
