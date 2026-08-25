package com.labibleont.ont.data

import com.labibleont.ont.data.store.FileReaderStore
import com.labibleont.ont.kit.reader.DailyVerseSchedule
import com.labibleont.ont.kit.reader.Highlight
import com.labibleont.ont.kit.reader.HighlightColor
import com.labibleont.ont.kit.reader.ReadingFont
import com.labibleont.ont.kit.reader.ReadingPosition
import com.labibleont.ont.kit.reader.ReadingPreferences
import com.labibleont.ont.kit.reader.ReadingTheme
import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Écrire, fermer, rouvrir, comparer.
 *
 * ## Pourquoi ce test existe, et pourquoi il n'a pas suffi d'un test de mappage
 *
 * Le 25 août 2026, « Le français reçu » manquait à `PreferencesFichier`. Le
 * réglage se basculait, l'écran suivait — et il **disparaissait à la
 * fermeture**. Rien ne le voyait : ni la compilation, ni l'écran, ni les tests.
 *
 * `PreferencesFichierTest` garde le mappage domaine ↔ DTO, et il aurait attrapé
 * ce cas-là. Mais il ne traverse pas le disque : un champ présent dans le DTO et
 * perdu à la sérialisation — `@Transient`, un encodeur qui l'omet, l'écriture
 * atomique qui échoue en silence — repasserait devant lui.
 *
 * Ici c'est **le vrai magasin, le vrai fichier, la vraie sérialisation**. Ce que
 * ce test appelle « rouvrir » est une seconde instance : le magasin lit tout à
 * la construction, donc en construire une autre sur le même fichier est
 * exactement ce que fait un lancement d'app.
 *
 * Le magasin prend un `File` et non un `Context` pour que ceci tourne sur la
 * JVM — c'est la dépendance réelle de l'adaptateur, le `Context` n'était que la
 * façon dont Android la lui fournissait.
 */
class FermerEtRouvrirTest {

    private lateinit var dossier: File
    private lateinit var fichier: File

    @Before
    fun preparer() {
        dossier = Files.createTempDirectory("ont-magasin").toFile()
        fichier = File(dossier, "lecteur.json")
    }

    @After
    fun ranger() {
        dossier.deleteRecursively()
    }

    /** Chaque réglage, sur des valeurs toutes différentes du défaut. */
    @Test
    fun `les réglages survivent à la fermeture`() {
        val voulu = ReadingPreferences(
            showGloss = false,
            showLevel3 = false,
            textSize = 31.0,
            lineSpacing = 0.9,
            theme = ReadingTheme.MYSTIQUE,
            bodyFont = ReadingFont.SPECTRAL,
            continuous = false,
            french = false,
            daily = DailyVerseSchedule.borne(true, 21, 15),
        )
        FileReaderStore(fichier).preferences = voulu

        assertEquals(voulu, FileReaderStore(fichier).preferences)
    }

    /**
     * Le cas exact du 25 août, et le seul que l'écran montrait : basculer un
     * réglage **seul**, tout le reste au défaut.
     */
    @Test
    fun `basculer le seul français reçu tient à la réouverture`() {
        val magasin = FileReaderStore(fichier)
        magasin.preferences = magasin.preferences.copy(french = false)

        assertEquals(false, FileReaderStore(fichier).preferences.french)
        assertTrue(
            "Le réglage doit être écrit sur le disque, pas seulement en mémoire.",
            fichier.readText().contains("\"french\":false"),
        )
    }

    /** Les annotations du lecteur traversent aussi — c'est ce qu'il perdrait. */
    @Test
    fun `un surlignage et sa note survivent à la fermeture`() {
        val marque = Highlight(
            id = "h1",
            bookId = "bereshit",
            chapterId = "bereshit-1",
            verse = 3,
            color = HighlightColor.GOLD,
            note = "la première parole",
        )
        FileReaderStore(fichier).save(marque)

        val relu = FileReaderStore(fichier).highlight("bereshit-1", 3)
        assertEquals("la première parole", relu?.note)
        assertEquals(HighlightColor.GOLD, relu?.color)
    }

    /**
     * La position de reprise — ce que le lecteur voit en rouvrant l'app.
     *
     * La date **perd ses sous-millisecondes**, et c'est voulu : le fichier range
     * les instants en millisecondes depuis 1970, un entier que le backend Rust
     * lit sans négocier de format. Ce test le constate au lieu de l'ignorer —
     * une troncature choisie doit être écrite quelque part, sinon le jour où
     * elle changera personne ne saura si c'était un contrat ou un accident.
     */
    @Test
    fun `la position de reprise survit à la fermeture, à la milliseconde`() {
        val ou = ReadingPosition(
            bookId = "bereshit",
            chapterId = "bereshit-1",
            chapterTitle = "Parashah 1",
            verse = 12,
            date = Instant.ofEpochMilli(1_756_108_800_123L),
        )
        FileReaderStore(fichier).remember(ou)

        assertEquals(ou, FileReaderStore(fichier).position)
    }

