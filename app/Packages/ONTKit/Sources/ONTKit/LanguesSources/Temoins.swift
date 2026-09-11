import Foundation

/// **Les langues sources** — ce que le lecteur voit quand il demande à voir la
/// référence derrière un verset traduit.
///
/// Le vault porte, sous `sources/`, le texte de chaque livre dans sa langue :
/// l'hébreu de la Kenesset, deux témoins grecs pour la Berit Hadashah, le guèze
/// de *Chanokh*, le latin du *Chazon Ezra*. Le pipeline les joint aux unités ONT
/// et les émet ; ce fichier dit ce qu'ils sont **pour le domaine**, sans rien
/// savoir du JSON qui les transporte.
///
/// ## L'invariant de toute cette couche
///
/// > **Le rang est la clé, le numéro est un affichage.**
///
/// Les unités ONT ne se découpent pas comme les chapitres reçus : une
/// **parashah** peut couvrir deux chapitres bibliques, et la numérotation
/// repart alors de ¹ au second (§2.2 du vault). *Bereshit* 7 porte ainsi
/// **vingt-deux numéros en double** — deux versets « 1 », deux « 2 », jusqu'à
/// « 22 ». Mesuré sur le corpus émis, pas déduit.
///
/// Un accès par numéro s'attacherait donc aux deux, sur cette unité-là
/// seulement, et sans rien dire. C'est le défaut qui passe tous les essais sauf
/// un. `VersetSource` et `MotSource` portent donc un `rang` — leur position,
/// unique par construction — et c'est lui qui les identifie.
///
/// Le `numero`, lui, n'est pas jeté : il sert de **garde**. La liseuse peut
/// vérifier que le verset qu'elle a pris à la position *i* porte bien le numéro
/// qu'elle affiche à cette position-là.

// MARK: - La langue

/// La langue d'un témoin.
///
/// Un type plutôt qu'une chaîne nue, pour une seule raison : la question « ce
/// texte s'écrit-il de droite à gauche » est une propriété de la **langue**, et
/// si elle n'est pas répondue ici, elle sera réécrite dans chaque vue qui rend
/// du texte source — iOS, Android, le site — avec trois façons de se tromper.
///
/// **Le code reste libre**, et ce n'est pas un oubli. Une énumération fermée
/// ferait échouer le décodage du manifeste le jour où un témoin syriaque
/// arrive, pour un gain nul : le domaine n'a rien à décider sur un code qu'il
/// ne connaît pas, il a seulement à le porter.
public struct Langue: Hashable, Sendable {
    /// Le code ISO 639 tel que le manifeste l'écrit — `he`, `grc`, `gez`, `lat`.
    public let code: String

    public init(code: String) {
        self.code = code
    }

    /// Vrai pour les écritures sémitiques qui courent vers la gauche.
    ///
    /// La liste est courte et explicite plutôt que déduite : une déduction sur
    /// le code (« tout ce qui n'est pas latin ») rendrait le guèze à l'envers,
    /// alors qu'il s'écrit de gauche à droite comme le français.
    public var versLaGauche: Bool {
        Self.droiteAGauche.contains(code)
    }

    private static let droiteAGauche: Set<String> = ["he", "arc", "syr", "ar", "hbo"]
}

// MARK: - Le témoin

/// Un témoin — une édition nommée d'une langue source.
///
/// `attribution` est **la phrase exacte à afficher**, écrite dans le vault et
/// jamais recomposée par l'app. Les licences des éditions critiques exigent un
/// crédit littéral ; le composer à partir de morceaux serait l'inventer, et
/// personne ne relirait la phrase inventée.
public struct Temoin: Hashable, Sendable, Identifiable {
    /// La clé du manifeste — `he-wlc`, `grc-sblgnt`.
    public let cle: String
    public let nom: String
    public let langue: Langue
    /// Le crédit littéral, tel qu'il doit paraître sous le texte.
    public let attribution: String
    /// Ce que ce témoin est dans la chaîne de transmission — « second degré :
    /// le guèze traduit le grec, qui traduisait l'araméen ». Absent quand le
    /// témoin est de première main.
    public let degre: String?

    public init(cle: String, nom: String, langue: Langue, attribution: String, degre: String?) {
        self.cle = cle
        self.nom = nom
        self.langue = langue
        self.attribution = attribution
        self.degre = degre
    }

    public var id: String { cle }
}

// MARK: - Ce que le livre a reçu, ou n'a pas reçu

