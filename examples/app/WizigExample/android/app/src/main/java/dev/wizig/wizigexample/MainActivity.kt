package dev.wizig.wizigexample

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.wizig.wizigexample.ui.theme.WizigExampleTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WizigExampleTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Greeting(
                        appName = "WizigExample",
                        modifier = Modifier.padding(innerPadding),
                    )
                }
            }
        }
    }
}

@Composable
private fun Greeting(appName: String, modifier: Modifier = Modifier) {
    var clickCount by remember { mutableStateOf(0) }
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Hello from $appName",
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            text = "Button clicks: $clickCount",
            style = MaterialTheme.typography.bodyMedium,
        )
        Button(
            onClick = {
                clickCount += 1
                Log.i("WizigExample", "Compose button clicked: $clickCount")
                println("Compose button clicked: $clickCount")
            },
        ) {
            Text("Click me")
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun GreetingPreview() {
    WizigExampleTheme {
        Greeting(appName = "WizigExample")
    }
}
