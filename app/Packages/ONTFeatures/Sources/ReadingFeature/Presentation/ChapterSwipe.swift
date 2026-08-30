import ONTDesignSystem
import ONTKit
import SwiftUI

/// Passer d'une unité à la suivante d'un glissement horizontal.
///
/// ## Pourquoi horizontal
///
/// La lecture défile verticalement. Un geste horizontal ne peut donc jamais
/// être confondu avec elle — c'est le seul axe libre, et c'est celui que
/// YouVersion emploie.
///
/// ## Ce qu'on ne fait pas : garder trois unités sous la main
///
/// La solution évidente serait un défilement paginé sur toutes les unités du
/// livre, précédente et suivante déjà construites. Mais une unité se construit
/// **d'un coup** ici — c'est le compromis assumé de `ChapterView`, qui achète
/// un défilement exact au prix d'une construction complète. En garder trois
/// vivantes, c'est tripler ce prix à chaque ouverture.
///
/// Regardé de près, YouVersion ne rend pas l'unité suivante pendant le geste
/// non plus : le texte courant glisse, et derrière lui il n'y a que le fond de
/// page. Il n'y a donc rien à précharger.
///
/// ## Le chargement se cache dans l'animation
///
/// L'unité qui arrive est construite au moment où le geste **franchit le
/// seuil** — pendant que le doigt est encore posé, et que le texte courant
/// occupe toujours l'écran. Le temps de construction se dépense donc là où il
/// ne se voit pas.
///
/// Et si la construction dure plus longtemps que l'animation, c'est
/// l'animation qui attend : on ne montre jamais une page vide. C'est pour ça
/// que les deux unités cohabitent le temps de la transition, et pour ça seul.
///
/// ## Ce que le glissement ne fait pas
///
/// Il ne touche pas au chemin de navigation. Revenir en arrière ramène donc à
/// la liste des unités, et non à celle dont on est parti — c'est le
/// comportement d'un lecteur qui feuillette, pas d'une pile qui s'empile.
/// La position de lecture, elle, suit : c'est elle qui compte pour « Reprendre ».
struct ChapterSwipe: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme

    let depart: Chapter

    @State private var courant: Chapter
    /// L'unité qui arrive, construite dès que le seuil est franchi.
    @State private var entrant: Chapter?
    /// De combien le doigt a déplacé la page.
    @State private var glisse: CGFloat = 0
    /// −1 vers la suivante, +1 vers la précédente.
    @State private var sens: CGFloat = 0
    @State private var enTransition = false
    /// L'opacité du cache. Pleine pendant le geste, elle tombe quand le geste
    /// est confirmé — c'est ce qui découvre l'unité qui arrive.
    @State private var voile: Double = 1
    /// Vrai dès que le geste horizontal a pris la main.
    @State private var gesteEngage = false
    /// Vrai dès que le seuil est franchi : la page **va** tourner si l'on
    /// lâche maintenant. C'est ce moment-là qui mérite d'être senti.
    @State private var arme = false
    /// Un compteur, pas un drapeau : deux renoncements de suite doivent se
    /// sentir deux fois, et un drapeau qui repasse à la même valeur ne
    /// déclencherait rien la seconde fois.
    @State private var renoncements = 0
    /// L'axe du geste en cours, décidé **une fois** et tenu jusqu'au bout.
    ///
    /// Il était réévalué à chaque mouvement : un long défilement vertical qui
    /// dérive un peu finissait par satisfaire le critère horizontal, et la page
    /// tournait alors qu'on lisait. Un geste a un axe, il ne change pas d'avis
    /// en route.
    @State private var axeHorizontal: Bool?
    /// La taille de la vue, relevée sans l'envelopper.
    @State private var taille: CGSize = .zero
    /// Pour lire la marge latérale de la colonne de lecture, qui suit le
    /// Dynamic Type — voir `seuilDuGeste(_:)`.
    var spacing = ONTSpacing()

    init(depart: Chapter) {
        self.depart = depart
        _courant = State(initialValue: depart)
    }

    /// Jusqu'où le texte s'écarte — **calculé**, pas choisi.
    ///
    /// Le pli mord `creuxMax` dans la page. Tant que le texte ne recule pas
    /// d'autant, la découpe lui prend des lettres : c'est arithmétique, et
    /// c'était le défaut. Il faut donc reculer d'au moins ce que le pli mord,
    /// moins la marge de lecture — qui ne porte aucun glyphe et absorbe donc
    /// une part de la morsure — plus une respiration.
    ///
    /// La marge vient de `ONTSpacing`, donc elle **suit le curseur de taille de
    /// texte**. En la fixant en dur, le plafond se mettrait à mentir dès que le
    /// lecteur agrandit son texte, c'est-à-dire précisément chez qui en a
    /// besoin.
    ///
    /// Les douze pour cent relevés chez YouVersion restent un **plancher**,
    /// pour les écrans trop étroits pour la règle ci-dessus. Eux n'ont pas de
    /// pli à dégager ; nous si.
    private func seuilDuGeste(_ largeur: CGFloat) -> CGFloat {
        max(largeur * Self.plafond, Self.creuxMax - spacing.page + 14)
    }

    /// Ce que le geste gagne encore **au-delà** du seuil.
    ///
    /// Le seuil et la butée étaient le même point : une fois armé, le doigt
    /// était déjà contre le mur, et revenir en deçà se jouait au cheveu près.
    /// Le second retour haptique serait alors tombé sur un tremblement plutôt
    /// que sur une intention.
    ///
    /// Résisté au tiers : il faut environ soixante-dix-huit points de doigt
    /// pour en gagner vingt-six. C'est ce qui fait sentir la butée — et c'est
    /// surtout la marge dont le retour a besoin pour être un vrai mouvement.
    private func depassement(_ ecart: CGFloat, seuil: CGFloat) -> CGFloat {
        guard ecart > seuil else { return 0 }
        return min((ecart - seuil) / 3, Self.depassementMax)
    }

    /// Où en est le geste, de zéro au plafond.
    private var avancement: CGFloat {
        let limite = seuilDuGeste(taille.width)
        return limite > 0 ? min(abs(glisse) / limite, 1) : 0
    }

    /// La densité de l'ombre dans le soulèvement.
    ///
    /// Elle croît avec le geste — plus on tire, plus le dessous s'assombrit —
    /// puis **saute** quand le plafond est atteint. Ce saut n'est pas un ornement :
    /// c'est le signal, et le retour haptique tombe au même instant. L'œil et
    /// le doigt apprennent donc la même chose en même temps, ce qui est tout
    /// l'intérêt du procédé chez YouVersion, où c'est leur pastille qui noircit.
    private var densite: Double {
        arme ? 1 : 0.28 + 0.44 * Double(avancement)
    }

    /// L'ombre du soulèvement — sur **toute** la zone découverte.
    ///
    /// Elle s'éteignait à 150 pt du pli, si bien que l'intérieur du
    /// soulèvement redevenait du fond nu : on voyait une arête ombrée, pas un
    /// dessous. Les hachures du croquis, elles, remplissent la lentille
    /// entière.
    ///
    /// Cette extinction avait sa raison en son temps — empêcher le voile de
    /// couvrir l'écran pendant que la morsure grandissait jusqu'à l'avaler.
    /// Elle n'en a plus : la bascule est devenue instantanée, et la morsure ne
    /// grandit plus au-delà du plafond.
    ///
    /// Le dégradé qui reste ne sert qu'à **modeler** le creux — un peu plus
    /// dense contre le pli, comme une ombre portée l'est toujours. Il ne crée
    /// plus de zone claire.
    private var ombreDuPli: [Gradient.Stop] {
        [
            .init(color: .black.opacity(0.80), location: 0),
            .init(color: .black.opacity(0.70), location: 0.45),
            .init(color: .black.opacity(0.62), location: 1),
        ]
    }

    /// Les unités présentes, de la plus basse à la plus haute.
    ///
    /// L'ordre porte le rang dans la pile : celle qui arrive est **dessous**,
    /// la courante par-dessus. Quand la première est promue, la liste se réduit
    /// à elle seule — et parce qu'elle est identifiée, sa vue survit au lieu
    /// d'être rebâtie.
    private var couches: [Chapter] {
        guard let entrant, entrant.id != courant.id else { return [courant] }
        return [entrant, courant]
    }

    /// L'abscisse du bord que la page découvre en partant.
    private func bordPage(_ largeur: CGFloat) -> CGFloat {
        sens < 0 ? largeur + glisse : glisse
    }

    /// La profondeur du creux, en points — un **état** et non un calcul.
    ///
    /// Pendant le geste, il suit le doigt. À la confirmation, il doit pouvoir
    /// aller bien au-delà de ce que le doigt a commandé : jusqu'à la largeur
    /// entière, pour que la morsure finisse par avaler la page. Un calcul tiré
    /// du glissement ne saurait pas faire ça.
    @State private var creux: CGFloat = 0


    /// Le plafond du geste — et le seuil, car c'est le même point.
    ///
    /// Douze pour cent de la largeur, relevés sur YouVersion : leur texte
    /// s'arrête à 140 px sur 1206 et n'avance plus, le doigt eût-il continué.
    ///
    /// Confondre le plafond et le seuil est ce qui rend le geste apprenable.
    /// Une limite qu'on **voit** enseigne où elle se trouve ; un seuil
    /// invisible se devine à l'usage, ou jamais.
    private static let plafond: CGFloat = 0.12

    /// La profondeur du creux au plafond.
    ///
    /// Le croquis donne une profondeur de la moitié de la hauteur du ventre,
    /// lequel fait 55 % de la page. Sur un téléphone tenu en main, cette
    /// proportion littérale donnerait une découpe énorme : on garde le
    /// caractère du dessin — un ventre franc — à une échelle qui tient dans
    /// une page qu'on lit.
    private static let creuxMax: CGFloat = 96

    /// Ce que le pli et le texte gagnent encore au-delà du seuil.
    private static let depassementMax: CGFloat = 26

    /// De combien on redescend sous le seuil avant de désarmer.
    ///
    /// Un doigt posé pile dessus le franchirait et le refranchirait à chaque
    /// micro-mouvement, et chaque passage vibrerait. Cinq points sont
    /// invisibles à l'œil comme au doigt ; ils suffisent à ce qu'un tremblement
    /// ne traverse pas la frontière deux fois par seconde.
    private static let jeuDeDesarmement: CGFloat = 5

    /// De combien l'unité qui arrive est décalée quand elle paraît.
    ///
    /// Neuf pour cent de la largeur — 108 px sur 1206, relevés sur le film.
    /// C'est court, et c'est le point : elle ne traverse pas l'écran, elle se
    /// pose.
    private static let entree: CGFloat = 0.09

    var body: some View {
        // **Pas de `GeometryReader`.** Il a coûté deux détours.
        //
        // Enveloppant, il respecte la zone sûre et enferme tout ce qu'il porte
        // sous la barre de navigation : le texte cessait d'atteindre le haut de
        // l'écran. Lui faire ignorer la zone sûre corrige ça mais la retire
        // aussi à la vue de défilement, qui perd alors sa marge de départ — le
        // titre venait buter contre les boutons.
        //
        // La pile est donc la vue de tête, comme `ChapterView` l'était avant le
        // geste : les zones sûres se comportent exactement comme avant, et la
        // vue de défilement garde le droit d'en décider pour elle-même. La
        // taille se relève sans rien envelopper.
        ZStack {
            // Le fond, toujours là. C'est lui qu'on voit dans la morsure
            // pendant le geste — jamais le chapitre suivant.
            theme.background
                .ignoresSafeArea()

            // Les deux unités, dans **une seule liste identifiée**.
            //
            // C'est ce qui casse à la fin quand on ne le fait pas. En gardant
            // l'unité qui arrive dans une variable et l'unité courante dans une
            // autre, la promotion — « celle qui arrivait devient la courante » —
            // est un changement de place dans la pile. SwiftUI ne reconnaît pas
            // la même vue à deux places différentes : il jette celle qu'il
            // venait de construire et en rebâtit une identique. D'où la
            // secousse au moment précis où l'animation devrait se poser.
            //
            // Une liste clé par unité supprime la question : la vue de l'unité
            // qui arrive **est** celle qui reste, elle ne change que de rang.
            ForEach(couches, id: \.id) { chapitre in
                let dessus = chapitre.id == courant.id

                ChapterView(
                    chapter: chapitre,
                    actif: dessus && entrant == nil,
                    // Seule celle du dessus glisse et se creuse. Les
                    // modificateurs restent posés dans le même ordre pour les
                    // deux : une chaîne qui change de forme changerait
                    // l'identité, et on perdrait ce qu'on vient de gagner.
                    decalage: dessus ? glisse : 0
                )
                .clipShape(Feuillet(creux: dessus ? creux : 0, aDroite: sens < 0))
                // L'unité qui arrive est construite dès le seuil mais reste
                // **invisible** : le lecteur ne doit pas la voir venir. Elle
                // paraît quand le voile se lève, une fois le geste confirmé.
                .opacity(dessus ? 1 : 1 - voile)
            }

            // La morsure, et rien qu'elle : entre la courbe et le bord de
            // l'écran. Elle ne peut plus laisser de zone morte, puisqu'elle
            // est définie par ce bord.
            Decouvert(bordPage: sens < 0 ? taille.width : 0, creux: creux, aDroite: sens < 0)
                .fill(
                    LinearGradient(
                        stops: ombreDuPli,
                        startPoint: sens < 0 ? .leading : .trailing,
                        endPoint: sens < 0 ? .trailing : .leading
                    )
                )
                .allowsHitTesting(false)
                // La densité passe par l'opacité et non par les teintes : une
                // opacité s'interpole, une pile d'arrêts de dégradé non — le
                // saut au plafond ne s'animerait pas.
                .opacity(creux == 0 ? 0 : densite)

            // Le numéro, dans le ventre — à la hauteur où la page cède.
            if creux > 1, let numero = numeroVoisin(suivante: sens < 0) {
                Pastille(numero: numero, densite: densite)
                    .position(
                        x: (sens < 0 ? taille.width : 0) + sens * creux * 0.5,
                        y: taille.height * Ventre.centre
                    )
                    .opacity(min(Double(creux) / 44, 1) * voile)
            }
        }

            // Deux retours, et deux seulement.
            //
            // Le premier au **franchissement du seuil** : le doigt est encore
            // posé, et c'est l'instant où l'on apprend que lâcher tournera la
            // page. C'est le seul retour qui renseigne — les autres ne font que
            // commenter ce qu'on voit déjà.
            //
            // Le second à l'**arrivée**, plus sourd : il clôt le geste, comme
            // une page qui se pose. Déclenché sur l'unité elle-même, donc il ne
            // peut pas se produire pour un geste annulé.
            // Dans les **deux** sens, et c'est le point.
            //
            // Une clôture conditionnelle ne le déclenchait qu'à l'armement :
            // franchir le seuil se sentait, revenir en deçà était muet. Or c'est
            // la **même** frontière qu'on traverse — lui donner une voix à
            // l'aller et le silence au retour laissait le doigt sans nouvelle
            // au moment où il renonce.
            //
            // Même sensation des deux côtés, délibérément : deux sensations
            // différentes feraient croire à deux événements différents.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.65), trigger: arme)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.45), trigger: courant.id)
            // Le troisième : la page qui **revient**. Plus léger que les deux
            // autres, parce qu'il ne dit pas qu'il s'est passé quelque chose —
            // il dit que rien ne s'est passé, et que le geste est rendu.
            .sensoryFeedback(.impact(weight: .light, intensity: 0.30), trigger: renoncements)
            .environment(\.ontLectureFigee, gesteEngage || enTransition)
            .simultaneousGesture(geste(largeur: taille.width), isEnabled: !enTransition)
        // On relève la taille sans envelopper : la mesure n'a pas à changer la
        // mise en page de ce qu'elle mesure.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { taille = $0 }
        // Le glissement de retour du système part du bord gauche et pousse
        // vers la droite — exactement le geste qui demande l'unité précédente.
        // Deux commandes sur un même mouvement, et c'est le système qui gagne :
        // on croyait feuilleter, on quittait la lecture.
        //
        // On le coupe **ici seulement**, le temps de la lecture. La flèche de
        // la barre reste, et c'est elle qui porte le retour désormais.
        .sansGesteDeRetourSysteme()
    }

    private func geste(largeur: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { mouvement in
                let dx = mouvement.translation.width
                let dy = mouvement.translation.height

                // L'axe se tranche au premier mouvement qui compte, et ne se
                // rejuge plus. Vertical : on ne touche à rien de tout le geste.
                if axeHorizontal == nil {
                    guard max(abs(dx), abs(dy)) > 12 else { return }
                    axeHorizontal = abs(dx) > abs(dy) * 1.5
                }
                guard axeHorizontal == true else { return }
                // Le défilement de lecture s'arrête ici : à partir du moment où
                // l'horizontale l'emporte, la page se soulève et ne descend
                // plus.
                gesteEngage = true

                let seuil = seuilDuGeste(largeur)
                let versLaSuivante = dx < 0
                guard let cible = voisine(suivante: versLaSuivante) else {
                    // Au bout du livre : la page résiste au lieu de se bloquer
                    // net. Un arrêt sec se lit comme un défaut.
                    glisse = min(max(dx / 4, -seuil), seuil)
                    creux = 0
                    return
                }

                let ecart = abs(dx)
                let gagne = depassement(ecart, seuil: seuil)
                sens = versLaSuivante ? -1 : 1

                // Le texte et le pli gagnent **exactement le même** dépassement,
                // et c'est ce qui préserve la garantie du seuil : le texte doit
                // reculer d'autant que le pli mord. En les faisant croître du
                // même pas, la marge qui l'empêche d'être mangé reste intacte
                // sur toute la course. Un pli qui se creuserait plus vite que
                // le texte ne s'écarte remangerait des lettres au moment précis
                // où le geste est armé.
                glisse = sens * (min(ecart, seuil) + gagne)
                creux = Self.creuxMax * min(ecart / seuil, 1) + gagne

                // Le seuil franchi, on construit — le doigt est encore posé et
                // le texte courant occupe toujours l'écran.
                if ecart >= seuil, entrant?.id != cible.id {
                    entrant = cible
                }

                // Armé au seuil, désarmé un peu en deçà : le jeu empêche qu'un
                // doigt immobile sur la frontière la traverse en rafale.
                //
                // Le basculement est **animé** — quatre-vingt-dix millisecondes,
                // assez vif pour se lire comme un déclic, assez long pour ne
                // pas clignoter quand on hésite.
                let devrait = arme
                    ? ecart >= seuil - Self.jeuDeDesarmement
                    : ecart >= seuil
                if arme != devrait {
                    withAnimation(.easeOut(duration: 0.09)) { arme = devrait }
                }
            }
            .onEnded { mouvement in
                let horizontal = axeHorizontal == true
                axeHorizontal = nil
                guard horizontal else { return }

                let dx = mouvement.translation.width
                let lance = mouvement.predictedEndTranslation.width
                // Le plafond atteint suffit — il n'y a plus de seuil séparé.
                // La vitesse reste un raccourci pour le coup de pouce vif qui
                // n'a pas eu le temps d'aller au bout.
                let assez = abs(dx) >= seuilDuGeste(largeur) || abs(lance) > largeur * 0.5

                guard assez, let cible = entrant ?? voisine(suivante: dx < 0) else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        glisse = 0
                        creux = 0
                    }
                    // Senti seulement si la page avait bougé pour de bon. Un
                    // doigt qui effleure sans rien déplacer n'a rien à se voir
                    // rendre.
                    if abs(dx) > 24 { renoncements += 1 }
                    entrant = nil
                    voile = 1
                    arme = false
                    gesteEngage = false
                    return
                }
                if entrant == nil { entrant = cible }
                tourner(la: cible, largeur: largeur)
            }
    }

    /// La fin du geste, relevée image par image sur YouVersion.
    ///
    /// ## Ce que montre le film, décomposé à 60 images par seconde
    ///
    /// La bascule est **instantanée**. Une image porte l'ancienne unité, la
    /// suivante porte la nouvelle. Aucun fondu, aucun essuyage, rien qui mange
    /// la page : le remplacement ne s'anime pas du tout.
    ///
    /// Ce qui s'anime, c'est **l'arrivée**. L'unité neuve paraît décalée de
    /// 108 px sur 1206 — neuf pour cent de la largeur — et se pose. Mesuré,
    /// son pas par image : 14, 12, 14, 14, 12, 12, 10, 10, 8, 4, 4, 2, 0. Elle
    /// ralentit et **ne dépasse jamais** sa place : une décélération pure, sans
    /// rebond. Deux cents millisecondes en tout.
    ///
    /// Et rien d'autre ne bouge. Pas d'ombre, pas de pastille, pas de voile —
    /// le fond étant uniforme, aucun bord de page ne se voit jamais.
    ///
    /// ## Ce qu'on en garde, et ce qu'on n'en garde pas
    ///
    /// On adopte la fin : bascule immédiate, puis une arrivée courte et
    /// décélérée. Ce qu'on faisait — laisser la morsure grandir jusqu'à avaler
    /// l'écran pendant que le texte parcourait toute la largeur, en 420 ms —
    /// donnait à la fin un poids qu'elle n'a pas à porter. Un geste confirmé
    /// est déjà décidé ; l'animation n'a plus rien à raconter, elle doit poser
    /// la page et se taire.
    ///
    /// On garde en revanche le pli et son ombre pour la **durée du geste** :
    /// c'est là qu'ils renseignent, et le croquis les demande. Ils
    /// disparaissent avec la bascule, comme tout le reste.
    private func tourner(la cible: Chapter, largeur: CGFloat) {
        enTransition = true

        // La bascule, sans animation aucune.
        courant = cible
        entrant = nil

        // Tourner la page, c'est y être. Sans cette ligne, feuilleter du 7 au 8
        // puis revenir par « Reprendre » ramenait au 7 : la position ne
        // s'écrivait qu'après un défilement, et l'on n'avait rien fait défiler.
        model.remember(chapter: cible, verse: cible.verses.first?.n ?? 1)
        creux = 0
        voile = 1
        // L'unité neuve entre du côté d'où le geste venait, à neuf pour cent
        // de la largeur.
        glisse = -sens * largeur * Self.entree

        withAnimation(.easeOut(duration: 0.20)) {
            glisse = 0
        } completion: {
            sens = 0
            arme = false
            gesteEngage = false
            enTransition = false
        }
    }

    /// Le **numéro** de l'unité d'à côté, sans la construire.
    ///
    /// La pastille est redessinée à chaque image du geste ; y appeler
    /// `voisine(suivante:)` ferait décoder une unité entière soixante fois par
    /// seconde pour n'en lire qu'un chiffre. L'esquisse du livre le porte déjà.
    private func numeroVoisin(suivante: Bool) -> Int? {
        guard
            let plan = model.outline(courant.bookId)?.chapters,
            let rang = plan.firstIndex(where: { $0.id == courant.id })
        else { return nil }
        let suite: [ChapterStub] = suivante
            ? Array(plan[plan.index(after: rang)...])
            : plan[..<rang].reversed()
        return suite.first { $0.verseCount > 0 }?.n
    }

    /// L'unité d'à côté, dans l'ordre du livre — `nil` au bout.
    ///
    /// Les unités vides sont **sautées** : un slot non rédigé fait partie du
    /// plan du corpus, mais tourner la page pour tomber sur du rien n'apprend
    /// rien à personne.
    private func voisine(suivante: Bool) -> Chapter? {
        guard
            let plan = model.outline(courant.bookId)?.chapters,
            let rang = plan.firstIndex(where: { $0.id == courant.id })
        else { return nil }

        let suite: [ChapterStub] = suivante
            ? Array(plan[plan.index(after: rang)...])
            : plan[..<rang].reversed()

        for unite in suite where unite.verseCount > 0 {
            if let chapitre = model.chapter(book: courant.bookId, id: unite.id) {
                return chapitre
            }
        }
        return nil
    }
}