/// Pourquoi un livre n'a pas de texte source.
///
/// Les deux cas ne disent pas la même chose au lecteur, et la nuance est celle
/// que le vault tient : *perdu* n'est pas *pas encore libre*. Quatre des six
/// livres sans source recevront la leur ; un rendu qui dirait « jamais » les
/// trahirait.
///
/// `.autre` garde un cas inconnu **sans rien perdre**. Le manifeste écrit ce
/// champ en toutes lettres et en français (« témoin », « fichier ») ; une
/// énumération fermée ferait disparaître une troisième cause au lieu de la
/// montrer, et c'est précisément ce qu'on ne veut pas d'une couche qui parle de
/// transmission.
public enum CauseDeLAbsence: Hashable, Sendable {
    /// Le texte lui-même est perdu — il ne survit que dans une autre langue.
    case temoin
    /// Il existe, mais aucune édition n'en est librement réutilisable.
    case fichier
    /// Une cause que cette version de l'app ne connaît pas encore.
    case autre(String)
}

/// Ce qu'on dit au lecteur quand il n'y a pas de texte source.
///
/// `explication` vient du vault, mot pour mot. L'app ne la compose jamais : une
/// phrase composée ici serait une seconde source, qui divergerait à la première
/// correction du vault et que personne ne penserait à remettre à jour.
public struct Transmission: Hashable, Sendable {
    public let explication: String
    public let cause: CauseDeLAbsence?

    public init(explication: String, cause: CauseDeLAbsence?) {
        self.explication = explication
        self.cause = cause
    }
}

/// Ce que la couche des langues sources sait d'un livre.
///
/// **Un type somme, et pas une liste qui pourrait être vide.** Six des sept
/// livres du manifeste n'ont aujourd'hui aucun témoin : l'absence est le cas
/// ordinaire, pas la panne. Une liste vide obligerait chaque appelant à se
/// souvenir de tester `isEmpty` — et celui qui l'oublie rend un écran blanc là
/// où le vault avait une phrase à dire.
///
/// Ici l'état illégal n'existe pas : `.temoins` est garanti non vide par
/// l'adaptateur, et `.aucune` force à regarder ce qu'on affiche à la place.
public enum SourcesDuLivre: Hashable, Sendable {
    /// Au moins un témoin porte ce livre, dans l'ordre du manifeste.
    case temoins([Temoin])
    /// Aucun — et le vault dit pourquoi, quand il le dit.
    ///
    /// `nil` reste possible : rien n'oblige le manifeste à porter une
    /// explication, et en inventer une ici serait la même faute que de
    /// composer l'attribution.
    case aucune(Transmission?)

    /// Les témoins, ou rien — pour les appelants qui n'ont qu'à itérer.
    public var temoinsDisponibles: [Temoin] {
        if case .temoins(let liste) = self { return liste }
        return []
    }
}

// MARK: - Le texte

/// Un mot du texte source, et la fiche qu'il ouvre quand il en ouvre une.
///
/// ## Pourquoi `rang` plutôt que le mot lui-même comme identité
///
/// Parce qu'un mot se répète dans un verset. *Bereshit* 1:1 porte `אֵ֥ת` puis
/// `וְאֵ֥ת` — et ailleurs la même forme paraît deux fois à l'identique.
/// Identifier par le texte ferait fusionner ces occurrences dans un `ForEach`,
/// et l'une des deux disparaîtrait de l'écran sans qu'aucune erreur ne le dise.
///
/// C'est le même invariant qu'au niveau du verset, un cran plus bas.
///
/// ## Ce qui est absent, et pourquoi l'absence est un état
///
/// `lemme` et `morphologie` manquent quand le témoin n'étiquette pas.
/// `translitteration` manque quand le vault n'en a écrit aucune pour cette
/// forme — deux mots sur trois sont dans ce cas. `cible`
/// manque quand **aucune fiche ONT ne correspond** — et c'est la règle que le
/// niveau 3 a déjà payée : une jointure qui se trompe ne rend pas le mot inerte,
/// elle le rend touchable vers la mauvaise fiche, et le lecteur ne peut pas le
/// voir. Un mot sans fiche se lit comme un mot sans fiche.
public struct MotSource: Hashable, Sendable, Identifiable {
    /// La position du mot dans le verset. C'est l'identité — voir plus haut.
    public let rang: Int
    /// La forme telle qu'elle est écrite, voyelles et cantillation comprises.
    public let texte: String
    /// Le numéro de Strong, tel que le témoin l'écrit — « 430 », « b/7225 ».
    public let lemme: String?
    /// Le code morphologique du témoin — « HVqp3ms ».
    public let morphologie: String?
    /// **La translittération, telle que le vault l'a écrite** — jamais calculée.
    ///
    /// Elle est *récoltée* : `pipeline/src/sources.rs` reprend les couples
    /// `(bereshit / בְּרֵאשִׁית)` que les niveaux 3 du corpus portent déjà, et
    /// refuse ceux dont une même forme en porte deux différentes. Aucun
    /// translittérateur n'existe dans ce dépôt, et en écrire un afficherait
    /// sous les mots des formes fausses avec l'aplomb d'un fait — le lecteur
    /// n'aurait rien pour les démentir.
    ///
    /// **Absente est l'état ordinaire** : deux mots sur trois n'en portent pas.
    /// C'est l'état du vault, pas un défaut du pont.
    public let translitteration: String?
    /// La fiche que ce mot ouvre, quand il en ouvre une.
    public let cible: CibleDuNiveauTrois?

