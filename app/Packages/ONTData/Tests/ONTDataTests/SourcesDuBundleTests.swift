import Foundation
import ONTKit
import Testing

@testable import ONTData

/// **Le contrat des langues sources, éprouvé sur le vrai fichier émis.**
///
/// ## Pourquoi celle-ci ne ressemble à aucune autre épreuve du paquet
///
/// Les autres décodent des chaînes JSON écrites dans le test. Elles éprouvent
/// la **traduction**, et c'est suffisant tant qu'un compilateur garde la forme :
/// `Schema.swift` est engendré depuis `pipeline/src/schema.rs`, donc un champ
/// renommé là-bas casse la compilation de l'app en nommant le fichier.
///
/// **Rien de tel ici.** Le codegen ne couvre pas `pipeline/src/sources.rs` : les
/// DTO de `SourcesFile.swift` sont écrits à la main, et une dérive de forme ne
/// casserait rien. Elle ferait décoder `nil` là où il y avait une valeur — et la
/// feuille de référence s'ouvrirait sans mots touchables, ce qui se lit
/// exactement comme un témoin qui n'étiquette pas. Aucune erreur, aucun rouge,
/// un texte inerte.
///
/// Cette épreuve est donc le seul garde-fou. Elle lit
/// `app/Resources/data/sources/` — **ce que `scripts/corpus.sh` embarque
/// réellement**, pas une copie de démonstration — et vérifie des valeurs
/// connues, comptées à la main dans le fichier.
///
/// Elle rougit si un nom de champ dérive, si un témoin disparaît du manifeste,
/// ou si la jointure mot → fiche cesse de tomber juste.
///
/// ## Ce que ça coûte, et pourquoi c'est accepté
///
/// Elle dépend d'un dossier du dépôt, hors du paquet. C'est une entorse assumée
/// à l'isolation d'un `swift test` — la seule façon d'éprouver un contrat dont
/// l'autre bout est un fichier engendré. Si le dossier manque, l'épreuve le dit
/// au lieu de passer en vert sur rien : un contrôle qui rend vert faute d'avoir
/// regardé est pire qu'un contrôle absent.
struct SourcesDuBundleTests {
    /// `app/Resources/data` — la racine du corpus tel qu'il est embarqué.
    ///
    /// Remontée depuis `#filePath` :
    /// `…/app/Packages/ONTData/Tests/ONTDataTests/<ce fichier>` → cinq crans.
    private static let ressources: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Resources/data", isDirectory: true)
    }()

    /// Un socle qui ne répond jamais : si le disque ne trouve pas le vrai
    /// fichier, l'épreuve échoue au lieu de mesurer autre chose.
    private struct SocleMuet: SourcesRepository {
        func sources(livre: String) -> SourcesDuLivre { .aucune(nil) }
        func unite(livre: String, temoin: String, unite: String) -> UniteSource? { nil }
    }

    private func depot() -> DiskSourcesRepository {
        DiskSourcesRepository(dossier: Self.ressources, socle: SocleMuet())
    }

    @Test("le corpus embarqué porte bien les langues sources")
    func lesFichiersSontLa() throws {
        let manifeste = Self.ressources.appendingPathComponent("sources/manifeste.json")
        try #require(
            FileManager.default.fileExists(atPath: manifeste.path),
            "sources/manifeste.json est absent de app/Resources/data — relancer scripts/corpus.sh"
        )
    }

    // MARK: - Le manifeste

    @Test("le manifeste nomme le témoin hébreu et son crédit littéral")
    func leTemoinHebreu() throws {
        guard case .temoins(let temoins) = depot().sources(livre: "bereshit") else {
            Issue.record("bereshit devrait porter au moins un témoin")
            return
        }
        let wlc = try #require(temoins.first { $0.cle == "he-wlc" })
        #expect(wlc.nom == "Westminster Leningrad Codex + Open Scriptures Hebrew Bible")
        #expect(wlc.langue.code == "he")
        #expect(wlc.langue.versLaGauche)
        // L'attribution est **littérale** : les licences exigent un crédit exact,
        // et l'app ne le recompose jamais. Si la phrase change dans le vault,
        // c'est ici qu'on veut le voir.
        #expect(wlc.attribution.contains("Open Scriptures Hebrew Bible, CC BY 4.0"))
        #expect(wlc.degre == nil, "le WLC est de première main")
    }

    /// **Six livres sur sept n'ont aucune source, et ce n'est pas une panne.**
    ///
    /// La phrase affichée vient du vault, mot pour mot. Une app qui la
    /// composerait dirait « texte indisponible » là où le vault explique que
    /// l'hébreu de *Yovelim* n'a laissé que des fragments à Qumrân.
    @Test("un livre sans témoin porte l'explication du vault, et sa cause")
    func unLivreSansTemoin() throws {
        guard case .aucune(let transmission) = depot().sources(livre: "yovelim") else {
            Issue.record("yovelim ne devrait porter aucun témoin")
            return
        }
        let t = try #require(transmission, "le vault doit expliquer l'absence")
        #expect(t.explication.contains("fragments à Qumrân"))
        // `fichier` — le texte existe, aucune édition n'en est réutilisable.
        // Distinct de `témoin`, où le texte lui-même est perdu : quatre des six
        // livres recevront leur source, et un rendu qui dirait « jamais » les
        // trahirait.
        #expect(t.cause == .fichier)
    }

    /// La cause est écrite **accentuée** dans le manifeste — « témoin ». Un
    /// décodage qui attendrait « temoin » tomberait sur `.autre("témoin")` et
    /// perdrait la nuance sans qu'aucune erreur ne le dise.
    @Test("la cause accentuée du manifeste tombe sur le bon cas")
    func laCauseAccentuee() throws {
        guard case .aucune(let transmission) = depot().sources(livre: "chazon-barukh") else {
            Issue.record("chazon-barukh ne devrait porter aucun témoin")
            return
        }
        #expect(try #require(transmission).cause == .temoin)
    }

    // MARK: - Le texte, mot à mot

    /// **L'épreuve centrale.** Le premier verset de la Genèse, compté à la main
    /// dans `he-wlc/bereshit.json`.
    @Test("Bereshit 1:1 se rend mot à mot, avec les fiches qu'il ouvre")
    func lePremierVerset() throws {
        let unite = try #require(
            depot().unite(livre: "bereshit", temoin: "he-wlc", unite: "bereshit-1"))
        #expect(unite.temoin.cle == "he-wlc")

        // **Par rang, jamais par numéro** — c'est l'invariant de la couche.
        let v = try #require(unite.verset(rang: 0))
        #expect(v.numero == 1, "le garde : la position 0 doit porter le numéro 1")
        #expect(v.mots.count == 7)

        // `t` porte le verset joint, avec ses espaces — ce qu'on copie.
        #expect(v.texte.hasPrefix("בְּרֵאשִׁ֖ית בָּרָ֣א"))

        let bara = try #require(v.mot(rang: 1))
        #expect(bara.texte == "בָּרָ֣א")
        #expect(bara.lemme == "1254 a")
        #expect(bara.morphologie == "HVqp3ms")
        #expect(bara.cible == .term(lemma: "bara"))

        // `אֵ֥ת` — la particule de l'accusatif. Elle est étiquetée (Strong 853)
        // mais **n'ouvre rien** : aucune fiche ONT ne lui correspond, et un mot
        // sans fiche se lit comme un mot sans fiche. Un mot qui ouvrirait la
        // fiche d'un autre se lirait, lui, comme la vérité.
        let et = try #require(v.mot(rang: 3))
        #expect(et.texte == "אֵ֥ת")
        #expect(et.lemme == "853")
        #expect(et.cible == nil)
    }

    /// **La translittération se récolte, et le champ qui la porte se garde ici.**
    ///
    /// C'est exactement la dérive que cette suite existe pour attraper. Le DTO
    /// l'a ignorée : le pipeline l'émettait, `MotPublie.translit` la portait, et
    /// `ONTSources.Mot` ne la déclarait pas. Rien ne rougissait — la feuille
    /// affichait les mots sans leur translittération, ce qui se lit exactement
    /// comme un vault qui n'en aurait pas écrit.
    ///
    /// Compté à la main dans `he-wlc/bereshit.json` : sur les sept mots du
    /// premier verset, `אֱלֹהִ֑ים` seul en porte une. L'absence des six autres
    /// est mesurée aussi — sans quoi un champ rempli au hasard passerait.
    @Test("la translittération du vault arrive jusqu'au domaine")
    func laTranslitteration() throws {
        let unite = try #require(
            depot().unite(livre: "bereshit", temoin: "he-wlc", unite: "bereshit-1"))
        let v = try #require(unite.verset(rang: 0))

        let elohim = try #require(v.mot(rang: 2))
        #expect(elohim.texte == "אֱלֹהִ֑ים")
        #expect(elohim.translitteration == "ʾelohim")

        #expect(
            v.mots.filter { $0.translitteration != nil }.count == 1,
            "un seul mot translittéré au premier verset — deux sur trois n'en portent pas"
        )
    }

    /// **Le piège que tout le reste de la couche existe pour éviter.**
    ///
    /// *Bereshit* 7 couvre deux chapitres bibliques : la numérotation repart de
    /// ¹ au second, et l'unité porte vingt-deux numéros en double. Un accès par
    /// `numero` trouverait le premier « 1 » et rendrait le mauvais verset — sur
    /// cette unité-là seulement, et sans rien dire.
    ///
    /// Mesuré sur le fichier émis : 46 versets, deux positions portant « 1 »,
    /// aux rangs 0 et 24.
    @Test("deux versets numérotés 1 dans la même unité ne se confondent pas")
    func deuxVersetsNumeroUn() throws {
        let unite = try #require(
            depot().unite(livre: "bereshit", temoin: "he-wlc", unite: "bereshit-7"))
        #expect(unite.versets.count == 46)

        let premier = try #require(unite.verset(rang: 0))
        let second = try #require(unite.verset(rang: 24))
        #expect(premier.numero == 1)
        #expect(second.numero == 1)
        #expect(premier.texte != second.texte, "deux versets distincts sous le même numéro")
        #expect(premier.texte.hasPrefix("וַיֹּ֤אמֶר"))
        #expect(second.texte.hasPrefix("וַיִּזְכֹּ֤ר"))

        // Et la preuve que l'accès par numéro se serait trompé : il n'y a
        // qu'une seule réponse possible, et elle est fausse une fois sur deux.
        #expect(unite.versets.filter { $0.numero == 1 }.count == 2)
    }

    /// Le rang d'un mot est son identité, et deux occurrences de la même forme
    /// doivent rester deux. Sans ça, un `ForEach` en ferait disparaître une.
    @Test("deux mots identiques dans un verset gardent deux identités")
    func deuxMotsIdentiques() throws {
        let unite = try #require(
            depot().unite(livre: "bereshit", temoin: "he-wlc", unite: "bereshit-1"))
        let v = try #require(unite.verset(rang: 0))
        #expect(Set(v.mots.map(\.id)).count == v.mots.count)
    }

    // MARK: - Le port, de bout en bout

    /// La question que la couche existe pour répondre : pour telle unité et
    /// telle position, le texte de chaque témoin disponible.
    @Test("un verset se demande à tous ses témoins d'un coup")
    func versetChezTousLesTemoins() throws {
        let lignes = depot().verset(livre: "bereshit", unite: "bereshit-1", rang: 0)
        // Un seul témoin embarqué aujourd'hui — l'hébreu. Le grec, le guèze et
        // le latin sont annoncés par le manifeste sans être présents, et ils ne
        // doivent pas apparaître ici : un témoin annoncé mais absent est omis,
        // jamais rendu vide.
        #expect(lignes.count == 1)
        let ligne = try #require(lignes.first)
        #expect(ligne.temoin.cle == "he-wlc")
        #expect(ligne.verset.mots.count == 7)
        #expect(ligne.id == "he-wlc#0")
    }

    @Test("un livre inconnu ne rend rien, et ne lève pas")
    func unLivreInconnu() {
        guard case .aucune(let t) = depot().sources(livre: "nexiste-pas") else {
            Issue.record("un livre absent du manifeste ne porte pas de témoin")
            return
        }
        #expect(t == nil)
        #expect(depot().unite(livre: "nexiste-pas", temoin: "he-wlc", unite: "x-1") == nil)
        #expect(depot().unite(livre: "bereshit", temoin: "grc-sblgnt", unite: "bereshit-1") == nil)
        #expect(depot().unite(livre: "bereshit", temoin: "he-wlc", unite: "bereshit-99") == nil)
    }

    // MARK: - La découpe des chemins du manifeste

    /// **Ce que cette suite ne peut pas éprouver**, et il vaut mieux l'écrire que
    /// de laisser croire le contraire : `swift test` n'a pas de bundle d'app, donc
    /// `BundleSourcesRepository` n'est jamais exercé ici. Le socle des épreuves
    /// ci-dessus est muet exprès, pour que tout passe par le vrai fichier du
    /// disque au lieu d'un repli silencieux.
    ///
    /// Reste ce qui *se* mesure sans bundle : la découpe du chemin. Le manifeste
    /// donne un chemin entier, Foundation veut un sous-dossier et un nom sans
    /// extension, et la découpe se tromperait deux fois si elle vivait aux deux
    /// points d'appel.
    ///
    /// Le second cas garde le dégât précis : un chemin sans dossier doit rendre
    /// `nil`. S'il rendait un nom nu, le paquet chercherait `bereshit.json` à la
    /// racine — et l'y trouverait, car le **livre ONT** s'y trouve, aplati par la
    /// phase de ressources. Un fichier qui existe, qui se lit, et qui n'est pas
    /// celui qu'on demandait.
    @Test("le chemin du manifeste se découpe pour le bundle")
    func decoupeDuChemin() throws {
        let d = try #require(BundleSourcesRepository.decouper("sources/he-wlc/bereshit.json"))
        #expect(d.dossier == "sources/he-wlc")
        #expect(d.nom == "bereshit")
        #expect(BundleSourcesRepository.decouper("bereshit.json") == nil)
    }
}
