package dev.ziggy.ziggyexample

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val label = TextView(this)
        label.text = "Hello from ZiggyExample"
        val padding = (24 * resources.displayMetrics.density).toInt()
        label.setPadding(padding, padding, padding, padding)
        setContentView(label)
    }
}
