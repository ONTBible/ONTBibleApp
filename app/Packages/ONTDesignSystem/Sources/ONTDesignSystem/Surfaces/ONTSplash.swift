import ONTKit
import SwiftUI

/// L'ouverture — la montagne qu'un trait de lumière révèle.
///
/// # Ce que ce n'est pas
///
/// **Ce n'est pas l'écran de lancement d'iOS.** Celui-là est décrit par
/// `UILaunchScreen` dans le `Info.plist`, il est fixe par construction, et
/// aucun code n'y tourne : le système l'affiche avant que l'app existe. Il
/// reste ce qu'il est, un fond uni.
///
/// Ceci est une **vue de l'app**, posée par-dessus le premier écran et
/// dissoute ensuite. C'est le seul endroit où une animation est possible.
///
/// # D'où vient ce qui est ici
///
/// Le mouvement est celui composé par l'auteur (`logomark-sweep.jsx`), porté
/// au dixième plutôt que réinventé. Ses trois temps, ses trois courbes et la
/// géométrie de sa lueur sont repris tels quels — voir ``Minutage``.
///
/// **Le fond est la nuit du projet, quel que soit le thème de lecture.**
///
/// Deux raisons qui vont dans le même sens. La première est technique : toute
/// la lumière du dessin passe par `mix-blend-mode: screen`, qui n'a **aucun
/// effet** sur un fond clair — sur le parchemin, le balayage serait invisible
/// et la montagne plate. L'ouverture exige un fond sombre.
///
/// La seconde est que ce sombre-là n'a pas à être un noir de circonstance. Le
/// dessin était sur `#0b0b0b` ; ``ONTColors/nuit`` — **#18090D**, le fond de
/// `ontbible.com` — est un bordeaux presque noir qui appartient déjà à la
/// palette. L'ouverture est donc la même pour tout le monde, et elle est de la
/// maison plutôt que neutre.
///
/// Reste la dissolution finale : la nuit se fond dans le fond du thème pendant
/// la rémanence. Un écran sombre qui saute sur du parchemin serait un
/// éblouissement à chaque ouverture.
public struct ONTSplash: View {

    /// Les trois temps du dessin, en secondes depuis l'apparition.
    ///
    /// Repris de `window.OM_SCENES` sans les toucher : l'auteur les a réglés à
    /// l'œil, et un mouvement dont on rogne les respirations cesse d'être le
    /// même mouvement.
    public enum Minutage {
        /// *Le logomark repose dans la pénombre, à peine visible.*
        public static let attente: Double = 1.1
        /// *Une lueur traverse la montagne et déborde de la silhouette.*
        public static let balayage: Double = 2.8
        /// *La lumière quitte le cadre, une rémanence chaude retombe.*
        public static let repos: Double = 1.6

        /// L'instant où le balayage commence.
        public static let debutDuBalayage = attente
        /// L'instant où il finit.
        public static let finDuBalayage = attente + balayage
        /// La durée entière.
        public static let total = attente + balayage + repos
    }

    private let theme: ReadingTheme
    private let debut: Date

    /// Vrai quand le lecteur a demandé moins de mouvement.
    ///
    /// Le balayage disparaît alors, et la montagne paraît simplement. Ce
    /// réglage ne relève pas du goût : il sert ceux que le mouvement rend
    /// malades, et un balayage « seulement plus doux » ne les soulagerait pas.
    @Environment(\.accessibilityReduceMotion) private var reduireLeMouvement

    public init(theme: ReadingTheme, debut: Date = Date()) {
        self.theme = theme
        self.debut = debut
    }

