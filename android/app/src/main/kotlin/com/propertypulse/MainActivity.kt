package com.propertypulse

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge: Flutter draws behind system bars (status bar + nav bar).
        // Matches iOS behaviour where content extends under the notch + home indicator.
        // Flutter SafeArea / MediaQuery.padding handles the insets per-screen.
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
