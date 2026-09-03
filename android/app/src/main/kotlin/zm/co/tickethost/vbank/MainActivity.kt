package zm.co.tickethost.vbank

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Back on the root route sends the app to the background instead of
        // finishing the activity: finishing tears down the Dart root isolate,
        // and the peer-to-peer node (a worker isolate) with it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vbank/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
