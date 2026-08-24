package com.labibleont.ont

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.labibleont.ont.data.bundle.AssetCorpusRepository
import com.labibleont.ont.data.store.PreferencesStore
import com.labibleont.ont.designsystem.theme.ONTTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.features.reading.BibleTab
import com.labibleont.ont.features.reading.ChapterScreen
import com.labibleont.ont.features.reading.ReadingModel

/**
 * L'unique activité, et la racine de composition.
 *
 * C'est **ici** que les implémentations rencontrent les ports : `ontfeatures`
 * ne connaît que `CorpusRepository`, et c'est cette ligne-ci qui décide que
 * derrière il y a des assets. Le jour où le corpus viendra d'ailleurs — d'un
 * téléchargement, d'un cache — c'est ce fichier qui change, et lui seul.
 *
 * `enableEdgeToEdge` avant `setContent` : le texte doit courir jusque sous la
 * barre d'état, comme sur iOS.
 */
public class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val corpus = AssetCorpusRepository(applicationContext)
        val reglages = PreferencesStore(applicationContext)

        setContent {
            val model: ReadingModel = viewModel(
                factory = object : ViewModelProvider.Factory {
                    @Suppress("UNCHECKED_CAST")
                    override fun <T : ViewModel> create(modelClass: Class<T>): T =
                        ReadingModel(corpus, reglages) as T
                },
            )
            val preferences = model.preferences

            ONTTheme(theme = preferences.theme) {
                Racine(model)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Racine(model: ReadingModel) {
    var enLecture by remember { mutableStateOf(false) }
    val theme = com.labibleont.ont.designsystem.theme.LocalReadingTheme.current

    LaunchedEffect(Unit) { model.chargerLArborescence() }

    Scaffold(
        containerColor = ONTColors.background(theme),
        topBar = {
            if (enLecture) {
                TopAppBar(
                    title = { Text(model.livre?.title.orEmpty()) },
                    navigationIcon = {
                        IconButton(onClick = { enLecture = false }) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Revenir au sommaire",
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent,
                        titleContentColor = ONTColors.brandInk(theme),
                        navigationIconContentColor = ONTColors.brandInk(theme),
                    ),
                )
            }
        },
    ) { marges ->
        Box(modifier = Modifier.fillMaxSize().padding(marges)) {
            when {
                model.chargement -> CircularProgressIndicator(
                    color = ONTColors.accent(theme),
                    modifier = Modifier.align(Alignment.Center),
                )

                enLecture -> {
                    val chapitre = model.chapitre
                    if (chapitre == null) {
                        Text(
                            model.echec ?: "Rien à lire ici pour l'instant.",
                            color = ONTColors.inkSoft(theme),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    } else {
                        ChapterScreen(
                            chapitre = chapitre,
                            preferences = model.preferences,
                            // La fiche de lexique viendra ; d'ici là un terme
                            // touché ne fait rien plutôt que de mentir.
                            onTerme = {},
                        )
                    }
                }

                else -> BibleTab(
                    model = model,
                    onOuvrir = { livre, unite ->
                        model.ouvrir(livre, unite)
                        enLecture = true
                    },
                )
            }
        }
    }
}
