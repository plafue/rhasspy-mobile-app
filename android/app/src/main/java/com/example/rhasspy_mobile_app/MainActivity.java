package com.example.rhasspy_mobile_app;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PersistableBundle;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;

import java.util.Arrays;
import java.util.List;
import java.util.Objects;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterMain;

public class MainActivity extends FlutterActivity {
    WakeWordService mService;
    private static final String CHANNEL = "rhasspy_mobile_app/widget";
    boolean mBound;
    private MethodChannel channel = null;
    public MethodChannel channel2;
    public  MethodChannel wakeWordChannel;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState, @Nullable PersistableBundle persistentState) {
        super.onCreate(savedInstanceState, persistentState);
        if (!isTaskRoot()
                && getIntent().hasCategory(Intent.CATEGORY_LAUNCHER)
                && getIntent().getAction() != null
                && getIntent().getAction().equals(Intent.ACTION_MAIN)) {

            finish();
        }


    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        Bundle extras = getIntent().getExtras();
        channel = getMethodChannel(flutterEngine);
        if(extras != null && extras.containsKey("StartRecording"))  {
            channel.invokeMethod("StartRecording","test");
            Log.i("Home", extras.getString("StartRecording"));

        }

        super.configureFlutterEngine(flutterEngine);
         channel2 =new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "rhasspy_mobile_app");
        channel2.setMethodCallHandler((call, result) -> {
            if(call.method.equals("sendToBackground")){
                Log.i("Background", "sendToBackground");
                moveTaskToBack(true);
            }
        });
        wakeWordChannel =new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "wake_word");
        wakeWordChannel.setMethodCallHandler((call, result) -> {
            switch (call.method){
                case "stop":
                    Log.i("WaKeWord", "Stopping the foreground-thread");
                    //mService.stopService();
                    unbindService(connection);
                    mBound = false;
                    Intent intent = new Intent(getApplicationContext(), WakeWordService.class);
                    intent.setAction("Stop");
                    ContextCompat.startForegroundService(getApplicationContext(), intent);
                    result.success(true);
                    break;
                case "pause":
                    if(mBound){
                        mService.pause();
                        result.success(true);
                    } else {
                        result.error("NoRunningService","no service running",null);
                    }
                    break;
                case "resume":
                    if(mBound){
                        mService.resume();
                        result.success(true);
                    } else {
                        result.error("NoRunningService","no service running",null);
                    }
                    break;
                case "start":
                    Log.i("WaKeWord", "Starting the foreground-thread");
                    Intent serviceIntent = new Intent(getActivity().getApplicationContext(), WakeWordService.class);
                    serviceIntent.putExtra("wakeWordDetector",call.argument("wakeWordDetector").toString());
                    switch (call.argument("wakeWordDetector").toString()){
                        case "UDP":
                            serviceIntent.putExtra("ip", call.argument("ip").toString());
                            serviceIntent.putExtra("port", Integer.parseInt(call.argument("port").toString()));
                            break;
                        default:
                            result.error("UnsupportedWakeWord",null,null);
                            return;
                    }

                    ContextCompat.startForegroundService(getActivity(), serviceIntent);
                    bindService(serviceIntent, connection,BIND_IMPORTANT);
                    result.success(true);
                    break;
                case "isRunning":
                    Log.i("WaKeWord", "check if is listening");

                    if(!mBound || mService == null){
                        result.success(false);
                    } else {
                        result.success(true);
                    }
                    break;
                case "isListening":
                    Log.i("WaKeWord", "check if is listening");

                    if(!mBound || mService == null){
                        result.success(false);
                    } else {
                        result.success(!mService.isPaused);
                    }
                    break;
                case "getWakeWordDetector":
                    List<String> availableWakeWordDetector = Arrays.asList("UDP");
                    result.success(availableWakeWordDetector);
                    break;
            }
        });
    }


    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        Log.i("Home", "NewIntent");
        if(intent.getExtras() != null) {
            if (Objects.requireNonNull(intent.getExtras()).containsKey("StartRecording")) {
                Log.i("Home", intent.getExtras().getString("StartRecording"));
                if (channel == null) {
                    channel = getMethodChannel(null);
                }
                channel.invokeMethod("StartRecording", "");
            }
        }


    }

    private MethodChannel getMethodChannel(FlutterEngine engine) {
        Context context = getApplicationContext();
        FlutterMain.startInitialization(context);
        FlutterMain.ensureInitializationComplete(context, new String[]{""});


        // Instantiate a FlutterEngine.
        if(engine == null){
            engine = new FlutterEngine(context);
        }
        DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(FlutterMain.findAppBundlePath(),"");
        engine.getDartExecutor().executeDartEntrypoint(entryPoint);
        return new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    }
    private ServiceConnection connection = new ServiceConnection() {

        @Override
        public void onServiceConnected(ComponentName className,
                                       IBinder service) {
            // We've bound to LocalService, cast the IBinder and get LocalService instance
            WakeWordService.LocalBinder binder = (WakeWordService.LocalBinder) service;
            mService = binder.getService();
            mBound = true;
        }

        @Override
        public void onServiceDisconnected(ComponentName className) {
            mBound = false;
        }
    };

    @Override
    protected void onDestroy() {
        unbindService(connection);
        super.onDestroy();

    }
}

