package com.labibleont.ont

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.labibleont.ont.designsystem.theme.ONTTheme
import com.labibleont.ont.kit.reader.ReadingTheme

/**
 * L'unique activité.
 *
 * Une seule, et toute la navigation en Compose : c'est ce qui permet aux
 * transitions entre onglets d'être les mêmes qu'en SwiftUI, et au retour
 * prédictif d'Android de savoir ce qu'il va révéler avant que le geste soit
 * confirmé.
 *
 * `enableEdgeToEdge` avant `setContent` : le texte doit courir jusque sous la
 * barre d'état, comme sur iOS. Les marges de sécurité sont ensuite reprises
 * écran par écran.
 */
public class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            ONTTheme(theme = ReadingTheme.MYSTIQUE) {
                Racine()
            }
        }
    }
}

/**
 * Le point d'entrée de l'arbre composé.
 *
 * Provisoire : il porte la peau et rien d'autre, le temps que les écrans
 * arrivent. Il vaut déjà quelque chose — il prouve que la chaîne complète
 * compile, de `schema.rs` jusqu'à un pixel à l'écran.
 */
@Composable
private fun Racine() {
    Scaffold(modifier = Modifier.fillMaxSize()) { marges ->
        Column(modifier = Modifier.padding(marges).padding(24.dp)) {
            Text("La Bible ONT")
        }
    }
}
