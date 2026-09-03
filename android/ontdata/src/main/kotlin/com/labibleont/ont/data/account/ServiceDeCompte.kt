package com.labibleont.ont.data.account

import com.labibleont.ont.kit.account.EchecDeConnexion
import com.labibleont.ont.kit.account.Fournisseur
import com.labibleont.ont.kit.account.Session
import com.labibleont.ont.kit.ports.AccountRepository
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Ce que le backend rend à la connexion.
 *
 * ## Les `@SerialName` ne sont pas décoratifs
 *
 * Le backend écrit en `snake_case` **littéral**, sans aucun `rename` — le
 * `CLAUDE.md` de la racine en fait un contrat entre les clients. Sans ces
 * annotations, kotlinx.serialization chercherait `jetonDAcces` et lèverait sur
 * un champ manquant : la connexion échouerait, et le message parlerait de
 * sérialisation plutôt que d'authentification.
 *
 * iOS s'en tire autrement — `convertFromSnakeCase` sur son décodeur partagé —
 * ce qui veut dire que **le contrat n'est écrit nulle part dans un type**. Ici
 * il l'est, et c'est le seul endroit des deux plateformes où le compilateur en
 * garde une trace.
 */
@Serializable
internal data class SessionDto(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Long,
    val created: Boolean = false,
)

@Serializable
internal data class DemandeDeConnexion(
    val code: String,
    @SerialName("redirect_uri") val redirectUri: String,
    @SerialName("code_verifier") val codeVerifier: String?,
)

@Serializable
internal data class DemandeDeRafraichissement(
    @SerialName("refresh_token") val refreshToken: String,
)

/**
 * Une erreur qu'on peut montrer au lecteur.
 *
 * `motif` et non `cause` : `Throwable` a déjà un `cause`, qui désigne l'erreur
 * sous-jacente. Réemployer le mot ferait dire deux choses au même nom.
 */
public class ErreurDeCompte(public val motif: EchecDeConnexion) : Exception(motif.toString())

/**
 * Le compte, contre le backend.
 *
 * `HttpURLConnection` comme l'actualiseur de corpus : une seule façon de parler
 * au réseau dans ce module, et aucune dépendance de plus pour trois requêtes.
 */
public class ServiceDeCompte(
    private val racine: String,
    private val coffre: CoffreDeJetons,
    private val horloge: () -> Long = System::currentTimeMillis,
) : AccountRepository {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    override fun session(): Session? = coffre.lire()

    override suspend fun ouvrir(
        fournisseur: Fournisseur,
        code: String,
        adresseDeRetour: String,
        verificateur: String,
    ): Session {
        val corps = json.encodeToString(
            DemandeDeConnexion(code, adresseDeRetour, verificateur),
        )
        val dto = poster("/auth/${fournisseur.cle}", corps)
            ?: throw ErreurDeCompte(EchecDeConnexion.Refusee)
        return dto.versDomaine(horloge()).also(coffre::ecrire)
    }

    override suspend fun rafraichir(): Session? {
        val actuelle = coffre.lire() ?: return null
        val corps = json.encodeToString(
            DemandeDeRafraichissement(actuelle.jetonDeRafraichissement),
        )
        val dto = poster("/auth/refresh", corps)
        if (dto == null) {
            // Le jeton long lui-même n'est plus bon : garder les anciens
            // jetons ferait boucler chaque requête sur un rafraîchissement qui
            // échoue. On oublie, et le lecteur se reconnecte une fois.
            coffre.effacer()
            return null
        }
        return dto.versDomaine(horloge()).also(coffre::ecrire)
    }

    override fun fermer(): Unit = coffre.effacer()

    private fun poster(chemin: String, corps: String): SessionDto? = runCatching {
        val connexion = (URL(racine + chemin).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 30_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
        }
        try {
            connexion.outputStream.use { it.write(corps.toByteArray()) }
            if (connexion.responseCode != 200) return@runCatching null
            val texte = connexion.inputStream.use { it.readBytes().decodeToString() }
            json.decodeFromString<SessionDto>(texte)
        } finally {
            connexion.disconnect()
        }
    }.getOrNull()
}

/**
 * La durée reçue devient un instant, une fois pour toutes.
 *
 * Le backend rend `expires_in` en **secondes** ; tout le reste du projet compte
 * en millisecondes. La conversion vit ici plutôt qu'au point d'appel : écrite
 * deux fois, elle finirait par manquer d'un facteur mille quelque part, et le
 * jeton serait tenu pour expiré à la seconde ou valide pour un an.
 */
internal fun SessionDto.versDomaine(maintenant: Long): Session = Session(
    jetonDAcces = accessToken,
    jetonDeRafraichissement = refreshToken,
    expiration = maintenant + expiresIn * 1_000,
    creation = created,
)