    /** La troncature elle-même, nommée. */
    @Test
    fun `les instants sont rangés à la milliseconde`() {
        val precis = Instant.ofEpochSecond(1_756_108_800L, 123_456_789L)
        FileReaderStore(fichier).remember(
            ReadingPosition("b", "b-1", "Parashah 1", 1, date = precis),
        )

        assertEquals(
            "l'instant relu est le précédent tronqué à la milliseconde",
            Instant.ofEpochMilli(precis.toEpochMilli()),
            FileReaderStore(fichier).position?.date,
        )
    }

    /**
     * Un fichier écrit par une version **antérieure** doit se relire.
     *
     * C'est la situation de tout lecteur qui met l'app à jour : son fichier ne
     * connaît pas le réglage qu'on vient d'ajouter. Il doit prendre le défaut,
     * pas faire perdre le reste.
     */
    @Test
    fun `un fichier d'avant se relit sans rien perdre`() {
        fichier.writeText(
            """
            {"highlights":[],"position":null,"preferences":{
              "showGloss":false,"showLevel3":true,"textSize":23.0,"lineSpacing":0.5,
              "theme":"dark","bodyFont":"literata","continuous":false,
              "dailyEnabled":false,"dailyHour":7,"dailyMinute":30}}
            """.trimIndent(),
        )

        val relu = FileReaderStore(fichier).preferences
        assertEquals("le défaut prend la place de la clé absente", true, relu.french)
        assertEquals("et le reste du fichier est conservé", 23.0, relu.textSize, 0.0)
        assertEquals(false, relu.continuous)
        assertEquals(ReadingTheme.DARK, relu.theme)
    }

    /**
     * Le **conteneur** doit être tolérant, pas seulement ses feuilles.
     *
     * Le piège se cache un cran au-dessus de celui qu'on regarde d'habitude :
     * on soigne le décodage de chaque réglage, et on oublie que l'objet qui les
     * contient peut refuser de se décoder en entier. Une clé manquante à ce
     * niveau-là ne coûte pas un réglage — elle coûte **tous les surlignages du
     * lecteur**, en silence, à la première ouverture de la nouvelle version.
     *
     * Ici la tolérance vient des valeurs par défaut du constructeur d'`Etat` :
     * kotlinx.serialization s'en sert quand la clé manque. Ce test est ce qui
     * garantit qu'elles y restent — les retirer compile encore.
     */
    @Test
    fun `un fichier sans la clé des réglages garde ses surlignages`() {
        fichier.writeText(
            """
            {"highlights":[{"id":"h1","bookId":"bereshit","chapterId":"bereshit-1",
              "verse":3,"color":"gold","note":"la première parole",
              "updatedAt":1756108800123,"deleted":false}],"position":null}
            """.trimIndent(),
        )

        val magasin = FileReaderStore(fichier)
        assertEquals(
            "la clé absente ne doit pas emporter les annotations",
            "la première parole",
            magasin.highlight("bereshit-1", 3)?.note,
        )
        assertEquals("et les réglages prennent leur défaut", true, magasin.preferences.french)
    }

    /**
     * Une clé **inconnue** est ignorée, pas fatale.
     *
     * C'est le fichier écrit par une version plus récente : celui de qui
     * rétrograde, ou restaure une sauvegarde faite depuis un autre appareil.
     */
    @Test
    fun `une clé inconnue ne fait rien perdre`() {
        fichier.writeText(
            """
            {"highlights":[],"position":null,"venuDuFutur":{"quoi":"on ne sait pas"},
             "preferences":{"french":false,"textSize":25.0,"ceciNonPlus":7}}
            """.trimIndent(),
        )

        val relu = FileReaderStore(fichier).preferences
        assertEquals(false, relu.french)
        assertEquals(25.0, relu.textSize, 0.0)
    }

    /**
     * Un fichier illisible est **mis de côté**, pas écrasé.
     *
     * C'est la moitié du problème que la tolérance du conteneur ne règle pas :
     * un JSON tronqué par une écriture interrompue, une sauvegarde abîmée. On
     * repart à vide — c'est le bon comportement —, mais la première écriture qui
     * suit détruirait ce qu'on n'a pas su lire.
     *
     * Un JSON tronqué garde presque toujours l'essentiel de ce qui était annoté.
     */
    @Test
    fun `un fichier illisible est mis de côté au lieu d'être écrasé`() {
        val tronque = """{"highlights":[{"id":"h1","note":"la première par"""
        fichier.writeText(tronque)

        val magasin = FileReaderStore(fichier)
        assertEquals("on repart à vide, comme avant", 0, magasin.all().size)

        // et l'écriture qui suit ne doit pas emporter l'original
        magasin.preferences = magasin.preferences.copy(french = false)

        val misDeCote = File(dossier, "lecteur.illisible.json")
        assertTrue("le fichier illisible doit être conservé", misDeCote.exists())
        assertEquals(
            "et conservé tel quel, pour qu'on puisse en tirer quelque chose",
            tronque,
            misDeCote.readText(),
        )
    }
}
