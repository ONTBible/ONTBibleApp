package com.labibleont.ont.features.you

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.labibleont.ont.designsystem.metrics.ONTRadius
import com.labibleont.ont.designsystem.metrics.ontSpacing
import com.labibleont.ont.designsystem.surfaces.ONTGroup
import com.labibleont.ont.designsystem.surfaces.ONTGroupDivider
import com.labibleont.ont.designsystem.surfaces.ONTLargeTitle
import com.labibleont.ont.designsystem.surfaces.ONTPage
import com.labibleont.ont.designsystem.surfaces.ONTRow
import com.labibleont.ont.designsystem.surfaces.ONTSectionHeader
import com.labibleont.ont.designsystem.theme.LocalReadingTheme
import com.labibleont.ont.designsystem.tokens.ONTColors
import com.labibleont.ont.kit.corpus.LibelleDUnite
import com.labibleont.ont.kit.reader.ReadingPreferences

/** Ce vers quoi une ligne de l'onglet Vous conduit. */
public enum class DestinationVous {
    LECTURE,
    VERSET_DU_JOUR,
    PARUTIONS,

    /** Le catalogue du design system — en développement seulement. */
    CATALOGUE,
}

/**
 * L'onglet Vous — un **hall**, pas un déversoir de réglages.
 *
 * ## Pourquoi des sous-écrans et non une page unique
 *
 * La première version d'Android empilait tout : niveaux, taille, thème, fonte,
 * rappel. C'était lisible et ça ne ressemblait à rien — une colonne
 * d'interrupteurs séparés par des traits pleine largeur.
 *
 * iOS en fait un sommaire : quelques groupes encartés, chaque ligne menant à un
 * écran qui ne traite qu'une chose. Ce n'est pas une préférence esthétique.
 * C'est ce qui permet à l'écran du **verset du jour** d'exister séparément de
 * celui des **parutions** — la distinction que la PR #74 a établie côté iOS, et
 * qu'une page unique aurait effacée.
 *
 * On reprend donc la structure. Ce qui change, ce sont les gestes : le retour
 * système ferme un sous-écran, et les lignes suivent la cible tactile
 * d'Android.
 */
