package com.labibleont.ont

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.labibleont.ont.data.bundle.AssetCorpusRepository
import com.labibleont.ont.data.bundle.AssetDailyVerseRepository
import com.labibleont.ont.data.bundle.AssetGlossaryRepository
import com.labibleont.ont.data.bundle.AssetSearchIndex
import com.labibleont.ont.data.store.FileReaderStore
import com.labibleont.ont.designsystem.catalog.DSCatalog
import com.labibleont.ont.designsystem.surfaces.ontScreen
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.theme.ONTTheme
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.features.lexicon.LexiconModel
import com.labibleont.ont.features.lexicon.LexiconTab
import com.labibleont.ont.features.lexicon.TermSheet
import com.labibleont.ont.features.qahal.QahalModel
import com.labibleont.ont.features.qahal.QahalTab
import com.labibleont.ont.features.reading.BibleTab
import com.labibleont.ont.features.reading.ChapterScreen
import com.labibleont.ont.features.reading.ReadingModel
import com.labibleont.ont.features.reading.ReferencePicker
import com.labibleont.ont.features.reading.SelectionBar
import com.labibleont.ont.features.search.SearchModel
import com.labibleont.ont.features.search.SearchScreen
import com.labibleont.ont.features.you.DailyVerseSettings
import com.labibleont.ont.features.you.DestinationVous
import com.labibleont.ont.features.you.ParutionsSettings
import com.labibleont.ont.features.you.ReadingSettings
import com.labibleont.ont.features.you.YouTab
import com.labibleont.ont.kit.corpus.plainText
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.notifications.VersetDuJourWorker
import kotlinx.coroutines.launch

/** Les quatre onglets, dans l'ordre de la liseuse iOS. */
private enum class Onglet(val titre: String) {
    QAHAL("Qahal"),
    BIBLE("Bible"),
    LEXIQUE("Lexique"),
    VOUS("Vous"),
}

/**
 * Où l'on est, au-dessus des onglets.
 *
 * Une pile à un seul étage plutôt qu'un graphe de navigation : l'app n'a que
 * des sous-écrans de premier niveau, et un `NavHost` demanderait de déclarer
 * des routes, de sérialiser des arguments et de tenir un état que trois
 * booléens décrivent déjà. On le prendra quand il y aura de quoi le remplir.
 */
private sealed interface Ecran {
    data object Onglets : Ecran
    data object Lecture : Ecran
    data object Recherche : Ecran
    data object Selecteur : Ecran
    data class Reglage(val ou: DestinationVous) : Ecran
}

/**
 * L'unique activité, et la racine de composition.
 *
 * C'est **ici** que les implémentations rencontrent les ports : `ontfeatures`
 * ne connaît que des interfaces, et ce sont ces lignes-ci qui décident que
 * derrière il y a des assets et un fichier JSON.
 */
