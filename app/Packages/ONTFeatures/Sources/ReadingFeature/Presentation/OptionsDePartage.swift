import ONTDesignSystem
import ONTKit
import SwiftUI

/// Ce qu'un passage partagé emporte — et son aperçu, qui change en direct.
///
/// **L'aperçu est ce qui rend l'écran utile.** Cinq bascules sans lui
/// obligeraient à imaginer le résultat, puis à sortir de l'app pour le
/// vérifier, puis à revenir. Avec lui, on voit la forme se faire.
///
/// Il appelle **exactement** la fonction qui compose un vrai partage, sur un
/// passage d'exemple. Une imitation dériverait au premier changement de
/// règle — et la dérive ne se verrait que le jour où quelqu'un partagerait
/// vraiment.
public struct OptionsDePartage: View {
    @Environment(ReadingModel.self) private var model
    @Environment(\.ontTheme) private var theme

    public init() {}

    /// Le passage d'exemple.
    ///
    /// Les premiers versets de *Bereshit*, écrits ici plutôt que tirés du
    /// corpus : l'écran doit rendre la même chose pour tout le monde, y compris
    /// avant qu'un livre soit chargé, et un exemple qui varie ferait comparer
    /// deux formes en croyant comparer deux réglages.
    private let exemple = [
        Partage.Morceau(numero: 1, texte: "Quand Elohim commença à orchestrer les Cieux et la Terre"),
        Partage.Morceau(numero: 2, texte: "la Terre était informe et vide."),
    ]

    public var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Numéros de versets", isOn: $model.preferences.partage.numerosDeVersets)
                Toggle("Versets à la suite", isOn: $model.preferences.partage.versetsALaSuite)
                Toggle("Guillemets", isOn: $model.preferences.partage.guillemets)
                Toggle("Nom de l'application", isOn: $model.preferences.partage.nomDeLApp)
            } header: {
                Text("La forme")
            }
            .ontRow()

            Section {
                Toggle("Lien vers ontbible.com", isOn: $model.preferences.partage.lien)
            } footer: {
                // **Ce que le lien coûte et ce qu'il rapporte**, dit une fois,
                // parce que c'est la seule bascule dont l'effet dépasse la
                // typographie.
                Text(
                    "Le lien ouvre le passage entier dans un navigateur, pour qui n'a "
                        + "pas l'application. Dans un message à un proche, il encombre "
                        + "autant qu'il sert."
                )
            }
            .ontRow()

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(apercu)
                        .font(.callout)
                        .foregroundStyle(theme.ink)
                        .textSelection(.enabled)
                        .animation(.snappy(duration: 0.16), value: apercu)

                    if model.preferences.partage.lien {
                        Text("https://ontbible.com/fr/lire/bereshit/bereshit-1?v=1-2")
                            .font(.footnote)
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
                // Le tout d'un bloc pour VoiceOver : lu élément par élément,
                // l'aperçu se hacherait en fragments sans rapport.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Aperçu du partage. \(apercu)")
            } header: {
                Text("Aperçu")
            } footer: {
                Text(
                    "Le lien voyage à part : votre application de messagerie en fait "
                        + "un aperçu, au lieu d'une adresse noyée dans le texte."
                )
            }
            .ontRow()
        }
        .navigationTitle("Options de partage")
        .ontTitreCompact()
        .ontScreen()
    }

    private var apercu: String {
        Partage.composer(
            exemple, reference: "Bereshit 1:1-2", reglages: model.preferences.partage)
    }
}
