import ONTDesignSystem
import ONTKit
import PhotosUI
import SwiftUI

/// L'en-tête du compte — portrait, nom, bio.
///
/// **Privé aujourd'hui, profil du Qahal demain.** Personne d'autre ne voit ces
/// champs : le Qahal — le rassemblement des lecteurs — n'a pas de serveur, et
/// son onglet refuse déjà de simuler ce qui n'existe pas. Ils sont pourtant
/// écrits comme un profil, pour que le jour où il ouvre, rien ne soit à
/// ressaisir.
///
/// L'écran **le dit**. Une bio qu'on remplit sans savoir qui la lit est la
/// seule chose qu'un écran de compte ne doit pas laisser deviner.
struct EnTeteDuProfil: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.ontTheme) private var theme

    var body: some View {
        NavigationLink {
            EditeurDuProfil()
        } label: {
            HStack(spacing: 14) {
                Portrait(profil: account.profil, octets: account.portrait())

                VStack(alignment: .leading, spacing: 3) {
                    if let nom = account.profil.nomAffiche {
                        Text(nom)
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                    } else {
                        // **Pas un espace réservé vide.** Un nom manquant est
                        // une invitation, pas un défaut d'affichage.
                        Text("Ajouter votre nom")
                            .font(.headline)
                            .foregroundStyle(theme.accent)
                    }

                    let bio = account.profil.bio.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !bio.isEmpty {
                        Text(bio)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .accessibilityHint("Modifie votre profil")
    }
}

/// Le portrait, ou ce qui en tient lieu.
private struct Portrait: View {
    @Environment(\.ontTheme) private var theme
    let profil: Profil
    let octets: Data?
    var taille: CGFloat = 56

    var body: some View {
        Group {
            if let octets, let image = UIImage(data: octets) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !profil.initiales.isEmpty {
                // Les initiales plutôt qu'une silhouette dès qu'on connaît un
                // nom : c'est déjà quelqu'un.
                Text(profil.initiales)
                    .font(.system(size: taille * 0.38, weight: .medium))
                    .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ONTColors.brandInk(theme.mode))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: taille * 0.42))
                    .foregroundStyle(theme.ink.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.ink.opacity(0.08))
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// L'éditeur.
struct EditeurDuProfil: View {
    @Environment(AccountModel.self) private var account
    @Environment(\.ontTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var choix: PhotosPickerItem?
    @State private var chargeLaPhoto = false

    /// La limite de la bio.
    ///
    /// Assez pour deux ou trois phrases, trop peu pour un billet. Une bio sans
    /// borne devient une page, et une page ne se lit pas sous un portrait.
    private let bornDeLaBio = 280

    var body: some View {
        @Bindable var account = account

        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Portrait(
                            profil: account.profil, octets: account.portrait(), taille: 96)
                        PhotosPicker(selection: $choix, matching: .images) {
                            if chargeLaPhoto {
                                ProgressView()
                            } else {
                                Text(account.profil.portrait == nil ? "Ajouter une photo" : "Changer")
                                    .font(.footnote)
                            }
                        }
                        if account.profil.portrait != nil {
                            Button("Retirer", role: .destructive) {
                                account.profil.portrait = nil
                            }
                            .font(.footnote)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .ontRow()

            Section("Nom") {
                TextField("Prénom", text: $account.profil.prenom)
                    .textContentType(.givenName)
                TextField("Nom", text: $account.profil.nom)
                    .textContentType(.familyName)
            }
            .ontRow()

            Section {
                TextField("Quelques mots sur vous", text: $account.profil.bio, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: account.profil.bio) { _, nouvelle in
                        // La borne est appliquée à la frappe et non au
                        // départ : un texte qu'on tape et qui disparaît en
                        // sortant de l'écran est pire que pas de bio du tout.
                        if nouvelle.count > bornDeLaBio {
                            account.profil.bio = String(nouvelle.prefix(bornDeLaBio))
                        }
                    }
            } header: {
                Text("Bio")
            } footer: {
                Text("\(account.profil.bio.count) / \(bornDeLaBio)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .ontRow()

            Section {
                Label {
                    // **Ce que l'écran doit dire, et qu'aucun écran de compte
                    // ne dit jamais assez tôt** : qui lit ceci.
                    Text(
                        "Personne d'autre ne voit ces informations. Elles restent sur "
                            + "votre compte, et deviendront votre profil le jour où le "
                            + "Qahal — le rassemblement des lecteurs — ouvrira."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .ontRow()
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .ontScreen()
        .task(id: choix) { await recevoirLaPhoto() }
    }

    private func recevoirLaPhoto() async {
        guard let choix else { return }
        chargeLaPhoto = true
        defer { chargeLaPhoto = false }

        guard let brut = try? await choix.loadTransferable(type: Data.self),
            let image = UIImage(data: brut)
        else { return }

        // **On réduit avant d'écrire.** Une photo d'appareil moderne fait
        // plusieurs mégaoctets ; on en affiche un rond de 96 points. Garder
        // l'original coûterait le stockage du lecteur pour un détail que
        // personne ne verra jamais — et l'enverrait tel quel le jour où le
        // profil se synchronisera.
        guard let reduite = image.reduite(a: 512),
            let jpeg = reduite.jpegData(compressionQuality: 0.85)
        else { return }

        account.poserLePortrait(jpeg)
    }
}

extension UIImage {
    /// Réduit l'image pour que son plus grand côté tienne dans `cote`.
    ///
    /// Rend `self` quand elle est déjà assez petite : réencoder une image qui
    /// n'en a pas besoin lui coûte une génération de qualité pour rien.
    func reduite(a cote: CGFloat) -> UIImage? {
        let plusGrand = max(size.width, size.height)
        guard plusGrand > cote else { return self }

        let facteur = cote / plusGrand
        let cible = CGSize(width: size.width * facteur, height: size.height * facteur)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: cible, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: cible))
        }
    }
}
