package kg.ayant.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.ui.RootGate
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.SessionViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            AyantTheme {
                val session: SessionViewModel = viewModel()
                RootGate(session = session)
            }
        }
    }
}