@Composable
public fun YouTab(
    preferences: ReadingPreferences,
    slotsRediges: Int,
    slotsTotal: Int,
    versets: Int,
    /**
     * Le nombre d'entrées du lexique.
     *
     * Il vaut zéro tant que le lexique n'a pas été chargé — c'est pourquoi
     * l'écran des onglets le charge aussi en arrivant ici, et pas seulement en
     * ouvrant l'onglet Lexique. Un compteur qui affiche zéro parce que la
     * donnée n'est pas venue ne se distingue pas d'un corpus vide.
     */
    entreesDeLexique: Int,
    /**
     * Le fournisseur de la session ouverte, ou `null` si personne ne l'est.
     *
     * Une chaîne et non un type du domaine : cet écran n'a pas à connaître
     * l'énumération des fournisseurs pour afficher un mot.
     */
    fournisseurConnecte: String?,
    onAller: (DestinationVous) -> Unit,
    onConnecter: (String) -> Unit,
    onDeconnecter: () -> Unit,
    onPasEncore: () -> Unit,
    /**
     * Vrai en build de développement.
     *
     * Le catalogue n'a rien à faire dans une app livrée : il ne sert qu'à
     * repérer une dérive de style avant qu'elle n'atteigne un écran de lecture.
     */
    enDeveloppement: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val theme = LocalReadingTheme.current
    val espace = ontSpacing

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
    ) {
        ONTPage {
            ONTLargeTitle("Vous")

            ONTSectionHeader("Compte")
            ONTGroup {
                Column(
                    modifier = Modifier.padding(espace.m),
                    verticalArrangement = Arrangement.spacedBy(espace.s),
                ) {
                    if (fournisseurConnecte == null) {
                        BoutonDeConnexion("Continuer avec Google") { onConnecter("google") }
                        BoutonDeConnexion("Continuer avec GitHub") { onConnecter("github") }
                    } else {
                        // ## Ce qu'on montre d'un compte ouvert
                        //
                        // Le fournisseur, et rien d'autre. Le backend ne rend
                        // que des jetons à la connexion — pas d'adresse — et
                        // aller la chercher demanderait une route de plus pour
                        // afficher une ligne. iOS la montre parce qu'Apple la
                        // lui donne au passage.
                        Text(
                            "Connecté avec " + when (fournisseurConnecte) {
                                "google" -> "Google"
                                "github" -> "GitHub"
                                else -> fournisseurConnecte
                            },
                            color = ONTColors.ink(theme),
                            fontSize = 15.sp,
                        )
                        BoutonDeConnexion("Se déconnecter") { onDeconnecter() }
                    }
                }
            }
            Text(
                // Le dire avant qu'on se demande : rien n'oblige à créer un
                // compte. C'est une propriété de l'app, pas une concession.
                if (fournisseurConnecte == null) {
                    "La lecture, les surlignages et les notes fonctionnent " +
                        "entièrement sans compte. La connexion ne sert qu'à les " +
                        "retrouver sur un autre appareil."
                } else {
                    "Vos marques restent sur cet appareil. Se déconnecter ne les " +
                        "efface pas."
                },
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(
                    start = espace.l,
                    end = espace.l,
                    top = espace.s,
                ),
            )

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Notifications")
            ONTGroup {
                ONTRow(
                    titre = "Verset du jour",
                    detail = if (preferences.daily.enabled) {
                        "à %02d:%02d".format(preferences.daily.hour, preferences.daily.minute)
                    } else {
                        "éteint"
                    },
                    icone = Icons.Filled.WbTwilight,
                    onClick = { onAller(DestinationVous.VERSET_DU_JOUR) },
                    fin = { Chevron() },
                )
                ONTGroupDivider()
                ONTRow(
                    titre = "Parutions",
                    detail = "quand un livre paraît",
                    icone = Icons.AutoMirrored.Filled.MenuBook,
                    onClick = { onAller(DestinationVous.PARUTIONS) },
                    fin = { Chevron() },
                )
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Lecture")
            ONTGroup {
                ONTRow(
                    titre = "Réglages de lecture",
                    detail = "niveaux, taille, thème, fonte",
                    icone = Icons.Filled.FormatSize,
                    onClick = { onAller(DestinationVous.LECTURE) },
                    fin = { Chevron() },
                )
            }

            Spacer(Modifier.height(espace.xl))

            ONTSectionHeader("Le corpus")
            ONTGroup {
                ONTRow(titre = "Slots rédigés", fin = { Valeur("$slotsRediges / $slotsTotal") })
                ONTGroupDivider()
                ONTRow(titre = "Versets", fin = { Valeur("$versets") })
                ONTGroupDivider()
                ONTRow(titre = "Entrées de lexique", fin = { Valeur("$entreesDeLexique") })
            }

            // ## Le pied qui dit pourquoi les chiffres sont bas
            //
            // Sans lui, « 4 / 70 » se lit comme un manque. Avec lui, comme un
            // chantier — ce qu'il est. iOS le porte depuis toujours ; Android
            // affichait les mêmes chiffres nus.
            //
            // Et le mot suit le registre : « chapitres » ou « parashiot ». Le
            // pluriel de *parashah* prend la marque hébraïque, pas le `s`
            // français — franciser l'intraduisible ici défferait exactement ce
            // que le réglage vient de faire.
            Text(
                "La Bible ONT est une restitution en cours. Le corpus s'étend " +
                    "à mesure que les ${LibelleDUnite.noms(preferences.french)} " +
                    "sont verrouillés.",
                color = ONTColors.inkSoft(theme),
                fontSize = 13.sp,
                modifier = Modifier.padding(
                    start = espace.l,
                    end = espace.l,
                    top = espace.s,
                ),
            )

            // ## Les crédits, que l'app taisait
            //
            // C'est le seul écran où le crédit paraît, donc le seul endroit où
            // la confusion des noms se verrait : **Gloire Bikouta** en public,
            // jamais « Sha'eliel », qui est le nom interne au vault.
            //
            // Et les deux licences de fontes ne sont pas une politesse : Ezra
            // SIL et Frank Ruhl Libre sont sous OFL, qui **exige** que la
            // mention accompagne la distribution. Une app qui les embarque sans
            // les créditer est en défaut, et le défaut voyage avec chaque
            // installation.
            Spacer(Modifier.height(espace.xl))
            ONTSectionHeader("Crédits")
            ONTGroup {
                ONTRow(titre = "Traduction", fin = { Valeur("Gloire Bikouta") })
                ONTGroupDivider()
                ONTRow(titre = "Hébreu", fin = { Valeur("Ezra SIL — SIL Open Font License") })
                ONTGroupDivider()
                ONTRow(titre = "Titres", fin = { Valeur("Frank Ruhl Libre — OFL") })
            }

            if (enDeveloppement) {
                Spacer(Modifier.height(espace.xl))
                ONTSectionHeader("Développement")
                ONTGroup {
                    ONTRow(
                        titre = "Design system",
                        detail = "jetons, surfaces, fontes, rendu",
                        icone = Icons.Filled.Palette,
                        onClick = { onAller(DestinationVous.CATALOGUE) },
                        fin = { Chevron() },
                    )
                }
            }

            Spacer(Modifier.height(espace.xxl))
        }
    }
}

@Composable
private fun Chevron() {
    val theme = LocalReadingTheme.current
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = ONTColors.inkSoft(theme),
    )
}

@Composable
private fun Valeur(texte: String) {
    val theme = LocalReadingTheme.current
    Text(texte, color = ONTColors.inkSoft(theme), fontSize = 15.sp)
}

/**
 * Un bouton de connexion.
 *
 * Éteint tant que le compte n'existe pas, et **il le dit** : un bouton qui ne
 * répond pas sans expliquer pourquoi se lit comme un défaut de l'app.
 *
 * Pas de « Continuer avec Apple » : sur Android, il faudrait passer par le web,
 * et le lecteur qui a un compte Apple l'aura créé sur son iPhone. On l'ajoutera
 * quand la synchronisation existera, pas avant — annoncer trois fournisseurs
 * dont un ne marche pas est pire que d'en annoncer deux.
 */
@Composable
private fun BoutonDeConnexion(intitule: String, onAppui: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(ONTRadius.pill))
            // **Plein**, pas délavé. Un bouton grisé se lit comme un défaut de
            // l'app ; celui-ci répond, et ce qu'il répond est qu'il n'est pas
            // encore branché. Dire « pas encore » vaut mieux que ne rien dire.
            .background(ONTColors.burgundy)
            .clickable(onClick = onAppui)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            intitule,
            color = ONTColors.gold,
            fontSize = 16.sp,
            textAlign = TextAlign.Center,
        )
    }
}