    public var body: some View {
        TimelineView(.animation(paused: reduireLeMouvement)) { instant in
            let t = instant.date.timeIntervalSince(debut)
            rendu(a: reduireLeMouvement ? Minutage.finDuBalayage : t)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("La Bible ONT")
    }

    // MARK: - Le rendu, à un instant donné

    @ViewBuilder
    private func rendu(a t: Double) -> some View {
        let front = frontDeLumiere(a: t)
        let montee = t < Minutage.debutDuBalayage
            ? Courbe.sortieCubique(Progression.entre(0, Minutage.debutDuBalayage, t))
            : 1
        let remanence = t >= Minutage.finDuBalayage
            ? Courbe.sortieQuadratique(
                Progression.entre(Minutage.finDuBalayage, Minutage.total, t)
              ) * 0.8
            : 0
        let allumage = reduireLeMouvement ? 0 : allumage(a: t)
        let dansLeCadre = Progression.paliers(
            front, [-0.12, 0.06, 0.94, 1.12], [0, 1, 1, 0]
        )

        GeometryReader { cadre in
            let largeur = cadre.size.width
            // Le logomark est large — 502 sur 249. On le pose sur la largeur de
            // l'écran, jamais sur sa hauteur : cadré en hauteur, il déborderait
            // sur un téléphone étroit.
            //
            // **Un peu plus d'un tiers de la largeur, et non les trois quarts.**
            // À la taille du dessin il remplissait l'écran, ce qui va sur une
            // page web où il est le sujet — ici il est une marque, et une marque
            // se pose. Le rapetisser laisse aussi la lueur déborder dans du
            // vide plutôt que de buter sur les bords.
            //
            // **Le plafond ne mord que sur tablette.** Sur un téléphone, 36 %
            // de 393 pt font 141 pt — la borne ne sert jamais, et le cadrage
            // validé là-bas ne dépend donc que du pourcentage.
            //
            // Sur iPad elle décide de tout. J'avais raisonné qu'une marque à
            // 24 % de la dalle « paraissait perdue » et je l'ai agrandie : à
            // l'œil c'était déjà trop. Une grande dalle ne demande pas une
            // grande marque — elle demande **plus de vide autour**, et c'est
            // ce vide qui la pose.
            let largeurDuLogo = min(largeur * 0.36, 225)
            let hauteurDuLogo = largeurDuLogo * 249 / 502

            // **Un seul point d'ancrage, dont tout le reste dépend.**
            //
            // La traînée était posée sur le milieu de l'écran pendant que la
            // montagne, elle, était remontée : les deux se désalignaient à
            // chaque retouche de cadrage, et la lumière filait à côté du sommet
            // qu'elle est censée quitter.
            //
            // Au centre, franchement. J'avais remonté la marque au « centre
            // optique » — une marque posée au milieu paraîtrait tomber —, et
            // l'auteur a tranché l'inverse à l'écran. La règle est vraie en
            // général et fausse ici : l'ouverture n'a rien d'autre à l'écran
            // qui puisse servir de contrepoids, donc rien qui fasse paraître le
            // milieu trop bas.
            let centreDuLogo = CGPoint(x: largeur / 2, y: cadre.size.height / 2)

            // La traînée sort de la crête, à 46 % de la hauteur du logomark —
            // la valeur du dessin, rapportée à sa boîte et non à l'écran.
            let hauteurDeLaTrainee = centreDuLogo.y + (0.46 - 0.5) * hauteurDuLogo

            ZStack {
                fond()

                // La traînée anamorphique — la lumière jetée de côté hors de la
                // crête éclairée. Elle **n'est pas masquée** : c'est elle qu'on
                // voit filer au-delà de la montagne.
                if !reduireLeMouvement {
                    trainee(largeur: largeur)
                        .position(x: front * largeur, y: hauteurDeLaTrainee)
                        .opacity(allumage * dansLeCadre * 0.22)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }

                ZStack {
                    // La montagne dans la pénombre — le socle, toujours là.
                    montagne(hauteur: hauteurDuLogo)
                        .foregroundStyle(Teintes.penombre)

                    // La même, en or, qui monte pendant l'attente et garde une
                    // chaleur pendant la rémanence.
                    montagne(hauteur: hauteurDuLogo)
                        .foregroundStyle(Teintes.or)
                        .blendMode(.screen)
                        .opacity(0.2 + montee * 0.22 + remanence * 0.3)

                    // La part éclairée de cette **même** montagne. La lueur est
                    // son ombre portée : la lumière sort de la silhouette sans
                    // jamais la dupliquer.
                    if !reduireLeMouvement {
                        bande(largeur: largeurDuLogo, front: front)
                            .frame(width: largeurDuLogo, height: hauteurDuLogo)
                            .mask(montagne(hauteur: hauteurDuLogo))
                            .lueur()
                            .blendMode(.screen)
                            .opacity(allumage)
                            .allowsHitTesting(false)
                    }
                }
                // **Indispensable.** Sans groupe, un `blendMode` ne se mêle pas
                // aux vues de son propre `ZStack` : il déborde et se compose
                // avec tout ce qui est derrière, jusqu'à la fenêtre. La montagne
                // disparaissait entièrement.
                .compositingGroup()
                .frame(width: largeurDuLogo, height: hauteurDuLogo)
                .position(x: centreDuLogo.x, y: centreDuLogo.y)
            }
        }
    }

    // MARK: - Les pièces

    /// Le fond du dessin, qui se dissout dans celui du thème à la rémanence.
    ///
    /// Sans cette dissolution, l'app passerait du presque-noir au parchemin
    /// d'une image à l'autre.
    private func fond() -> some View {
        // **Opaque, et non un voile.** La première version posait la nuit à
        // vingt pour cent par-dessus le fond du thème : on obtenait du
        // parchemin assombri, l'app restait lisible derrière, et le `screen`
        // du balayage n'avait plus de noir sur quoi mordre.
        //
        // La dissolution vers l'app n'appartient pas à ce fond : c'est
        // l'ouverture **entière** qui s'efface, et `AvecOuverture` s'en charge.
        RadialGradient(
            // **La nuit au centre, et plus sombre encore au bord.**
            //
            // La première version prenait ``ONTColors/nuitSurface`` au centre —
            // #261016, la *surface* du site, pas son sol. Le fond montait alors
            // à (39,19,25) au milieu de l'écran : encore visible comme une
            // couleur, là où il doit être une absence.
            //
            // Le bord est la nuit mêlée de noir plutôt qu'un noir franc : c'est
            // ce qui garde le bordeaux perceptible au lieu de le remplacer.
            colors: [ONTColors.nuit, Teintes.nuitProfonde],
            center: UnitPoint(x: 0.5, y: 0.55),
            startRadius: 0,
            endRadius: 620
        )
        .background(Teintes.nuitProfonde)
        .ignoresSafeArea()
    }

    private func montagne(hauteur: CGFloat) -> some View {
        ONTMountain(height: hauteur)
    }

    /// La bande lumineuse qui traverse la montagne.
    ///
    /// Elle fait 2,2 fois la largeur du logo et son cœur clair est **centré sur
    /// le front** : c'est la traduction du `background-size: 220%` et de la
    /// position calculée du dessin, qui reviennent exactement à cela.
    private func bande(largeur: CGFloat, front: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: Teintes.or.opacity(0), location: 0.32),
                .init(color: Teintes.orClair.opacity(0.95), location: 0.44),
                .init(color: Teintes.coeur, location: 0.5),
                .init(color: Teintes.orClair.opacity(0.95), location: 0.56),
                .init(color: Teintes.or.opacity(0), location: 0.68),
            ],
            // 100° dans le dessin : presque horizontal, légèrement incliné.
            startPoint: UnitPoint(x: 0, y: 0.41),
            endPoint: UnitPoint(x: 1, y: 0.59)
        )
        .frame(width: largeur * 2.2)
        .offset(x: (front - 0.5) * largeur)
    }

    private func trainee(largeur: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: Teintes.orClair.opacity(0), location: 0),
                .init(color: Teintes.trainee.opacity(0.55), location: 0.45),
                .init(color: Teintes.traineeCoeur, location: 0.5),
                .init(color: Teintes.trainee.opacity(0.55), location: 0.55),
                .init(color: Teintes.orClair.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: largeur * 1.45, height: 26)
        .blur(radius: 20)
    }

    // MARK: - Le calcul du mouvement

    /// Où se trouve le front de lumière, de −0,22 à 1,22.
    ///
    /// Il naît et meurt **hors du cadre** : on ne doit jamais le voir
    /// apparaître ni s'éteindre.
    private func frontDeLumiere(a t: Double) -> Double {
        let p = Courbe.sinusoidale(
            Progression.entre(Minutage.debutDuBalayage, Minutage.finDuBalayage, t)
        )
        return -0.22 + (1.22 + 0.22) * p
    }

    /// L'intensité de la part éclairée — elle monte avant le balayage et
    /// retombe après, pour que la lumière n'apparaisse pas d'un coup.
    private func allumage(a t: Double) -> Double {
        Progression.paliers(
            t,
            [
                Minutage.debutDuBalayage - 0.3,
                Minutage.debutDuBalayage + 0.25,
                Minutage.finDuBalayage - 0.15,
                Minutage.finDuBalayage + 0.5,
            ],
            [0, 1, 1, 0],
            courbe: Courbe.sinusoidale
        )
    }
}

