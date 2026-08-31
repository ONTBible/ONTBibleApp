package com.labibleont.ont.data.remote

import android.content.Context
import com.labibleont.ont.kit.ports.Reporter
import com.labibleont.ont.kit.ports.SilentReporter
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Le corpus se met à jour sans passer par le magasin.
 *
 * ## Pourquoi ça existe
 *
 * Une correction de traduction ne devrait pas attendre une revue d'App Store ou
 * de Play. Le vault bouge tous les jours ; l'app, bien plus rarement. Sans ce
 * chemin, un lecteur reste des semaines sur un texte dont on sait qu'il est
 * corrigé.
 *
 * iOS le fait depuis toujours. Android ne le faisait pas, **et la fiche du Play
 * Store l'annonçait quand même** — la phrase avait été portée depuis la fiche
 * App Store sans vérifier qu'elle décrivait la même application.
 *
 * ## Le montage, repris d'iOS
 *
 * Le bundle porte un corpus complet : l'app fonctionne au premier lancement,
 * sans réseau, et fonctionnera toujours. **Le disque ne fait que le recouvrir,
 * fichier par fichier.** Un téléchargement raté ne casse rien — il laisse le
 * fichier précédent en place.
 *
 * Le manifeste est le seul fichier à nom fixe, et le point d'entrée. Tout le
 * reste porte son empreinte dans son nom, ce qui autorise un cache éternel :
 * `plan.4814dcb178e2.json` ne changera jamais de contenu.
 */
