import Testing

@testable import ONTKit

/// Le nom d'usage — le seul champ du profil qui **désigne** au lieu de décrire.
struct NomDUsageTests {
    @Test("les majuscules se replient")
    func lesMajuscules() {
        // `@Gloire` et `@gloire` désigneraient deux personnes alors qu'on lit
        // le même mot.
        #expect(NomDUsage.replier("Gloiiire_") == "gloiiire_")
    }

    /// Le lecteur le tape par habitude ; il n'appartient pas au nom.
    @Test("l'arobase de tête est absorbée")
    func lArobase() {
        #expect(NomDUsage.replier("@gloiiire_") == "gloiiire_")
    }

    /// **Les accents ne se replient pas en leur lettre nue**, ils tombent.
    /// Sinon `@rené` et `@rene` désigneraient la même personne sans qu'on
    /// l'ait dit nulle part.
    @Test("accents, espaces et ponctuation ne passent pas")
    func ceQuiNePassePas() {
        #expect(NomDUsage.replier("ré né") == "rn")
        #expect(NomDUsage.replier("a-b!c") == "abc")
    }

    @Test("un point ne peut ni ouvrir ni se doubler")
    func lesPoints() {
        #expect(NomDUsage.replier(".gloire") == "gloire")
        #expect(NomDUsage.replier("a..b") == "a.b")
        #expect(NomDUsage.replier("a.b.c") == "a.b.c")
    }

    @Test("la saisie s'arrête à la borne")
    func laBorne() {
        let long = String(repeating: "a", count: 50)
        #expect(NomDUsage.replier(long).count == NomDUsage.maximum)
    }

    /// **Bien formé et trop court sont deux choses.** Replier deux lettres rend
    /// deux lettres, et c'est correct : c'est en validant qu'on refuse, jamais
    /// en tapant — sans quoi le lecteur ne pourrait pas taper la première
    /// lettre de son nom.
    @Test("valider n'est pas replier")
    func validerNEstPasReplier() {
        #expect(NomDUsage.replier("ab") == "ab")
        #expect(!NomDUsage.valide("ab"))
        #expect(NomDUsage.valide("abc"))
        #expect(!NomDUsage.valide("Abc"))
        #expect(!NomDUsage.valide("abc."))
    }

    /// Le reproche nomme **ce qui manque**, pas la règle entière.
    @Test("le reproche vise juste, et se tait sur un champ vide")
    func leReproche() {
        #expect(NomDUsage.reproche("") == nil)
        #expect(NomDUsage.reproche("ab") == "Au moins 3 signes.")
        #expect(NomDUsage.reproche("abc.") == "Ne peut pas finir par un point.")
        #expect(NomDUsage.reproche("gloiiire_") == nil)
    }
}
