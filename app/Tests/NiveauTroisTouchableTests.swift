import Foundation
import ONTDesignSystem
import ONTKit
import Testing

/// La translittération du niveau 3 ouvre sa fiche — quand elle en a une.
///
/// ## Le défaut, tel que le lecteur le rencontrait
///
/// Il lit `(*chesed* / חֶסֶד)`, il est dessus, c'est exactement le moment où il
/// veut la fiche — et rien ne répond. Le même mot, balisé `**chesed**` dans le
/// corps trente lignes plus haut, l'ouvre pourtant. L'appareil qui relie un mot
/// à sa fiche s'arrêtait au corps du texte, à l'endroit précis où on le demande.
///
/// ## Ce qui se mesure ici
///
/// **Le lien dans la chaîne composée**, et non « le nœud porte une cible » —
/// c'est le rendu que le doigt touche. Un `cible` correctement rempli et un
/// renderer qui l'ignore rendraient le premier vert et le lecteur toujours
/// bloqué : la mesure doit se prendre au dernier maillon.
@MainActor
struct NiveauTroisTouchableTests {
    private var theme: ONTTheme { ONTTheme(preferences: .default) }

    /// L'adresse portée par la run dont le texte est `mot`, s'il y en a une.
    private func adresse(de mot: String, dans noeuds: [Inline]) -> URL? {
        let chaine = ONTTextRenderer.compose(noeuds, theme: theme)
        for run in chaine.runs {
            if String(chaine[run.range].characters) == mot { return run.link }
        }
        return nil
    }

    @Test("une translittération résolue vers une entrée ouvre le terme")
    func versUnTerme() {
        let url = adresse(
            de: "chesed",
            dans: [.translit("chesed", hebrew: "חֶסֶד", cible: .term(lemma: "chesed"))])
        #expect(url?.host == "term")
        #expect(url?.lastPathComponent == "chesed")
    }

    /// **Les deux destinations ne se confondent pas.** Une fiche de Shem vit
    /// dans `shemot.json`, pas dans le glossaire : envoyer un nom propre sur
    /// `term` le ferait chercher là où il n'est pas, et la jointure échouerait
    /// en silence — le lecteur toucherait, et n'obtiendrait rien.
    @Test("une translittération résolue vers un Shem ouvre le shem")
    func versUnShem() {
        let url = adresse(
            de: "Noach",
            dans: [.translit("Noach", hebrew: "נֹחַ", cible: .shem(lemma: "noach"))])
        #expect(url?.host == "shem")
        #expect(url?.lastPathComponent == "noach")
    }

    /// **L'inertie est le cas ordinaire, et elle est voulue.** Le pipeline ne
    /// résout que l'exact ; `vayiven` vient de `banah` par une règle
    /// morphologique qu'on refuse d'écrire, parce qu'une règle qui se trompe ne
    /// rend pas le mot inerte — elle le rend touchable vers la mauvaise fiche.
    @Test("sans cible, la translittération reste inerte")
    func sansCible() {
        #expect(
            adresse(de: "vayiven", dans: [.translit("vayiven", hebrew: "וַיִּבֶן", cible: nil)])
                == nil)
    }

    /// L'hébreu reste hors du lien : il se compose en RTL, et une zone tactile
    /// à cheval sur la barre oblique traverserait deux directions d'écriture.
    @Test("seule la part latine se touche")
    func lHebreuResteHorsDuLien() {
        let noeuds: [Inline] = [
            .translit("chesed", hebrew: "חֶסֶד", cible: .term(lemma: "chesed"))
        ]
        #expect(adresse(de: "חֶסֶד", dans: noeuds) == nil)
        #expect(adresse(de: "chesed", dans: noeuds) != nil)
    }

    /// Le cas majoritaire : le niveau 3 s'écrit le plus souvent **dans** une
    /// glose de niveau 2. Un rendu qui ne le lierait qu'en surface manquerait la
    /// plupart des mots sans rien dire — il en rendrait simplement moins.
    @Test("le niveau 3 se touche jusque dans une glose")
    func dansUneGlose() {
        let url = adresse(
            de: "chesed",
            dans: [
                .gloss([.translit("chesed", hebrew: "חֶסֶד", cible: .term(lemma: "chesed"))])
            ])
        #expect(url?.host == "term")
    }
}