// MARK: - Les teintes du dessin

/// Les couleurs propres à l'ouverture.
///
/// Elles ne passent pas par ``ONTColors`` parce qu'elles ne sont **pas** des
/// jetons du design system : ce sont les valeurs du dessin, sur un fond sombre
/// imposé. Les mêler aux jetons de lecture donnerait à croire qu'on peut les
/// employer ailleurs.
private enum Teintes {
    /// La montagne dans la pénombre — `#3a3527`.
    static let penombre = Color(red: 0.227, green: 0.208, blue: 0.153)
    /// L'or du logo — `#cdbe83`.
    static let or = Color(red: 0.804, green: 0.745, blue: 0.514)
    /// L'or clair de la bande — `#e9d68d`.
    static let orClair = Color(red: 0.914, green: 0.839, blue: 0.553)
    /// Le cœur de la bande — `#fffaf0`.
    static let coeur = Color(red: 1, green: 0.980, blue: 0.941)
    /// La traînée — `#fff6d8`.
    static let trainee = Color(red: 1, green: 0.965, blue: 0.847)
    /// Son cœur — `#fffdf5`.
    static let traineeCoeur = Color(red: 1, green: 0.992, blue: 0.961)
    /// La nuit du projet, assombrie — le bord du dégradé.
    ///
    /// ``ONTColors/nuit`` (#18090D) ramenée à 45 % de sa clarté, écrite plutôt
    /// que calculée : `Color.mix(with:by:)` n'existe qu'à partir de macOS 15,
    /// et le paquet déclare macOS 14. La compilation pour iOS ne le montrait
    /// pas — seule celle du paquet, qui vise aussi le Mac, faisait rougir.
    static let nuitProfonde = Color(red: 0.042, green: 0.016, blue: 0.023)
    /// La lueur — `rgba(255,240,200,·)`.
    static let lueur = Color(red: 1, green: 0.941, blue: 0.784)
}