public class CorpusUpdater(
    private val context: Context,
    private val origine: String = "https://ontbible.com/corpus/",
    /**
     * Où partent les échecs de mise à jour.
     *
     * Muet par défaut, pour que les tests ne remontent rien.
     */
    private val rapporteur: Reporter = SilentReporter,
) {

    /**
     * Le manifeste publié.
     *
     * [genere] date le **contenu** du corpus, pas le moment de sa compilation.
     * C'est ce qui permet de comparer deux corpus sans casser le déterminisme du
     * pipeline — voir [plusRecentQueLeBundle].
     */
    @Serializable
    internal data class Manifeste(
        val schema: Int,
        val genere: String = "",
        val fichiers: Map<String, Entree> = emptyMap(),
        val livres: Map<String, Entree> = emptyMap(),
    ) {
        @Serializable
        internal data class Entree(val chemin: String, val empreinte: String, val octets: Int)

        /**
         * Tout ce qu'il désigne, sous la forme `nom local → entrée`.
         *
         * Les noms locaux sont ceux qu'attend le lecteur de disque, calqués sur
         * ceux des assets. Un nom du manifeste qu'on ne connaît pas est
         * **ignoré** : une version future peut publier des fichiers que
         * celle-ci ne saurait pas lire, et les écrire sans les comprendre ne
         * ferait qu'occuper le disque.
         */
        val tout: kotlin.collections.List<Pair<String, Entree>>
            get() {
                val noms = mapOf(
                    "plan" to "corpus.json",
                    "quotidien" to "daily.json",
                    "glossaire" to "glossary.json",
                    "occurrences" to "occurrences.json",
                    "shemot" to "shemot.json",
                )
                return fichiers.mapNotNull { (cle, e) -> noms[cle]?.let { it to e } } +
                    livres.map { (id, e) -> "books/$id.json" to e }
            }
    }

    public companion object {
        /** La version de manifeste que cette app sait lire. */
        internal const val SCHEMA: Int = 2

        /** Le dossier où le corpus téléchargé recouvre celui du bundle. */
        public fun dossierParDefaut(context: Context): File =
            File(context.filesDir, "corpus")

        /**
         * **Écarte le corpus du disque quand celui du bundle est plus récent.**
         *
         * ## Le trou que la garde de [synchroniser] laisse
         *
         * Refuser un corpus publié plus vieux empêche d'en *poser* un mauvais.
         * Ça ne fait rien à celui qui est **déjà là**. Or le disque recouvre le
         * bundle, fichier par fichier et sans condition : une copie téléchargée
         * avant la garde continue donc de gagner sur un bundle plus neuf, et
         * indéfiniment — jusqu'au jour où le site publie plus récent qu'elle.
         *
         * Constaté sur iOS, où la même correction avait été faite d'abord : la
         * 1.0.5 embarquait la couche des Shemot, et **aucun nom ne s'affichait**.
         * Le disque portait le corpus de l'avant-veille, sans un seul nœud
         * `shem`, et il répondait à sa place. La correction précédente avait
         * arrêté la cause et laissé l'effet.
         *
         * Android portait la garde de [synchroniser] sans celle-ci : il avait
         * donc hérité de la moitié du remède.
         *
         * ## Ce que la purge coûte, et pourquoi ce n'est rien
         *
         * Le corpus est **entièrement retéléchargeable**, et le bundle répond en
         * attendant : l'app n'est jamais sans texte, même une seconde. Rien de
         * ce que le lecteur a écrit ne vit ici — surlignages, notes et position
         * sont dans son propre fichier, ailleurs.
         *
         * ## Une estampille absente vaut « plus vieux »
         *
         * Toutes les installations d'aujourd'hui sont dans ce cas : un corpus
         * sur le disque et aucune estampille, puisque personne n'en écrivait.
         * Les traiter comme périmées est exact — il date forcément d'avant cette
         * version — et c'est ce qui rend la réparation automatique au premier
         * lancement.
         */
        public fun purgerSiLeBundleEstPlusNeuf(
            context: Context,
            dossier: File = dossierParDefaut(context),
        ) {
            val embarquee = CorpusUpdater(context).dateDuBundle()
            val surDisque = runCatching {
                File(dossier, "estampille.txt").readText().trim()
            }.getOrDefault("")
            if (!doitPurger(surDisque = surDisque, embarquee = embarquee)) return
            dossier.deleteRecursively()
        }

        /**
         * L'arbitrage de la purge, isolé de tout contexte.
         *
         * Comme [plusRecent], et pour la même raison : il ne dépend ni du
         * disque, ni des assets, ni de l'appareil, donc il s'éprouve tel quel.
         * Laissé dans [purgerSiLeBundleEstPlusNeuf], il aurait exigé un
         * `Context` — et une épreuve qui a besoin d'un appareil est une épreuve
         * qu'on n'écrit pas.
         *
         * ## Pourquoi ce n'est pas `!plusRecent(...)`
         *
         * [plusRecent] est **strict**, et l'égalité est ici le cas ordinaire :
         * le disque porte alors exactement le corpus du bundle. Le nier
         * purgerait à chaque lancement pour reposer les mêmes octets. **Aussi
         * récent suffit à garder.**
         *
         * Une estampille absente ou mal formée ne s'ordonne pas : elle est
         * traitée comme périmée. C'est le cas de toutes les installations
         * antérieures à cette version, et c'est ce qui rend la réparation
         * automatique au premier lancement.
         */
        /**
         * Le manifeste que le pipeline embarque dans les assets.
         *
         * Réduit à la seule clé qu'on lui demande : les autres — `vault`,
         * `stats` — ne regardent pas la liseuse. `ignoreUnknownKeys` les laisse
         * passer.
         */
        @Serializable
        internal data class ManifesteEmbarque(val generatedAt: String = "")

        /**
         * La date d'un manifeste embarqué, **depuis son texte**.
         *
         * Séparée de la lecture des assets pour qu'une épreuve puisse lui donner
         * un vrai document du pipeline. C'est tout le sujet : le défaut vivait
         * dans le décodage, et une épreuve qui part de la valeur *déjà décodée*
         * ne peut pas le voir.
         */
        internal fun dateDuManifesteEmbarque(source: String): String =
            runCatching {
                Json { ignoreUnknownKeys = true }
                    .decodeFromString<ManifesteEmbarque>(source)
                    .generatedAt
            }.getOrDefault("")

        internal fun doitPurger(surDisque: String, embarquee: String): Boolean {
            val e = embarquee.trim()
            // Un bundle indatable ne peut rien opposer : ne rien jeter vaut
            // mieux que jeter un corpus peut-être bon.
            if (!bienFormee(e)) return false
            val d = surDisque.trim()
            if (!bienFormee(d)) return true
            return d < e
        }

        /**
         * L'arbitrage, isolé de tout contexte.
         *
         * Il ne dépend ni du réseau, ni des assets, ni de l'appareil — donc il
         * s'éprouve tel quel. C'était l'inverse qui posait problème sur iOS :
         * les premiers cas de refus **passaient sans la garde**, parce que leurs
         * manifestes ne listaient aucun fichier et que « zéro téléchargement »
         * était le résultat attendu de toute façon. Un instrument dont la panne
         * ressemble au résultat.
         *
         * ## Ce qu'on ne consulte jamais
         *
         * L'horloge de l'appareil. Un téléphone qui se croit en 2019 — et il y
         * en a, le lecteur règle sa date lui-même — refuserait tout corpus comme
         * venant du futur, et son texte se figerait sans que rien ne l'explique.
         * On ne compare que deux valeurs de la même chaîne.
         */
        internal fun plusRecent(publiee: String, embarquee: String): Boolean {
            val p = publiee.trim()
            // Une forme voisine est traitée comme absente : elle s'ordonne
            // n'importe comment contre la forme stricte, et se tromper dans ce
            // sens-là est ce qui a produit le défaut.
            if (!bienFormee(p)) return false
            val e = embarquee.trim()
            // Un bundle sans date ne peut rien opposer. La refuser priverait ses
            // lecteurs de toute mise à jour, pour toujours.
            if (!bienFormee(e)) return true
            // La forme étant fixe, l'ordre lexicographique est l'ordre du temps.
            return p > e
        }

        /** `2026-08-30T22:45:48Z` — vingt signes, UTC, secondes obligatoires. */
        private fun bienFormee(s: String): Boolean =
            s.length == 20 &&
                s[4] == '-' && s[7] == '-' && s[10] == 'T' &&
                s[13] == ':' && s[16] == ':' && s[19] == 'Z' &&
                intArrayOf(0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18)
                    .all { s[it].isDigit() }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val dossier = dossierParDefaut(context)
    private val registre get() = File(dossier, "empreintes.json")

    /**
     * L'estampille du corpus **posé sur le disque**.
     *
     * À côté de lui, et pas dans le registre d'empreintes : celui-ci dit *quels
     * fichiers* on tient, celle-là dit *de quand ils datent*. Deux questions,
     * deux fichiers — les mêler ferait qu'une réponse partielle à l'une abîmerait
     * l'autre.
     */
    private val estampilleDuDisque get() = File(dossier, "estampille.txt")

    /**
     * Synchronise, et rend le nombre de fichiers remplacés.
     *
     * Zéro veut dire « rien de neuf », ce qui est le cas ordinaire. Une panne de
     * réseau n'est pas une erreur : l'app lit ce qu'elle a.
     */
    public fun synchroniser(): Int {
        val manifeste = manifestePublie() ?: return 0
        if (manifeste.schema != SCHEMA) return 0
        if (!plusRecentQueLeBundle(manifeste)) return 0

        dossier.mkdirs()
        val connus = empreintesConnues().toMutableMap()
        var remplaces = 0

        for ((local, entree) in manifeste.tout) {
            if (connus[local] == entree.empreinte) continue
            val octets = telecharger(entree) ?: continue
            if (!ecrire(octets, local)) continue
            // L'empreinte n'est notée que pour ce qui vient **réellement** d'être
            // écrit. Noter tout le manifeste dès qu'un fichier passe déclarerait
            // à jour un téléchargement raté, qui ne serait jamais retenté — la
            // correction qu'il portait n'arriverait qu'au prochain changement de
            // ce livre-là, c'est-à-dire peut-être jamais.
            connus[local] = entree.empreinte
            remplaces++
        }

        if (remplaces > 0) {
            // Après les fichiers, comme le registre et pour la même raison : une
            // estampille écrite d'avance promettrait un corpus qu'une coupure
            // aurait laissé à moitié posé.
            runCatching { estampilleDuDisque.writeText(manifeste.genere) }
            enregistrerLesEmpreintes(connus)
        }
        return remplaces
    }

    /**
     * Le corpus publié est-il plus récent que celui du bundle ?
     *
     * ## Le défaut que cette garde ferme
     *
     * Sans elle, le disque gagne **toujours**. Une build neuve, embarquant un
     * corpus neuf, se fait donc écraser au premier lancement par le corpus
     * publié — qui est plus ancien tant que le site n'a pas republié.
     *
     * Trouvé sur iOS : une build portant 1 913 Shemot en affichait 217, ceux du
     * corpus publié. La fonctionnalité arrivait **invisible**, et aucun test ne
     * pouvait l'attraper — ils mesurent tous le corpus du bundle, que personne
     * ne lit.
     *
     * ## Pourquoi une date, et laquelle
     *
     * Une empreinte dit que deux corpus **diffèrent**, jamais lequel vient
     * après. Il faut donc un ordre, et `genere` le porte.
     *
     * C'est la date du **contenu** — l'état du vault — et non celle de la
     * compilation. La distinction n'est pas cosmétique : le pipeline garantit
     * que deux exécutions sur le même vault produisent le même octet, donc la
     * même empreinte, donc aucun retéléchargement inutile. Un horodatage de
     * build romprait cette garantie et republierait tout le corpus à chaque
     * passage de CI.
     *
     * ## Un manifeste sans date est refusé
     *
     * On ne peut pas prouver qu'il est plus récent, et se tromper dans ce
     * sens-là est exactement ce qui a produit le défaut. Un corpus qui ne se met
     * pas à jour est visible et réparable ; un corpus silencieusement remplacé
     * par du plus vieux ne l'est pas.
     */
    internal fun plusRecentQueLeBundle(manifeste: Manifeste): Boolean =
        plusRecent(publiee = manifeste.genere, embarquee = dateDuBundle())

    /**
     * La date du corpus embarqué, lue du manifeste des assets.
     *
     * ## Deux manifestes, deux documents
     *
     * Celui du bundle est écrit par le pipeline et porte `generatedAt`, `vault`
     * et les statistiques du build. Celui du site est écrit par
     * `corpus-publie.py` et porte `genere`, `fichiers` et `livres`. **Ils ne se
     * ressemblent que de loin**, et la même date n'y a pas le même nom.
     *
     * Les décoder avec la même classe compilait, passait les épreuves, et
     * rendait la chaîne vide sur le manifeste du bundle — kotlinx cherchait
     * `genere`, ne le trouvait pas, et prenait la valeur par défaut. La garde
     * entière tombait alors : `plusRecent` traite un bundle indatable comme
     * n'ayant rien à opposer, donc **acceptait tout**.
     *
     * Le défaut ne se voyait nulle part. Les épreuves nourrissaient la sortie de
     * cette fonction, jamais son entrée.
     */
    internal fun dateDuBundle(): String = runCatching {
        context.assets.open("data/manifest.json").use { flux ->
            dateDuManifesteEmbarque(flux.readBytes().decodeToString())
        }
    }.getOrDefault("")

    private fun manifestePublie(): Manifeste? = runCatching {
        lire(URL(origine + "manifeste.json"))?.let {
            json.decodeFromString<Manifeste>(it.decodeToString())
        }
    }.onFailure {
        // Un manifeste illisible arrête **toute** mise à jour : le lecteur
        // reste sur le corpus du paquet, indéfiniment, et l'app ne montre
        // aucun signe. C'est la panne la plus silencieuse de la chaîne.
        //
        // Une panne de réseau, elle, ne passe pas ici : `lire` rend `null`
        // sans lever. Ce qui arrive jusque-là est un manifeste qu'on a reçu
        // et qu'on n'a pas su lire — donc un vrai défaut, pas un tunnel.
        rapporteur.report(it, "lecture du manifeste publié")
    }.getOrNull()

    private fun telecharger(entree: Manifeste.Entree): ByteArray? =
        runCatching { lire(URL(origine + entree.chemin)) }.getOrNull()

    private fun lire(url: URL): ByteArray? {
        val c = url.openConnection() as HttpURLConnection
        return try {
            c.connectTimeout = 15_000
            c.readTimeout = 30_000
            if (c.responseCode != 200) null else c.inputStream.use { it.readBytes() }
        } catch (_: Exception) {
            null
        } finally {
            c.disconnect()
        }
    }

    private fun ecrire(octets: ByteArray, local: String): Boolean = runCatching {
        val cible = File(dossier, local)
        cible.parentFile?.mkdirs()
        // Par un fichier provisoire : un `write` interrompu — batterie, mise à
        // mort par le système — laisserait sinon un JSON tronqué que l'app lirait
        // au lancement suivant, et qui gagnerait sur le bundle intact.
        val provisoire = File(cible.parentFile, "${cible.name}.tmp")
        provisoire.writeBytes(octets)
        provisoire.renameTo(cible)
    }.onFailure {
        // Le fichier est arrivé et n'a pas pu être posé — disque plein,
        // permission, interruption. L'empreinte n'est donc pas notée et on
        // réessaiera, mais si la cause persiste on réessaiera pour toujours,
        // en silence.
        rapporteur.report(it, "écriture du corpus téléchargé : $local")
    }.getOrDefault(false)

    private fun empreintesConnues(): Map<String, String> = runCatching {
        json.decodeFromString<Map<String, String>>(registre.readText())
    }.getOrDefault(emptyMap())

    private fun enregistrerLesEmpreintes(table: Map<String, String>) {
        // Écrit **après** les fichiers, délibérément. Dans l'autre ordre, une
        // interruption laisserait un registre qui déclare à jour des fichiers
        // jamais écrits — et l'app ne les redemanderait plus.
        runCatching { registre.writeText(json.encodeToString(table)) }
    }
}
