import Foundation
import SwiftUI

extension AttributedString {

    /// Couper les mots en fin de ligne, dans la langue du texte.
    ///
    /// # Pourquoi ce n'est pas un réglage de mise en page
    ///
    /// **SwiftUI ne sait pas césurer.** Il n'existe aucun modificateur, et un
    /// `NSParagraphStyle.hyphenationFactor` posé sur une `AttributedString` est
    /// purement ignoré — mesuré : deux captures du même chapitre, l'une avec et
    /// l'autre sans, ne diffèrent pas **d'un seul pixel**. C'était la première
    /// implémentation, et elle avait l'air juste.
    ///
    /// La seule voie est donc d'insérer des **traits d'union conditionnels**
    /// (U+00AD) là où la langue permet de couper. Le moteur de texte s'en sert
    /// alors comme d'une permission : il coupe là s'il en a besoin, et le
    /// caractère reste invisible sinon.
    ///
    /// # Et pourquoi la langue n'est pas un détail
    ///
    /// `CFStringGetHyphenationLocationBeforeIndex` demande une locale, et les
    /// motifs de coupure lui sont propres. Sans la déclarer, un téléphone réglé
    /// en anglais couperait la prose française avec les règles anglaises.
    ///
    /// Le texte de l'ONT est français quel que soit l'appareil qui l'affiche :
    /// la locale est donc **écrite**, jamais lue du système.
    ///
    /// # Ce qu'on ne coupe pas
    ///
    /// Ni l'hébreu, ni les mots courts, ni les intraduisibles translittérés
    /// — pour eux la locale française n'a rien de juste à dire, et une coupure
    /// fausse dans un nom hébreu est pire qu'une ligne trop courte.
    public func cesuree(_ active: Bool, langue: String = "fr_FR") -> AttributedString {
        guard active else { return self }
        let locale = Locale(identifier: langue) as CFLocale
        guard CFStringIsHyphenationAvailableForLocale(locale) else { return self }

        var sortie = AttributedString()
        for run in runs {
            let morceau = self[run.range]
            let texte = String(morceau.characters)

            // Les runs qui ne relèvent pas de la langue française gardent leur
            // texte intact : ni l'hébreu, ni ce qui porte déjà une autre
            // langue déclarée.
            guard run.languageIdentifier == nil, !contientDeLHebreu(texte) else {
                sortie += morceau
                continue
            }

            var coupe = AttributedString(cesurer(texte, locale: locale))
            coupe.setAttributes(morceau.runs.first?.attributes ?? AttributeContainer())
            sortie += coupe
        }
        return sortie
    }

    /// Vrai si le texte porte un caractère du bloc hébreu.
    private func contientDeLHebreu(_ texte: String) -> Bool {
        texte.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }
    }

    /// Insère les traits d'union conditionnels d'un texte.
    ///
    /// Les points sont demandés **de la fin vers le début** : c'est le sens de
    /// `CFStringGetHyphenationLocationBeforeIndex`, qui rend le dernier point
    /// possible avant un index donné.
    private func cesurer(_ texte: String, locale: CFLocale) -> String {
        // Sous six caractères, couper coûte plus qu'il ne rapporte : on gagne
        // deux ou trois signes sur la ligne et on hache un mot que l'œil lisait
        // d'un coup.
        let minimum = 6

        var sortie = ""
        for mot in texte.split(separator: " ", omittingEmptySubsequences: false) {
            defer { sortie += " " }
            guard mot.count >= minimum else {
                sortie += mot
                continue
            }

            let s = String(mot)
            let cf = s as CFString
            let n = CFStringGetLength(cf)
            var points: Set<Int> = []
            var borne = n

            while borne > 1 {
                let point = CFStringGetHyphenationLocationBeforeIndex(
                    cf, borne, CFRangeMake(0, n), 0, locale, nil
                )
                guard point != kCFNotFound, point > 0, point < borne else { break }
                // Jamais à un ou deux signes d'un bout : une syllabe orpheline
                // en fin de ligne se lit plus mal qu'une ligne courte.
                if point >= 2 && point <= n - 3 { points.insert(point) }
                borne = point
            }

            if points.isEmpty {
                sortie += s
                continue
            }
            for (i, c) in s.enumerated() {
                if points.contains(i) { sortie.append("\u{00AD}") }
                sortie.append(c)
            }
        }

        // Le `defer` a posé une espace de trop après le dernier mot.
        if sortie.hasSuffix(" ") { sortie.removeLast() }
        return sortie
    }
}