extension View {
    /// Les cinq ombres portées empilées du dessin.
    ///
    /// Cinq et non une : c'est l'empilement qui donne une lueur qui **décroît**
    /// avec la distance au lieu d'un halo uniforme. Les rayons et les opacités
    /// sont ceux du `filter` d'origine.
    fileprivate func lueur() -> some View {
        self
            .shadow(color: Teintes.lueur.opacity(1), radius: 6)
            .shadow(color: Teintes.lueur.opacity(0.95), radius: 17)
            .shadow(color: Teintes.lueur.opacity(0.8), radius: 40)
            .shadow(color: Teintes.lueur.opacity(0.6), radius: 80)
            .shadow(color: Teintes.lueur.opacity(0.42), radius: 150)
    }
}

// MARK: - Les courbes, telles que le dessin les emploie

private enum Courbe {
    static func sortieCubique(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    static func sortieQuadratique(_ p: Double) -> Double { 1 - pow(1 - p, 2) }
    static func sinusoidale(_ p: Double) -> Double { -(cos(.pi * p) - 1) / 2 }
}

private enum Progression {
    /// La part parcourue entre deux instants, bornée.
    static func entre(_ debut: Double, _ fin: Double, _ t: Double) -> Double {
        guard fin > debut else { return t >= fin ? 1 : 0 }
        return min(1, max(0, (t - debut) / (fin - debut)))
    }

    /// Une interpolation par paliers — l'équivalent du `interpolate` du dessin.
    static func paliers(
        _ x: Double,
        _ bornes: [Double],
        _ valeurs: [Double],
        courbe: (Double) -> Double = { $0 }
    ) -> Double {
        guard bornes.count == valeurs.count, bornes.count >= 2 else { return 0 }
        if x <= bornes[0] { return valeurs[0] }
        if x >= bornes[bornes.count - 1] { return valeurs[valeurs.count - 1] }

        for i in 0..<(bornes.count - 1) where x >= bornes[i] && x <= bornes[i + 1] {
            let p = entre(bornes[i], bornes[i + 1], x)
            return valeurs[i] + (valeurs[i + 1] - valeurs[i]) * courbe(p)
        }
        return valeurs[valeurs.count - 1]
    }
}

#Preview("L'ouverture") {
    ONTSplash(theme: .parchment)
}