public class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val corpus = AssetCorpusRepository(applicationContext)
        val glossaire = AssetGlossaryRepository(applicationContext)
        val index = AssetSearchIndex(applicationContext)
        val vivier = AssetDailyVerseRepository(applicationContext)
        val lecteur = FileReaderStore(applicationContext)

        setContent {
            var preferences by remember { mutableStateOf(lecteur.preferences) }

            val lecture: ReadingModel = viewModel(
                key = "lecture",
                factory = fabrique { ReadingModel(corpus, lecteur, lecteur, lecteur) },
            )
            val lexique: LexiconModel = viewModel(
                key = "lexique",
                factory = fabrique { LexiconModel(glossaire) },
            )
            val qahal: QahalModel = viewModel(
                key = "qahal",
                factory = fabrique { QahalModel(vivier, corpus) },
            )
            val recherche: SearchModel = viewModel(
                key = "recherche",
                factory = fabrique { SearchModel(index, glossaire) },
            )

            ONTTheme(theme = preferences.theme) {
                Racine(
                    lecture = lecture,
                    lexique = lexique,
                    recherche = recherche,
                    qahal = qahal,
                    preferences = preferences,
                    onPreferences = {
                        lecteur.preferences = it
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
    recherche: SearchModel,
    qahal: QahalModel,
    preferences: ReadingPreferences,
    onPreferences: (ReadingPreferences) -> Unit,
) {
    val theme = LocalReadingTheme.current
    val contexte = LocalContext.current
    var onglet by remember { mutableStateOf(Onglet.BIBLE) }
    var ecran: Ecran by remember { mutableStateOf(Ecran.Onglets) }
    var terme: String? by remember { mutableStateOf(null) }
    val messages = remember { SnackbarHostState() }
    val portee = rememberCoroutineScope()

    LaunchedEffect(Unit) { lecture.chargerLArborescence() }
    LaunchedEffect(onglet) {
        if (onglet == Onglet.LEXIQUE) lexique.charger()
        if (onglet == Onglet.QAHAL) qahal.choisir()
    }

    val demanderLaPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        // Refusée est une réponse : on programme quand même. Le travail ne
        // notifiera pas, et le jour où le lecteur change d'avis dans les
        // réglages système, le rappel est déjà là.
        VersetDuJourWorker.programmer(contexte, preferences.daily)
    }

    // Le retour défait une chose à la fois, de la plus fine à la plus large :
    // la sélection, puis l'écran. Fermer le chapitre alors qu'on venait de
    // désigner un verset serait une perte, pas un retour.
    BackHandler(enabled = ecran != Ecran.Onglets || lecture.selection.isNotEmpty()) {
        when {
            lecture.selection.isNotEmpty() -> lecture.deselectionner()
            ecran == Ecran.Selecteur -> ecran = Ecran.Lecture
            else -> ecran = Ecran.Onglets
        }
    }

    val titreDeLEcran = when (val e = ecran) {
        Ecran.Lecture -> lecture.livre?.title.orEmpty()
        Ecran.Recherche -> "Rechercher"
        Ecran.Selecteur -> "Aller à"
        is Ecran.Reglage -> when (e.ou) {
            DestinationVous.LECTURE -> "Réglages de lecture"
            DestinationVous.VERSET_DU_JOUR -> "Verset du jour"
            DestinationVous.PARUTIONS -> "Parutions"
            DestinationVous.CATALOGUE -> "Design system"
        }
        Ecran.Onglets -> null
    }

    Scaffold(
        // Transparent : le fond et son grain sont posés par `ontScreen`, en un
        // seul endroit, pour qu'ils ne puissent ni manquer ni se doubler.
        containerColor = Color.Transparent,
        modifier = Modifier.ontScreen(),
        snackbarHost = { SnackbarHost(messages) },
        topBar = {
            if (titreDeLEcran != null) {
                TopAppBar(
                    title = {
                        if (ecran == Ecran.Lecture) {
                            // Une pastille, pas un titre : elle dit où l'on est
                            // **et** elle s'ouvre. C'est le geste de YouVersion
                            // et de Bible Strong. Sans elle, aller de
                            // Bereshit 1 à Bereshit 18 demandait de revenir au
                            // sommaire, replier le livre, le déplier, viser.
                            PastilleDeRenvoi(
                                renvoi = lecture.chapitre?.title
                                    ?: lecture.livre?.title.orEmpty(),
                                onClick = { ecran = Ecran.Selecteur },
                            )
                        } else {
                            Text(titreDeLEcran)
                        }
                    },
                    navigationIcon = {
                        IconButton(
                            onClick = {
                                // Le sélecteur revient à la lecture, pas au
                                // sommaire : on l'a ouvert **depuis** un
                                // chapitre, et le fermer ne doit pas le perdre.
                                ecran = if (ecran == Ecran.Selecteur) {
                                    Ecran.Lecture
                                } else {
                                    Ecran.Onglets
                                }
                            },
                        ) {
                            // Une croix pour **fermer**, une flèche pour
                            // **revenir**. Le sélecteur porte déjà une flèche
                            // qui remonte d'une étape ; deux flèches empilées
                            // qui ne font pas la même chose se lisent comme un
                            // défaut, et on ne sait plus laquelle presser.
                            Icon(
                                if (ecran == Ecran.Selecteur) {
                                    Icons.Filled.Close
                                } else {
                                    Icons.AutoMirrored.Filled.ArrowBack
                                },
                                contentDescription = if (ecran == Ecran.Selecteur) {
                                    "Fermer sans changer de passage"
                                } else {
                                    "Revenir"
                                },
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent,
                        titleContentColor = ONTColors.brandInk(theme),
                        navigationIconContentColor = ONTColors.brandInk(theme),
                    ),
                )
            } else if (onglet == Onglet.BIBLE) {
                TopAppBar(
                    title = {},
                    actions = {
                        IconButton(onClick = { ecran = Ecran.Recherche }) {
                            Icon(Icons.Filled.Search, contentDescription = "Rechercher")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent,
                        actionIconContentColor = ONTColors.brandInk(theme),
                    ),
                )
            }
        },
        bottomBar = {
            if (ecran == Ecran.Lecture && lecture.selection.isNotEmpty()) {
                SelectionBar(
                    renvoi = lecture.renvoi(),
                    dejaMarquee = lecture.selectionEstMarquee(),
                    onCouleur = lecture::surligner,
                    onEffacer = lecture::effacerLesMarques,
                    onPartager = {
                        val passage = lecture.chapitre?.verses
                            ?.filter { it.n in lecture.selection }
                            ?.joinToString(" ") { it.nodes.plainText() }
                            .orEmpty()
                        partager(contexte, "« $passage »\n\n${lecture.renvoi()} — La Bible ONT")
                    },
                    onFermer = lecture::deselectionner,
                )
            } else if (ecran == Ecran.Onglets) {
                NavigationBar(containerColor = ONTColors.surface(theme)) {
                    for (o in Onglet.entries) {
                        NavigationBarItem(
                            selected = onglet == o,
                            onClick = { onglet = o },
                            icon = {
                                Icon(
                                    when (o) {
                                        Onglet.QAHAL -> Icons.Filled.Groups
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

                ecran is Ecran.Selecteur -> ReferencePicker(
                    model = lecture,
                    livreCourant = lecture.livre?.id,
                    uniteCourante = lecture.chapitre?.id,
                    onAller = { livre, unite, verset ->
                        lecture.ouvrir(livre, unite)
                        verset?.let { lecture.basculer(it) }
                        ecran = Ecran.Lecture
                    },
                )

                ecran is Ecran.Recherche -> SearchScreen(
                    model = recherche,
                    onOuvrir = { livre, unite ->
                        lecture.ouvrir(livre, unite)
                        ecran = Ecran.Lecture
                    },
                )

                ecran is Ecran.Reglage -> when ((ecran as Ecran.Reglage).ou) {
                    DestinationVous.LECTURE -> ReadingSettings(preferences, onPreferences)
                    DestinationVous.VERSET_DU_JOUR -> DailyVerseSettings(
                        preferences = preferences,
                        apercu = remember { VersetDuJourWorker.apercu(contexte) },
                        onChange = { rappel ->
                            onPreferences(preferences.copy(daily = rappel))
                            if (rappel.enabled &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                            ) {
                                demanderLaPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                            } else {
                                VersetDuJourWorker.programmer(contexte, rappel)
                            }
                        },
                    )
                    DestinationVous.PARUTIONS -> ParutionsSettings()
                    DestinationVous.CATALOGUE -> DSCatalog()
                }

                ecran is Ecran.Lecture -> {
                    val chapitre = lecture.chapitre
                    if (chapitre == null) {
                        Text(
                            lecture.echec ?: "Rien à lire ici pour l'instant.",
                            color = ONTColors.inkSoft(theme),
                            modifier = Modifier.align(Alignment.Center),
                        )
                    } else {
                        @Suppress("UNUSED_EXPRESSION") lecture.revisionDesMarques
                        ChapterScreen(
                            chapitre = chapitre,
                            preferences = preferences,
                            selection = lecture.selection,
                            onVerset = { n ->
                                lecture.basculer(n)
                                lecture.retenir(n)
                            },
                            marque = { verset -> lecture.surlignage(verset)?.color },
                            onTerme = { lemme ->
                                lexique.charger()
                                terme = lemme
                            },
                        )
                    }
                }

                onglet == Onglet.QAHAL -> QahalTab(
                    chapitre = qahal.chapitre,
                    verset = qahal.verset,
                    preferences = preferences,
                    onPartager = { partager(contexte, it) },
                )

                onglet == Onglet.BIBLE -> BibleTab(
                    model = lecture,
                    position = lecture.reprendre(),
                    onOuvrir = { livre, unite ->
                        lecture.ouvrir(livre, unite)
                        ecran = Ecran.Lecture
                    },
                )

                onglet == Onglet.LEXIQUE -> LexiconTab(
                    model = lexique,
                    onOuvrir = { terme = it },
                )

                else -> YouTab(
                    preferences = preferences,
                    slotsRediges = lecture.slotsRediges,
                    slotsTotal = lecture.slotsTotal,
                    versets = lecture.versets,
                    onAller = { ecran = Ecran.Reglage(it) },
                    enDeveloppement = BuildConfig.DEBUG,
                    onPasEncore = {
                        portee.launch {
                            messages.showSnackbar(
                                "La connexion arrive avec la synchronisation. " +
                                    "La lecture n'en a pas besoin.",
                            )
                        }
                    },
                )
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

/**
 * La pastille de renvoi, dans la barre du haut.
 *
 * Elle dit où l'on est et s'ouvre d'un appui. Le chevron le signale : sans lui,
 * elle se lirait comme un titre, et personne ne penserait à la toucher.
 */
@Composable
private fun PastilleDeRenvoi(renvoi: String, onClick: () -> Unit) {
    val theme = LocalReadingTheme.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(ONTRadius.pill))
            .background(ONTColors.brandInk(theme).copy(alpha = 0.10f))
            .clickable(onClick = onClick)
            .padding(start = 14.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
    ) {
        Text(renvoi, color = ONTColors.brandInk(theme), fontSize = 16.sp)
        Icon(
            Icons.Filled.ExpandMore,
            contentDescription = "Aller à un autre passage",
            tint = ONTColors.brandInk(theme),
        )
    }
}

/** Le partage système — le même d'un écran à l'autre. */
private fun partager(contexte: android.content.Context, texte: String) {
    contexte.startActivity(
        Intent.createChooser(
            Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, texte)
            },
            null,
        ),
    )
}