    public init(
        rang: Int,
        texte: String,
        lemme: String? = nil,
        morphologie: String? = nil,
        translitteration: String? = nil,
        cible: CibleDuNiveauTrois? = nil
    ) {
        self.rang = rang
        self.texte = texte
        self.lemme = lemme
        self.morphologie = morphologie
        self.translitteration = translitteration
        self.cible = cible
    }

    public var id: Int { rang }
}

/// Un verset dans sa langue source.
public struct VersetSource: Hashable, Sendable, Identifiable {
    /// La **position** dans l'unité. C'est la clé.
    public let rang: Int
    /// Le numéro **à afficher**. Pas une clé : il se répète dans une unité qui
    /// couvre deux chapitres bibliques. Il sert de garde — la liseuse vérifie
    /// que le verset pris à la position *i* porte bien le numéro qu'elle
    /// affiche à cette position-là.
    public let numero: Int
    /// Le verset entier, joint.
    ///
    /// **Ce n'est pas une redondance avec `mots`.** Il porte la ponctuation et
    /// les espaces que la liste de mots perd, et c'est lui qu'on copie ou qu'on
    /// lit à voix haute. La liste, elle, est ce qu'on touche.
    public let texte: String
    /// Le verset mot à mot. **Vide quand le témoin n'étiquette pas** — le guèze
    /// de Dillmann, par exemple. La liseuse rend alors le verset sans mots
    /// touchables, ce qui est exact : il n'y a rien à ouvrir.
    public let mots: [MotSource]

    public init(rang: Int, numero: Int, texte: String, mots: [MotSource] = []) {
        self.rang = rang
        self.numero = numero
        self.texte = texte
        self.mots = mots
    }

    public var id: Int { rang }

    /// Le mot à une position donnée, ou `nil` hors bornes.
    public func mot(rang: Int) -> MotSource? {
        mots.indices.contains(rang) ? mots[rang] : nil
    }
}

/// Le texte d'une unité chez un témoin.
///
/// Le témoin voyage **avec** le texte plutôt qu'à côté : l'attribution doit
/// paraître sous ce qu'elle crédite, et la séparer obligerait chaque écran à
/// refaire la jointure avec le manifeste — jusqu'à celui qui l'oubliera.
public struct UniteSource: Hashable, Sendable, Identifiable {
    public let temoin: Temoin
    /// L'unité ONT — `bereshit-7`.
    public let unite: String
    /// Les versets **dans l'ordre**. L'index est le `rang`.
    public let versets: [VersetSource]

    public init(temoin: Temoin, unite: String, versets: [VersetSource]) {
        self.temoin = temoin
        self.unite = unite
        self.versets = versets
    }

    public var id: String { "\(temoin.cle)#\(unite)" }

    /// Le verset à une position donnée, ou `nil` hors bornes.
    ///
    /// **Positionnel, jamais par numéro** — c'est l'invariant de l'en-tête. Un
    /// `first { $0.numero == n }` compilerait, marcherait partout, et rendrait
    /// le mauvais verset sur les unités à deux chapitres.
    public func verset(rang: Int) -> VersetSource? {
        versets.indices.contains(rang) ? versets[rang] : nil
    }
}

/// Un verset chez un témoin — une ligne de la feuille de référence.
///
/// C'est ce que la liseuse itère quand elle ouvre un verset : l'hébreu, puis le
/// grec, chacun sous son crédit. Un type plutôt qu'un couple `(Temoin,
/// VersetSource)`, parce qu'un `ForEach` a besoin d'une identité — et que
/// celle-ci tient les deux moitiés ensemble sans que l'appelant la fabrique.
public struct VersetChezUnTemoin: Hashable, Sendable, Identifiable {
    public let temoin: Temoin
    public let verset: VersetSource

    public init(temoin: Temoin, verset: VersetSource) {
        self.temoin = temoin
        self.verset = verset
    }

    public var id: String { "\(temoin.cle)#\(verset.rang)" }
}
