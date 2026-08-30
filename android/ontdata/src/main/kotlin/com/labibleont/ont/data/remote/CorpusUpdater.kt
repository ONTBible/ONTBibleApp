package com.labibleont.ont.data.remote

import android.content.Context
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

        if (remplaces > 0) enregistrerLesEmpreintes(connus)
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

    /** La date du corpus embarqué, lue du manifeste des assets. */
    internal fun dateDuBundle(): String = runCatching {
        context.assets.open("data/manifest.json").use { flux ->
            json.decodeFromString<Manifeste>(flux.readBytes().decodeToString()).genere
        }
    }.getOrDefault("")

    private fun manifestePublie(): Manifeste? = runCatching {
        lire(URL(origine + "manifeste.json"))?.let {
            json.decodeFromString<Manifeste>(it.decodeToString())
        }
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