/// Le numéro de l'unité qui vient, dans la bande que la page découvre.
///
/// Le repère de YouVersion, et il vaut mieux qu'une flèche : il ne dit pas
/// seulement qu'il y a une suite, il dit **laquelle**. On sait avant de lâcher
/// si on va là où on voulait.
private struct Pastille: View {
    @Environment(\.ontTheme) private var theme
    let numero: Int
    /// Où en est l'assombrissement du soulèvement, de zéro à un.
    ///
    /// La pastille vit **dans** cette zone, et celle-ci finit quasi noire. En
    /// encre du thème sur un fond à peine teinté, le numéro s'effacerait juste
    /// au moment où il compte le plus : quand le geste est armé.
    ///
    /// Ses teintes suivent donc la densité — encre du thème sur un soulèvement
    /// clair, blanc sur un soulèvement noir, et tout l'entre-deux. Le lecteur
    /// ne voit pas un changement de couleur, il voit un numéro qui reste
    /// lisible.
    let densite: Double

    var body: some View {
        // **Mêlée à la main, et non par `mix(with:by:)`.**
        //
        // Celui-ci demande macOS 15 quand le paquet en déclare 14 : l'appel ne
        // cassait que la compilation du Mac, invisible depuis un build iOS.
        // C'est exactement ce qui était arrivé au dégradé de l'ouverture, et
        // pour la même raison.
        //
        // L'interpolation linéaire par composante est ce que `mix` fait ; on
        // la pose donc, sans dépendre d'une version.
        let teinte = ONTColors.melange(theme.ink, vers: .white, part: densite)
        Text("\(numero)")
            .font(ONTUI.title3.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(teinte.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(teinte.opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}


/// La géométrie du ventre, relevée sur le croquis.
///
/// Mesurée au pixel plutôt qu'interprétée : le trait vertical du dessin donne
/// le bord d'origine, et le retrait du trait courbe, ligne par ligne, donne le
/// profil. Trois choses en sont sorties, dont deux que je n'avais pas vues.
///
/// * Le creux n'occupe pas toute la hauteur — **55 %** seulement. Le bord reste
///   droit en haut et en bas : la page ne cède qu'où le doigt tire.
/// * Son centre est à **42 %** de la hauteur, donc au-dessus du milieu. Une
///   symétrie parfaite se lit comme une découpe ; ce décalage la dément.
/// * Le ventre est **large**, en plateau entre 40 et 60 % de sa propre hauteur.
///   Pas une pointe : une matière pleine qui s'étire.
private enum Ventre {
    /// La part de la hauteur que le creux occupe.
    static let hauteur: CGFloat = 0.55
    /// Où son centre se tient, en part de la hauteur totale.
    static let centre: CGFloat = 0.42
    /// Ce qui donne au ventre son plateau : les points de contrôle poussés loin
    /// le long de la courbe. Plus bas, on retombe sur une pointe.
    static let plateau: CGFloat = 0.62

    static func bornes(_ hauteurTotale: CGFloat) -> (debut: CGFloat, milieu: CGFloat, fin: CGFloat) {
        let demi = hauteurTotale * hauteur / 2
        let milieu = hauteurTotale * centre
        return (milieu - demi, milieu, milieu + demi)
    }

    /// Trace le bord creusé, du haut vers le bas.
    /// De combien les tracés dépassent en haut et en bas.
    ///
    /// `clipShape` découpe au **cadre de la vue**, et le contenu de la lecture
    /// déborde volontairement au-dessus du sien pour passer sous la barre de
    /// navigation. Un tracé arrêté au cadre coupait donc ce débordement, même
    /// au repos : le texte s'arrêtait net en haut de la zone sûre.
    ///
    /// Les formes s'étendent donc bien au-delà, verticalement. Elles ne
    /// découpent que ce qu'elles ont à découper — le bord qui se creuse.
    static let debord: CGFloat = 4000

    static func tracer(
        _ trace: inout Path,
        bord: CGFloat,
        vers: CGFloat,
        creux: CGFloat,
        hauteurTotale: CGFloat
    ) {
        let (debut, milieu, fin) = bornes(hauteurTotale)
        let pointe = CGPoint(x: bord + vers * creux, y: milieu)

        trace.addLine(to: CGPoint(x: bord, y: debut))
        trace.addCurve(
            to: pointe,
            control1: CGPoint(x: bord, y: debut + (milieu - debut) * plateau),
            control2: CGPoint(x: pointe.x, y: milieu - (milieu - debut) * plateau)
        )
        trace.addCurve(
            to: CGPoint(x: bord, y: fin),
            control1: CGPoint(x: pointe.x, y: milieu + (fin - milieu) * plateau),
            control2: CGPoint(x: bord, y: fin - (fin - milieu) * plateau)
        )
    }
}

/// Le contour de la page, dont un bord se creuse en son milieu.
private struct Feuillet: Shape {
    var creux: CGFloat
    /// Le bord qui se creuse — celui que la page découvre en partant.
    var aDroite: Bool

    var animatableData: CGFloat {
        get { creux }
        set { creux = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var trace = Path()
        let bord = aDroite ? rect.maxX : rect.minX
        let dos = aDroite ? rect.minX : rect.maxX
        let plafond = rect.minY - Ventre.debord
        let plancher = rect.maxY + Ventre.debord

        trace.move(to: CGPoint(x: dos, y: plafond))
        trace.addLine(to: CGPoint(x: bord, y: plafond))
        Ventre.tracer(
            &trace,
            bord: bord,
            vers: aDroite ? -1 : 1,
            creux: creux,
            hauteurTotale: rect.height
        )
        trace.addLine(to: CGPoint(x: bord, y: plancher))
        trace.addLine(to: CGPoint(x: dos, y: plancher))
        trace.closeSubpath()
        return trace
    }
}

/// Tout ce que la page a découvert — **jusqu'au bord de l'écran**.
///
/// C'est ce qui manquait : l'ombre ne bordait que l'arête et laissait une bande
/// de fond nu entre elle et le bord de l'écran. Le croquis n'a pas de zone
/// vide. Ce qu'on découvre en soulevant un feuillet, ce n'est pas du rien,
/// c'est le dessous — et le dessous est dans l'ombre partout, simplement moins
/// à mesure qu'on s'éloigne du pli.
private struct Decouvert: Shape {
    /// L'abscisse du bord de la page, hors creux.
    var bordPage: CGFloat
    var creux: CGFloat
    var aDroite: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bordPage, creux) }
        set { bordPage = newValue.first; creux = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var trace = Path()
        let butee = aDroite ? rect.maxX : rect.minX

        let plafond = rect.minY - Ventre.debord
        let plancher = rect.maxY + Ventre.debord

        trace.move(to: CGPoint(x: bordPage, y: plafond))
        Ventre.tracer(
            &trace,
            bord: bordPage,
            vers: aDroite ? -1 : 1,
            creux: creux,
            hauteurTotale: rect.height
        )
        trace.addLine(to: CGPoint(x: bordPage, y: plancher))
        trace.addLine(to: CGPoint(x: butee, y: plancher))
        trace.addLine(to: CGPoint(x: butee, y: plafond))
        trace.closeSubpath()
        return trace
    }
}

/// Le défilement de lecture est-il figé ?
///
/// Il l'est dès que le geste horizontal prend la main. Les deux gestes
/// pouvaient s'exercer ensemble, et le résultat était le contraire de ce qu'on
/// veut : on tournait la page en descendant d'un demi-écran sans l'avoir voulu.
/// Un feuillet qu'on soulève ne défile pas.
struct LectureFigeeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var ontLectureFigee: Bool {
        get { self[LectureFigeeKey.self] }
        set { self[LectureFigeeKey.self] = newValue }
    }
}


// MARK: - Le glissement de retour du système

// MARK: - Le geste de retour du système

// **iOS seulement, et ce n'est pas un manque du Mac.**
//
// Ce qui suit coupe le glissement de retour du `UINavigationController` pour le
// rendre nous-mêmes. Le Mac n'a ni ce geste ni ce contrôleur : il n'y a rien à
// couper, et rien à remplacer. Une fenêtre se referme par son bouton, et le
// lecteur ne cherche pas à la faire glisser.
//
// C'est une différence qui se **décide**, pas qui se traduit — d'où ce `#if`
// ici plutôt qu'une intention dans `ONTPlateformes`, où ne vivent que les
// choses que les deux plateformes nomment autrement.
#if os(iOS)
extension View {
    /// Coupe le glissement de retour du système sur cette vue, et le rend en
    /// partant.
    ///
    /// Il n'existe pas d'équivalent SwiftUI : le geste appartient au
    /// `UINavigationController`, et seul UIKit y donne accès. D'où ce détour
    /// par un contrôleur vide, glissé dans la hiérarchie pour y trouver son
    /// parent de navigation.
    func sansGesteDeRetourSysteme() -> some View {
        background(CoupeGesteDeRetour().frame(width: 0, height: 0))
    }
}

private struct CoupeGesteDeRetour: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Coupeur { Coupeur() }
    func updateUIViewController(_ coupeur: Coupeur, context: Context) {}

    /// Un contrôleur qui n'affiche rien et ne sert qu'à atteindre la pile de
    /// navigation qui le porte.
    ///
    /// Le geste est rendu à la disparition, et pas seulement coupé à
    /// l'apparition : il appartient à la pile entière, pas à cet écran. Oublier
    /// de le rendre le supprimerait partout ailleurs dans l'app, et le défaut
    /// ne se verrait que trois écrans plus loin.
    final class Coupeur: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}


#else

    extension View {
        /// Sur le Mac, il n'y a **rien à couper** : ni glissement de retour, ni
        /// `UINavigationController` pour le porter. La vue passe telle quelle.
        ///
        /// Écrit plutôt que borné au point d'appel : une vue qui déclare « pas
        /// de geste système ici » dit la même chose sur les deux plateformes,
        /// et c'est au design system de savoir que l'une n'a rien à faire.
        func sansGesteDeRetourSysteme() -> some View { self }
    }

#endif
