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
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
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
import com.labibleont.ont.features.reading.ReadingSettingsSheet
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
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.compose.runtime.collectAsState
import com.labibleont.ont.kit.reader.LienProfond
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import com.labibleont.ont.features.reading.GlissementDUnite
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItemColors
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.NavigationDrawerItemDefaults
import com.labibleont.ont.kit.reader.ReadingTheme

/** Les quatre onglets, dans l'ordre de la liseuse iOS. */
private enum class Onglet(val titre: String) {
    QAHAL("Qahal"),
    BIBLE("Bible"),
    LEXIQUE("Lexique"),
    VOUS("Vous"),
}

/**
 * L'onglet se range par son **nom**, jamais par son rang.
 *
 * Un `ordinal` enregistré désignerait un autre onglet le jour où l'ordre
 * changerait — et l'ordre est justement ce qu'on discute, puisqu'il suit
 * aujourd'hui celui de la liseuse iOS. Un nom inconnu retombe sur Bible.
 */
private val OngletSaver: Saver<Onglet, Any> = Saver(
    save = { it.name },
    restore = { nom -> Onglet.entries.firstOrNull { it.name == nom } },
)

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
    data class Selecteur(val livre: String? = null) : Ecran
    data class Reglage(val ou: DestinationVous) : Ecran
}

/**
 * De quoi faire survivre [Ecran] à une rotation et à la mort du processus.
 *
 * `rememberSaveable` passe par un `Bundle`, qui ne sait pas ranger une
 * interface scellée. On dit donc comment : une étiquette, et l'argument quand
 * il y en a un.
 *
 * ## Pourquoi la restauration ne lève jamais
 *
 * L'état rendu peut avoir été écrit par une **version antérieure de l'app** —
 * le système garde le `Bundle` par-dessus une mise à jour. Une étiquette
 * inconnue, ou un `DestinationVous` qui n'existe plus, ne doit donc pas faire
 * planter au retour. `valueOf` aurait levé.
 *
 * On rend alors `null`, et non l'état de départ écrit à la main. Les deux
 * donnent aujourd'hui le même écran, mais ils ne disent pas la même chose :
 * `null` déclare « je n'ai pas su relire » et laisse la valeur initiale
 * jouer, quelle qu'elle devienne. Écrire `Ecran.Onglets` ici, ce serait
 * réaffirmer une valeur par défaut à un second endroit — et le jour où le
 * premier changerait, celui-ci resterait en arrière sans que rien ne le
 * signale.
 *
 * Un état restauré **faux** est pire qu'un état perdu : le lecteur ne peut
 * pas savoir qu'il a été déplacé.
 */
private val EcranSaver: Saver<Ecran, Any> = listSaver(
    save = { ecran ->
        when (ecran) {
            Ecran.Onglets -> listOf("onglets", null)
            Ecran.Lecture -> listOf("lecture", null)
            Ecran.Recherche -> listOf("recherche", null)
            is Ecran.Selecteur -> listOf("selecteur", ecran.livre)
            is Ecran.Reglage -> listOf("reglage", ecran.ou.name)
        }
    },
    restore = { enregistre ->
        val argument = enregistre.getOrNull(1)
        when (enregistre.getOrNull(0)) {
            "onglets" -> Ecran.Onglets
            "lecture" -> Ecran.Lecture
            "recherche" -> Ecran.Recherche
            "selecteur" -> Ecran.Selecteur(argument)
            "reglage" ->
                DestinationVous.entries.firstOrNull { it.name == argument }
                    ?.let { Ecran.Reglage(it) }
            else -> null
        }
    },
)

/**
 * L'unique activité, et la racine de composition.
 *
 * C'est **ici** que les implémentations rencontrent les ports : `ontfeatures`
 * ne connaît que des interfaces, et ce sont ces lignes-ci qui décident que
 * derrière il y a des assets et un fichier JSON.
 */
public class MainActivity : ComponentActivity() {

    /**
     * L'adresse qu'on nous demande d'ouvrir, s'il y en a une.
     *
     * ## Pourquoi un flux et pas une lecture de `intent` dans la composition
     *
     * Une `Intent` peut arriver alors que l'activité **existe déjà** — c'est
     * même le cas courant : la notification du verset du jour ou le widget
     * réveillent une app déjà lancée. `onCreate` ne s'exécute alors pas, et un
     * lien lu là ne marcherait qu'à froid. D'où `onNewIntent`, et un flux que
     * la composition observe au lieu d'un champ qu'elle relirait sans savoir
     * qu'il a changé.
     *
     * `null` après consommation : sans ça, revenir sur l'app rejouerait le
     * dernier lien et arracherait le lecteur à sa page.
     */
    private val adresseRecue = MutableStateFlow<String?>(null)

