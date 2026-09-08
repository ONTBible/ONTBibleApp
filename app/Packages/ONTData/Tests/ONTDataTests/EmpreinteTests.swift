import Foundation
import Testing

@testable import ONTData

/// L'empreinte d'un fichier de corpus téléchargé.
///
/// ## Le contrôle qui manquait
///
/// L'actualiseur ne vérifiait que la **taille annoncée**, et son propre
/// commentaire l'appelait « somme de contrôle du pauvre ». Elle attrape une
/// réponse tronquée ou une page d'erreur servie à la place d'un livre — pas un
/// fichier abîmé qui garde sa longueur, ni un cache qui rend le mauvais livre
/// sous le bon nom.
///
/// L'empreinte était pourtant **dans le manifeste depuis le début** : elle
/// nomme même le fichier publié, `plan.4814dcb178e2.json`. On s'en servait pour
/// savoir *si* un fichier avait changé, jamais pour savoir *si celui qu'on
/// vient de recevoir est le bon*. Deux questions, une seule donnée, une seule
/// des deux posée.
///
/// ## Ce que ces épreuves gardent vraiment
///
/// Pas « sha256 fonctionne » — ça, CryptoKit s'en charge. Elles gardent
/// **l'accord avec `corpus-publie.py`**, qui calcule
/// `hashlib.sha256(octets).hexdigest()[:12]`. Le tronquage à douze signes vient
/// de là. Si l'un des deux côtés le change seul, l'app rejettera *tout* le
/// corpus publié sans qu'aucune compilation ne bronche — c'est un contrat entre
/// deux dépôts, et il ne s'exprime dans aucun type.
struct EmpreinteTests {
    @Test("l'empreinte est un sha256 tronqué à douze signes")
    func formeDeLEmpreinte() {
        // `echo -n "" | shasum -a 256` → e3b0c44298fc1c14…
        #expect(CorpusUpdater.empreinte(Data()) == "e3b0c4429" + "8fc")
        let e = CorpusUpdater.empreinte(Data("bereshit".utf8))
        #expect(e.count == 12)
        #expect(e.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// Le cas que la taille seule ne voit pas : **même longueur, contenu
    /// différent**. C'est le seul qui justifie ce contrôle.
    @Test("deux contenus de même taille ont deux empreintes")
    func memeTailleAutreContenu() {
        let a = Data("bereshit-1-verset-01".utf8)
        let b = Data("bereshit-1-verset-02".utf8)
        #expect(a.count == b.count)
        #expect(CorpusUpdater.empreinte(a) != CorpusUpdater.empreinte(b))
    }

    /// Et un octet retourné au milieu, qui ne change ni la taille ni le début.
    @Test("un seul octet modifié change l'empreinte")
    func unOctetSuffit() {
        var abime = Data("le corpus entier, ou presque".utf8)
        abime[13] ^= 0x01
        #expect(
            CorpusUpdater.empreinte(abime)
                != CorpusUpdater.empreinte(Data("le corpus entier, ou presque".utf8))
        )
    }
}
