package com.labibleont.ont.observabilite

import android.content.Context
import com.labibleont.ont.BuildConfig
import com.labibleont.ont.kit.ports.Reporter
import io.sentry.Sentry
import io.sentry.SentryLevel
import io.sentry.android.core.SentryAndroid

/**
 * La remontée d'erreurs, et ce qu'elle refuse de dire.
 *
 * ## Pourquoi Android en avait besoin, alors que Play remonte déjà
 *
 * La Play Console montre les **plantages**, et elle les montre bien : l'AAB
 * embarque sa table de correspondance, donc les piles arrivent déobfusquées
 * sans qu'on fasse rien.
 *
 * Mais une liseuse plante rarement. Ce qu'elle fait, c'est **renoncer** — le
 * corpus publié ne se télécharge pas, un fichier du disque est illisible et on
 * retombe sur celui du paquet, une écriture de surlignage échoue. Quinze
 * `runCatching` avalent ces cas dans `ontdata`, et aucun ne laissait la moindre
 * trace : l'app continue, le lecteur voit un texte figé, et personne ne sait.
 *
 * `Reporter` existait comme port depuis le début, sans réalisation ni appelant.
 * Une interface que personne n'implémente ressemble à une décision prise.
 *
 * ## Ce qui ne sort jamais de l'appareil
 *
 * Les annotations d'un lecteur de Bible révèlent des convictions religieuses —
 * catégorie particulière au sens de l'article 9 du RGPD. Le texte d'une note,
 * le contenu d'un verset et la liste des passages surlignés ne doivent jamais
 * partir par ce canal.
 *
 * D'où les refus explicites plus bas : ni capture d'écran, ni hiérarchie de
 * vues, ni identifiant, ni rejeu de session. Un film du parcours de lecture
 * serait exactement la donnée qu'on s'engage à ne pas faire sortir.
 */
public object Observabilite {

    /**
     * Démarre Sentry, ou ne fait rien.
     *
     * Le DSN vit dans les ressources plutôt que dans un secret : ce n'est pas
     * une clé, c'est une adresse d'envoi, et elle voyage dans chaque copie de
     * l'app. Le garder « secret » donnerait l'illusion d'une protection que le
     * paquet livré dément.
     */
    public fun demarrer(contexte: Context, dsn: String) {
        if (dsn.isBlank() || dsn.contains("à-remplir")) return

        SentryAndroid.init(contexte) { options ->
            options.dsn = dsn
            options.environment = if (BuildConfig.DEBUG) "debug" else "release"
            options.isDebug = BuildConfig.DEBUG
            options.isAttachStacktrace = true

            // ── Ce qu'on capture ──────────────────────────────────────────
            //
            // Un blocage assez long pour être tué par le système commence par
            // un blocage plus court. Le capturer donne la pile **avant** la
            // mort — ce qu'un ANR remonté par Play ne donne pas toujours.
            options.isAnrEnabled = true
            options.anrTimeoutIntervalMillis = 3_000

            options.tracesSampleRate = if (BuildConfig.DEBUG) 1.0 else 0.2

            // ── Ce qu'on refuse ───────────────────────────────────────────
            //
            // Une capture d'écran à l'erreur montrerait le passage lu et les
            // surlignages posés dessus. C'est précisément la donnée que l'app
            // s'engage à ne pas faire sortir sans consentement.
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false

            // Ni adresse IP ni identifiant de lecteur.
            options.isSendDefaultPii = false

            // Le rejeu de session filmerait le parcours de lecture.
            options.sessionReplay.onErrorSampleRate = 0.0
            options.sessionReplay.sessionSampleRate = 0.0

            // Dernier filet : même expurgé à l'appel, un message peut porter
            // une valeur qu'on n'avait pas prévue. On repasse dessus ici,
            // parce que ce point est le seul que rien ne contourne.
            options.setBeforeSend { evenement, _ ->
                evenement.message?.let { it.formatted = it.formatted?.let(::expurger) }
                evenement.throwable?.let { evenement.setTag("expurge", "oui") }
                evenement
            }
        }
    }

    /**
     * Ce qu'on retire d'une chaîne de diagnostic.
     *
     * **Volontairement grossier** : sur-expurger coûte un diagnostic moins
     * précis, laisser fuir le titre d'une note coûte beaucoup plus.
     *
     * Deux règles, et la seconde a une nuance qu'iOS a payée pour trouver.
     */
    public fun expurger(texte: String): String {
        // 1. Les chemins **absolus** seuls.
        //
        // Un chemin relatif comme `data/corpus.json` nomme une ressource de
        // notre propre paquet : il ne révèle rien, et c'est souvent la seule
        // information utile du message. L'expurger transformait « ressource
        // introuvable : data/corpus.json » en « … : <chemin> » — un diagnostic
        // sans diagnostic.
        val sansChemins = texte.split(" ").joinToString(" ") { jeton ->
            val absolu = jeton.startsWith("/") || jeton.startsWith("file://") ||
                jeton.contains("/data/user/") || jeton.contains("/storage/") ||
                jeton.contains("/data/data/")
            val identifiant = IDENTIFIANT.containsMatchIn(jeton)
            if (absolu || identifiant) "<chemin>" else jeton
        }

        // 2. Le texte cité — la forme sous laquelle une note de lecteur ou un
        //    extrait de verset se retrouverait dans un message.
        //
        // Le critère est la **prose** : douze signes au moins, et une espace
        // *entre deux mots*. Une note en contient toujours ; un identifiant de
        // ressource, un lemme ou une clé, jamais.
        //
        // ## Deux pièges que le portage a révélés, et qu'iOS porte encore
        //
        // **Les guillemets français encadrent d'espaces insécables.**
        // « bereshit-1-verset-30 » en contient deux — l'une après l'ouvrant,
        // l'autre avant le fermant. Un critère « contient une espace » les
        // compte, et expurge donc une clé qui ne révèle rien. D'où le `trim`
        // sur l'intérieur avant de juger, et `\S\s\S` plutôt qu'un `\s` nu :
        // une espace **entre deux signes**, pas une espace de typographie.
        //
        // **L'apostrophe n'est pas un guillemet, en français.** La mettre parmi
        // les délimiteurs coupait la citation à « m'a » — donc la note du
        // lecteur traversait intacte, ce qui est exactement le cas qu'on
        // voulait fermer. Seuls « » et " délimitent ici.
        return sansChemins.replace(CITATION) { trouve ->
            val interieur = trouve.groupValues[1].trim()
            val prose = interieur.length >= 12 && ESPACE_ENTRE_MOTS.containsMatchIn(interieur)
            if (prose) "<texte>" else trouve.value
        }
    }

    private val IDENTIFIANT = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-")

    private val CITATION = Regex("[«\"]([^«»\"]*)[»\"]")

    private val ESPACE_ENTRE_MOTS = Regex("\\S\\s\\S")
}

/**
 * Le [Reporter] du port, réalisé par Sentry.
 *
 * Il expurge **avant** d'envoyer, et non dans un filtre au départ : le contexte
 * donné par l'appelant est la partie la plus susceptible de porter une valeur
 * de lecteur, et c'est celle qu'on veut voir propre dans le code plutôt que de
 * s'en remettre à un filtre lointain.
 */
public class SentryReporter : Reporter {

    override fun report(error: Throwable, context: String) {
        Sentry.withScope { portee ->
            portee.setTag("contexte", Observabilite.expurger(context).take(200))
            portee.level = SentryLevel.ERROR
            Sentry.captureException(error)
        }
    }

    override fun breadcrumb(message: String) {
        Sentry.addBreadcrumb(Observabilite.expurger(message))
    }
}