    /**
     * L'app était déjà là, et on lui demande d'ouvrir autre chose.
     *
     * `super` d'abord : sans lui, `getIntent()` continue de rendre l'ancienne
     * et le lien suivant rouvrirait le précédent.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        adresseRecue.value = intent.dataString
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        adresseRecue.value = intent?.dataString

        val corpus = AssetCorpusRepository(applicationContext)
        val glossaire = AssetGlossaryRepository(applicationContext)
        val index = AssetSearchIndex(applicationContext)
        val vivier = AssetDailyVerseRepository(applicationContext)
        val lecteur = FileReaderStore(applicationContext)

        setContent {
            val adresse by adresseRecue.collectAsState()
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

            // Une seule source de vérité pour les réglages : celle du modèle.
            // Une copie locale ici avait paru inoffensive tant que la feuille
            // de réglages était seule à écrire — mais deux états pour un même
            // réglage finissent toujours par diverger, et c'est « Le français
            // reçu » qui l'a montré : l'arborescence lisait l'un, la feuille
            // écrivait l'autre.
            val preferences = lecture.preferences

            ONTTheme(theme = preferences.theme) {
                AvecOuverture {
                Racine(
                    lecture = lecture,
                    lexique = lexique,
                    recherche = recherche,
                    qahal = qahal,
                    preferences = preferences,
                    onPreferences = { lecture.changerLesPreferences(it) },
                    adresse = adresse,
                    onAdresseSuivie = { adresseRecue.value = null },
                )
                }
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
    adresse: String?,
    onAdresseSuivie: () -> Unit,
    lecture: ReadingModel,
    lexique: LexiconModel,
    recherche: SearchModel,
    qahal: QahalModel,
    preferences: ReadingPreferences,
    onPreferences: (ReadingPreferences) -> Unit,
) {
    val theme = LocalReadingTheme.current
    val contexte = LocalContext.current
    val haptique = LocalHapticFeedback.current
    // `rememberSaveable` et non `remember` : `configChanges` n'est pas déclaré,
    // donc l'activité est recréée à chaque changement de configuration. Avec un
    // simple `remember`, tourner le téléphone renvoyait le lecteur à l'onglet
    // Bible, en haut de page, quel que soit l'endroit où il lisait.
    //
    // Et ça ne va pas s'arranger tout seul : en `targetSdk 36`, au-delà de
    // 600 dp de large, les fenêtres se redimensionnent librement et chaque
    // redimensionnement recrée l'activité. Ce qui ne se voyait qu'en tournant
    // le téléphone deviendrait une perte ordinaire sur tablette.
    //
    // L'onglet se range par son nom plutôt que par son rang : un `ordinal`
    // enregistré désignerait un autre onglet le jour où l'ordre changerait.
    var onglet by rememberSaveable(stateSaver = OngletSaver) {
        mutableStateOf(Onglet.BIBLE)
    }
    var ecran: Ecran by rememberSaveable(stateSaver = EcranSaver) {
        mutableStateOf(Ecran.Onglets)
    }
    var terme: String? by rememberSaveable { mutableStateOf(null) }
    var reglagesOuverts by rememberSaveable { mutableStateOf(false) }
    val messages = remember { SnackbarHostState() }
    val portee = rememberCoroutineScope()

    LaunchedEffect(Unit) { lecture.chargerLArborescence() }

    // ## Suivre une adresse reçue
    //
    // Elle vient d'une notification, d'un widget, ou d'une conversation. On la
    // consomme une fois — `onAdresseSuivie` la remet à null — sinon revenir sur
    // l'app rejouerait le dernier lien et arracherait le lecteur à sa page.
    //
    // La sélection est posée après `ouvrir`, jamais avant : `ouvrir` charge
    // l'unité et remet la sélection à zéro. L'ordre inverse désignait des
    // versets puis les oubliait aussitôt.
    LaunchedEffect(adresse) {
        val lien = adresse?.let { LienProfond.lire(it) } ?: return@LaunchedEffect
        when (lien) {
            is LienProfond.Lecture -> {
                onglet = Onglet.BIBLE
                ecran = Ecran.Onglets
            }
            is LienProfond.Livre -> {
                onglet = Onglet.BIBLE
                ecran = Ecran.Onglets
                lecture.ouvrir(lien.livreId)
            }
            is LienProfond.Unite -> {
                onglet = Onglet.BIBLE
                lecture.ouvrir(lien.livreId, lien.uniteId)
                ecran = Ecran.Lecture

                // ## Les versets demandés sont bornés à ceux qui existent
                //
                // Une adresse vient du dehors : elle peut avoir été retapée,
                // tronquée, ou bricolée. Sans cette borne, `?v=999` désignait
                // un verset absent — et la position de lecture retenue s'en
                // trouvait empoisonnée : la carte « Reprendre » aurait affiché
                // un renvoi qui n'existe pas, et le lancement suivant aurait
                // visé le vide.
                //
                // Le défaut a été trouvé côté iOS, à la faveur d'une question
                // qu'on s'est posée en accordant le format. Il ne se voit pas
                // dans le cas nominal — c'est exactement ce qu'un portage
                // recopie sans le remarquer.
                if (lien.versets.isNotEmpty()) {
                    // `ouvrir` charge dans une coroutine : lire `chapitre` tout
                    // de suite rendrait celui d'avant, ou `null`. On attend que
                    // l'unité demandée soit là — avec une borne de temps, faute
                    // de quoi un identifiant inconnu suspendrait l'effet pour
                    // toujours et la sélection ne viendrait jamais.
                    val arrivee = withTimeoutOrNull(5_000) {
                        snapshotFlow { lecture.chapitre }
                            .filterNotNull()
                            .first { it.id == lien.uniteId }
                    }
                    val reels = arrivee?.verses?.map { it.n }?.toSet().orEmpty()
                    val retenus = lien.versets.filter { it in reels }
                    if (retenus.isNotEmpty()) {
                        lecture.deselectionner()
                        retenus.forEach { lecture.basculer(it) }
                    }
                }
            }
        }
        onAdresseSuivie()
    }
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
            ecran is Ecran.Selecteur -> ecran = Ecran.Lecture
            else -> ecran = Ecran.Onglets
        }
    }

    val titreDeLEcran = when (val e = ecran) {
        Ecran.Lecture -> lecture.livre?.title.orEmpty()
        Ecran.Recherche -> "Rechercher"
        is Ecran.Selecteur -> "Aller à"
        is Ecran.Reglage -> when (e.ou) {
            DestinationVous.LECTURE -> "Réglages de lecture"
            DestinationVous.VERSET_DU_JOUR -> "Verset du jour"
            DestinationVous.PARUTIONS -> "Parutions"
            DestinationVous.CATALOGUE -> "Design system"
        }
        Ecran.Onglets -> null
    }

    // ## La barre devient un rail quand l'écran s'élargit
    //
    // C'est le comportement d'iOS, qui pose `.tabViewStyle(.sidebarAdaptable)`
    // et voit sa barre d'onglets se muer en barre latérale sur iPad. Android
    // n'avait **rien** : la barre du bas restait la barre du bas, y compris sur
    // une tablette ou une fenêtre redimensionnée, où elle mange de la hauteur
    // pour rien alors que la largeur abonde.
    //
    // `NavigationSuiteScaffold` décide seul selon la largeur de fenêtre — et
    // c'est bien la **fenêtre**, pas l'écran : sous `targetSdk 36`, au-delà de
    // 600 dp, le lecteur redimensionne librement, et une mesure prise sur
    // l'écran mentirait à chaque poignée déplacée.
    //
    // `None` hors des onglets : en lecture ou dans un sélecteur, il n'y a pas
    // de destination à proposer, et un rail vide sur le côté d'un chapitre
    // n'est qu'une bande perdue.
    val couleursDeSuite = suiteCouleurs(theme)
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            if (ecran == Ecran.Onglets) {
                for (o in Onglet.entries) {
                    item(
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
                        colors = couleursDeSuite,
                    )
                }
            }
        },
        layoutType = if (ecran == Ecran.Onglets) {
            NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo())
        } else {
            NavigationSuiteType.None
        },
        containerColor = ONTColors.background(theme),
    ) {
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
                                onClick = { ecran = Ecran.Selecteur() },
                            )
                        } else {
                            Text(titreDeLEcran)
                        }
                    },
                    actions = {
                        if (ecran == Ecran.Lecture) {
                            // On règle la taille du texte quand on bute dessus,
                            // pas quand on y pense. Obliger à quitter le
                            // chapitre pour y aller, c'est garantir que
                            // personne n'y touchera jamais.
                            IconButton(onClick = { reglagesOuverts = true }) {
                                Icon(
                                    Icons.Filled.FormatSize,
                                    contentDescription = "Réglages de lecture",
                                )
                            }
                        }
                    },
                    navigationIcon = {
                        IconButton(
                            onClick = {
                                // Le sélecteur revient à la lecture, pas au
                                // sommaire : on l'a ouvert **depuis** un
                                // chapitre, et le fermer ne doit pas le perdre.
                                ecran = if (ecran is Ecran.Selecteur) {
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
                                if (ecran is Ecran.Selecteur) {
                                    Icons.Filled.Close
                                } else {
                                    Icons.AutoMirrored.Filled.ArrowBack
                                },
                                contentDescription = if (ecran is Ecran.Selecteur) {
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
                        actionIconContentColor = ONTColors.brandInk(theme),
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
                    livreImpose = (ecran as Ecran.Selecteur).livre,
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
                        GlissementDUnite(
                            peutAllerAvant = lecture.precedente() != null,
                            peutAllerApres = lecture.suivante() != null,
                            uniteCourante = chapitre.id,
                            onAvant = { lecture.precedente()?.let { lecture.aller(it) } },
                            onApres = { lecture.suivante()?.let { lecture.aller(it) } },
                        ) {
                        ChapterScreen(
                            chapitre = chapitre,
                            preferences = preferences,
                            selection = lecture.selection,
                            onVerset = { n ->
                                // Désigner un verset entre en mode sélection,
                                // ou l'étend. Deux vibrations distinctes : le
                                // système réserve `LongPress` à l'entrée dans un
                                // mode, et `TextHandleMove` au déplacement d'une
                                // poignée de sélection de texte — ce qu'étendre
                                // la sélection est exactement.
                                //
                                // Les distinguer permet de savoir, sans
                                // regarder, si l'on vient d'ouvrir la barre ou
                                // d'ajouter un verset de plus.
                                haptique.performHapticFeedback(
                                    if (lecture.selection.isEmpty()) {
                                        HapticFeedbackType.LongPress
                                    } else {
                                        HapticFeedbackType.TextHandleMove
                                    },
                                )
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
                        if (unite == null) {
                            // Toucher un livre montre **ses unités**, il ne
                            // saute pas à la première. C'était le manque :
                            // aucun chemin vers un autre chapitre depuis le
                            // sommaire.
                            ecran = Ecran.Selecteur(livre)
                        } else {
                            lecture.ouvrir(livre, unite)
                            ecran = Ecran.Lecture
                        }
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
    }

    if (reglagesOuverts) {
        ModalBottomSheet(
            onDismissRequest = { reglagesOuverts = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = ONTColors.background(theme),
        ) {
            ReadingSettingsSheet(
                chapitre = lecture.chapitre,
                preferences = preferences,
                onChange = onPreferences,
            )
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

/**
 * Les couleurs des entrées de navigation, quelle que soit la forme.
 *
 * `NavigationSuiteScaffold` rend une barre, un rail ou un tiroir selon la
 * largeur, et chacun a son propre jeu de couleurs. Les poser une fois ici
 * garantit que le rail d'une tablette ressemble à la barre d'un téléphone —
 * sans quoi la même app aurait deux peaux selon l'appareil.
 *
 * La capsule reste teintée sur fond clair et pleine sur fond sombre, pour la
 * raison mesurée ailleurs : sur la nuit, l'icône et la capsule sont la même
 * couleur, et aucune opacité ne les distingue toutes les deux.
 */
@Composable
private fun suiteCouleurs(theme: ReadingTheme): NavigationSuiteItemColors {
    val capsule = if (theme.isDark) {
        ONTColors.brandInk(theme)
    } else {
        ONTColors.accent(theme).copy(alpha = 0.28f)
    }
    val icone = if (theme.isDark) ONTColors.onBrand(theme) else ONTColors.brandInk(theme)
    return NavigationSuiteDefaults.itemColors(
        navigationBarItemColors = NavigationBarItemDefaults.colors(
            selectedIconColor = icone,
            selectedTextColor = ONTColors.brandInk(theme),
            indicatorColor = capsule,
            unselectedIconColor = ONTColors.inkSoft(theme),
            unselectedTextColor = ONTColors.inkSoft(theme),
        ),
        navigationRailItemColors = NavigationRailItemDefaults.colors(
            selectedIconColor = icone,
            selectedTextColor = ONTColors.brandInk(theme),
            indicatorColor = capsule,
            unselectedIconColor = ONTColors.inkSoft(theme),
            unselectedTextColor = ONTColors.inkSoft(theme),
        ),
        navigationDrawerItemColors = NavigationDrawerItemDefaults.colors(
            selectedIconColor = icone,
            selectedTextColor = ONTColors.brandInk(theme),
            selectedContainerColor = capsule,
            unselectedIconColor = ONTColors.inkSoft(theme),
            unselectedTextColor = ONTColors.inkSoft(theme),
        ),
    )
}
