package com.labibleont.ont

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
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
import com.labibleont.ont.data.bundle.AssetGlossaryRepository
import com.labibleont.ont.data.store.PreferencesStore
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.theme.ONTTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.features.lexicon.LexiconModel
import com.labibleont.ont.features.lexicon.LexiconTab
import com.labibleont.ont.features.lexicon.TermSheet
import com.labibleont.ont.features.reading.BibleTab
import com.labibleont.ont.features.reading.ChapterScreen
import com.labibleont.ont.features.reading.ReadingModel
import com.labibleont.ont.features.you.YouTab
import com.labibleont.ont.kit.reader.ReadingPreferences

/** Les trois onglets, dans l'ordre de la liseuse iOS. */
private enum class Onglet(val titre: String) {
    BIBLE("Bible"),
    LEXIQUE("Lexique"),
    VOUS("Vous"),
}

/**
 * L'unique activité, et la racine de composition.
 *
 * C'est **ici** que les implémentations rencontrent les ports : `ontfeatures`
 * ne connaît que `CorpusRepository` et `GlossaryRepository`, et ce sont ces
 * lignes-ci qui décident que derrière il y a des assets. Le jour où le corpus
 * viendra d'ailleurs — d'un téléchargement, d'un cache — c'est ce fichier qui
 * change, et lui seul.
 */
public class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val corpus = AssetCorpusRepository(applicationContext)
        val glossaire = AssetGlossaryRepository(applicationContext)
        val reglages = PreferencesStore(applicationContext)

        setContent {
            var preferences by remember { mutableStateOf(reglages.preferences) }

            val lecture: ReadingModel = viewModel(
                key = "lecture",
                factory = fabrique { ReadingModel(corpus, reglages) },
            )
            val lexique: LexiconModel = viewModel(
                key = "lexique",
                factory = fabrique { LexiconModel(glossaire) },
            )

            ONTTheme(theme = preferences.theme) {
                Racine(
                    lecture = lecture,
                    lexique = lexique,
                    preferences = preferences,
                    onPreferences = {
                        reglages.preferences = it
                        preferences = it
                    },
                )
            }
        }
    }

    private fun <T : ViewModel> fabrique(creer: () -> T) = object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <V : ViewModel> create(modelClass: Class<V>): V = creer() as V
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Racine(
    lecture: ReadingModel,
    lexique: LexiconModel,
    preferences: ReadingPreferences,
    onPreferences: (ReadingPreferences) -> Unit,
) {
    val theme = LocalReadingTheme.current
    var onglet by remember { mutableStateOf(Onglet.BIBLE) }
    var enLecture by remember { mutableStateOf(false) }
    var terme: String? by remember { mutableStateOf(null) }

    LaunchedEffect(Unit) { lecture.chargerLArborescence() }
    LaunchedEffect(onglet) { if (onglet == Onglet.LEXIQUE) lexique.charger() }

    // Le retour système ferme la lecture avant de quitter l'app. Sur Android
    // c'est le geste principal — le lui refuser oblige à viser une flèche.
    BackHandler(enabled = enLecture) { enLecture = false }

    Scaffold(
        containerColor = ONTColors.background(theme),
        topBar = {
            if (enLecture) {
                TopAppBar(
                    title = { Text(lecture.livre?.title.orEmpty()) },
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
        bottomBar = {
            if (!enLecture) {
                NavigationBar(containerColor = ONTColors.surface(theme)) {
                    for (o in Onglet.entries) {
                        NavigationBarItem(
                            selected = onglet == o,
                            onClick = { onglet = o },
                            icon = {
                                Icon(
                                    when (o) {
                                        Onglet.BIBLE -> Icons.AutoMirrored.Filled.MenuBook
                                        Onglet.LEXIQUE -> Icons.Filled.Translate
                                        Onglet.VOUS -> Icons.Filled.Person
                                    },
                                    contentDescription = o.titre,
                                )
                            },
                            label = { Text(o.titre) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = ONTColors.onBrand(theme),
                                selectedTextColor = ONTColors.brandInk(theme),
                                indicatorColor = ONTColors.brandInk(theme),
                                unselectedIconColor = ONTColors.inkSoft(theme),
                                unselectedTextColor = ONTColors.inkSoft(theme),
                            ),
                        )
                    }
                }
            }
        },
    ) { marges ->
        Box(modifier = Modifier.fillMaxSize().padding(marges)) {
            when {
                lecture.chargement -> CircularProgressIndicator(
                    color = ONTColors.accent(theme),
                    modifier = Modifier.align(Alignment.Center),
                )

                enLecture -> {
                    val chapitre = lecture.chapitre
                    if (chapitre == null) {
                        Text(
                            lecture.echec ?: "Rien à lire ici pour l'instant.",
                            color = ONTColors.inkSoft(theme),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    } else {
                        ChapterScreen(
                            chapitre = chapitre,
                            preferences = preferences,
                            onTerme = { lemme ->
                                // La fiche s'ouvre par-dessus le texte, sans le
                                // quitter : on consulte un terme et on revient à
                                // la ligne où l'on était.
                                lexique.charger()
                                terme = lemme
                            },
                        )
                    }
                }

                onglet == Onglet.BIBLE -> BibleTab(
                    model = lecture,
                    onOuvrir = { livre, unite ->
                        lecture.ouvrir(livre, unite)
                        enLecture = true
                    },
                )

                onglet == Onglet.LEXIQUE -> LexiconTab(
                    model = lexique,
                    onOuvrir = { terme = it },
                )

                else -> YouTab(preferences = preferences, onChange = onPreferences)
            }
        }
    }

    terme?.let { lemme ->
        ModalBottomSheet(
            onDismissRequest = { terme = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = ONTColors.surface(theme),
        ) {
            TermSheet(lemme = lemme, model = lexique, preferences = preferences)
        }
    }
}
