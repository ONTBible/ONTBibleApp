#if canImport(UIKit)
    import ONTKit
    import UIKit

    /// **Les raccourcis de l'icône** — ce que l'appui long sur l'app propose.
    ///
    /// ## Dynamiques, et c'est tout l'intérêt
    ///
    /// Déclarés dans `Info.plist`, ils seraient figés : « Reprendre » n'aurait
    /// pas de passage à nommer, et proposerait la lecture à quelqu'un qui n'a
    /// jamais rien lu. Posés au moment où l'app s'efface, ils portent
    /// ==l'endroit réel où le lecteur s'est arrêté== — « Bereshit 17 », pas
    /// « Reprendre ».
    ///
    /// Le moment compte : iOS lit cette liste quand l'écran d'accueil la
    /// montre, donc **après** que l'app a quitté le premier plan. La poser au
    /// lancement la rendrait vraie une fois, puis périmée à chaque lecture.
    ///
    /// ## Chacun porte son `ont://`
    ///
    /// Un raccourci ne transporte qu'un type et un dictionnaire. On y range
    /// l'URL, et `Router.open` fait le reste — ==le même chemin que le widget,
    /// que les liens universels et que le sommaire==.
    ///
    /// L'alternative aurait été un second aiguillage, avec ses propres cas et
    /// ses propres oublis. C'est la raison pour laquelle `ont://onglet/…`
    /// vient d'être ajouté plutôt qu'une navigation à part.
    ///
    /// ## Trois, choisis par l'auteur
    ///
    /// « Verset du jour, Reprendre, Bible — déjà pour commencer », le
    /// 29 septembre 2026. iOS en montre quatre au maximum et coupe au-delà
    /// sans le dire ; il reste donc une place pour la suite.
    ///
    /// **Ni l'un ni l'autre ne paraît s'il ne peut pas aboutir** : « Reprendre »
    /// demande une position enregistrée, « Verset du jour » demande un corpus
    /// qui en porte un. ==Un raccourci qui ouvre sur rien fait croire que le
    /// geste a raté==, et c'est la règle déjà tenue pour les fournisseurs de
    /// connexion.
    ///
    /// Le verset du jour est tiré par `DailySelection.verse(for:in:)` — **le
    /// même choix que le widget**, donc les deux ouvrent le même passage le
    /// même jour. Le recalculer autrement ici les aurait fait diverger un
    /// jour sur deux sans que rien ne le dise.
    enum RaccourcisDeLIcone {
        /// La clé sous laquelle l'URL voyage.
        static let cleDeLUrl = "ont.url"

        /// Rafraîchit la liste depuis l'état courant.
        @MainActor
        static func poser(position: ReadingPosition?, versetDuJour: DailyVerse?) {
            var items: [UIApplicationShortcutItem] = []

            if let versetDuJour {
                items.append(
                    raccourci(
                        type: "verset-du-jour",
                        titre: "Verset du jour",
                        sousTitre: versetDuJour.r,
                        symbole: "sun.horizon",
                        url: "ont://read/\(versetDuJour.bookId)/\(versetDuJour.chapterId)"
                            + "?v=\(versetDuJour.n)"
                    )
                )
            }

            if let position {
                items.append(
                    raccourci(
                        type: "reprendre",
                        titre: "Reprendre",
                        sousTitre: "\(position.chapterTitle) · \(position.verse)",
                        symbole: "arrow.turn.down.right",
                        url: "ont://read/\(position.bookId)/\(position.chapterId)"
                            + "?v=\(position.verse)"
                    )
                )
            }

            items.append(
                raccourci(
                    type: "bible", titre: "La Bible", sousTitre: "le sommaire",
                    symbole: "book.closed.fill", url: "ont://onglet/bible"
                )
            )

            UIApplication.shared.shortcutItems = Array(items.prefix(4))
        }

        private static func raccourci(
            type: String, titre: String, sousTitre: String?,
            symbole: String, url: String
        ) -> UIApplicationShortcutItem {
            UIApplicationShortcutItem(
                type: type,
                localizedTitle: titre,
                localizedSubtitle: sousTitre,
                icon: UIApplicationShortcutIcon(systemImageName: symbole),
                userInfo: [cleDeLUrl: url as NSString]
            )
        }

        /// L'URL d'un raccourci touché, ou `nil` si l'on ne sait pas la lire.
        ///
        /// `nil` plutôt qu'un repli : ouvrir la Bible parce qu'on n'a pas
        /// compris le raccourci ferait croire que le geste a marché.
        static func url(de item: UIApplicationShortcutItem) -> URL? {
            guard let brut = item.userInfo?[cleDeLUrl] as? String else { return nil }
            return URL(string: brut)
        }
    }

    /// **Le passe-plat entre le delegate et la vue.**
    ///
    /// ## Pourquoi il faut ce détour
    ///
    /// Le premier jet appelait `UIApplication.shared.open(url)` depuis le
    /// delegate, pour réutiliser `onOpenURL` de la racine. ==iOS refuse
    /// d'ouvrir une app par son propre schéma== : l'appel rend `true`, la
    /// complétion s'exécute, et **rien ne se passe**. Les trois raccourcis
    /// paraissaient et n'ouvraient rien.
    ///
    /// Relevé par l'auteur le 29 septembre 2026 — « ils sont là, mais
    /// n'ouvrent rien ». L'échec est muet : aucune erreur, aucun journal, et
    /// la valeur de retour dit le contraire de ce qui s'est produit.
    ///
    /// ## Pourquoi une boîte et non un appel direct
    ///
    /// Un `UIApplicationDelegate` n'a pas de routeur sous la main : celui-ci
    /// vit dans l'environnement SwiftUI, construit par la scène. La boîte est
    /// le point où les deux se rejoignent — le delegate dépose, la racine
    /// relève.
    ///
    /// Elle est lue **deux fois** : à l'apparition de la racine et à chaque
    /// changement. Le premier cas couvre le démarrage à froid, où le delegate
    /// dépose avant que la vue existe ; le second, l'app déjà ouverte. ==Ne
    /// lire qu'au changement perdrait tous les lancements depuis l'écran
    /// d'accueil==, qui sont précisément ceux que le raccourci sert.
    @MainActor
    @Observable
    public final class RaccourciEnAttente {
        public static let partage = RaccourciEnAttente()

        /// Ce qu'un raccourci a demandé et que personne n'a encore ouvert.
        public private(set) var url: URL?

        private init() {}

        func deposer(_ url: URL) { self.url = url }

        /// Rend l'URL en attente **et la retire** — un raccourci s'honore une
        /// fois. La garder rouvrirait le même passage à chaque retour au
        /// premier plan.
        public func relever() -> URL? {
            defer { url = nil }
            return url
        }
    }
#endif
