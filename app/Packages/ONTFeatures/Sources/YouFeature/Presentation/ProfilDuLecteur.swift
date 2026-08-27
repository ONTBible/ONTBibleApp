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

                    // L'arobase sous le nom, en accent : c'est un identifiant,
                    // pas une description, et rien d'autre sur cet écran n'en
                    // est un.
                    if let arobase = account.profil.arobase {
                        Text(arobase)
                            .font(.subheadline)
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
    @State private var parcourtLesFichiers = false
    @State private var refus: String?

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
                        if chargeLaPhoto {
                            ProgressView()
                        } else {
                            // **Deux origines, et l'une ne remplace pas
                            // l'autre.** La photothèque tient les photos ; un
                            // portrait dessiné, reçu par message ou rangé dans
                            // iCloud Drive n'y est pas, et rien ne l'y fera
                            // entrer. Le lecteur qui l'a sous la main n'aurait
                            // eu aucun chemin.
                            HStack(spacing: 18) {
                                PhotosPicker(selection: $choix, matching: .images) {
                                    Label("Photothèque", systemImage: "photo.on.rectangle")
                                        .font(.footnote)
                                }
                                Button {
                                    parcourtLesFichiers = true
                                } label: {
                                    Label("Fichiers", systemImage: "folder")
                                        .font(.footnote)
                                }
                            }
                        }
                        if account.profil.portrait != nil {
                            Button("Retirer", role: .destructive) {
                                account.profil.portrait = nil
                            }
                            .font(.footnote)
                        }
                        if let refus {
                            Text(refus)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .ontRow()

            Section {
                HStack(spacing: 2) {
                    // **L'arobase est dessinée, pas tapée.** Elle appartient à
                    // l'affichage et non à la donnée : la laisser dans le champ
                    // ferait qu'un jour quelqu'un enregistrerait `@@gloiiire_`.
                    Text("@")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("nomdusage", text: $account.profil.nomDUsage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profil.nomDUsage")
                        .accessibilityLabel("Nom d'usage")
                        .onChange(of: account.profil.nomDUsage) { _, saisie in
                            // **Replié à la frappe, pas à la validation.**
                            // Refuser après coup un nom qu'on vient de taper en
                            // entier oblige à tout reprendre ; l'écarter au
                            // moment où il s'écrit fait sentir la règle sans
                            // jamais l'énoncer.
                            let replie = NomDUsage.replier(saisie)
                            if replie != saisie { account.profil.nomDUsage = replie }
                        }
                }
            } header: {
                Text("Nom d'usage")
            } footer: {
                // Le reproche ne paraît que s'il y a quelque chose à reprocher,
                // et il nomme ce qui manque — jamais la règle entière.
                if let reproche = NomDUsage.reproche(account.profil.nomDUsage) {
                    Text(reproche).foregroundStyle(.red)
                } else {
                    Text("Ce par quoi les autres lecteurs vous nommeront, au Qahal.")
                }
            }
            .ontRow()

            Section("Nom") {
                // **Un identifiant stable, et non l'invite.**
                //
                // L'invite disparaît dès que le champ est rempli : un relevé
                // qui la cherche trouve le champ vide et le perd rempli. C'est
                // ce qui a fait échouer le test d'interface, et ça vaudrait
                // pour n'importe quel outil d'automatisation.
                TextField("Prénom", text: $account.profil.prenom)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("profil.prenom")
                TextField("Nom", text: $account.profil.nom)
                    .textContentType(.familyName)
                    .accessibilityIdentifier("profil.nom")
            }
            .ontRow()

            Section {
                TextField("Quelques mots sur vous", text: $account.profil.bio, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("profil.bio")
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
        .fileImporter(
            isPresented: $parcourtLesFichiers,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { resultat in
            recevoirLeFichier(resultat)
        }
    }

    /// Un fichier choisi dans **Fichiers** — iCloud Drive, Téléchargements, un
    /// dossier d'app tierce.
    ///
    /// `startAccessingSecurityScopedResource` n'est pas une formalité : hors du
    /// bac à sable, l'URL rendue par le sélecteur ne s'ouvre pas sans elle, et
    /// l'échec est un simple `nil` qu'on prendrait pour un fichier illisible.
    private func recevoirLeFichier(_ resultat: Result<[URL], Error>) {
        refus = nil
        guard case .success(let urls) = resultat, let url = urls.first else { return }

        let ouvert = url.startAccessingSecurityScopedResource()
        defer { if ouvert { url.stopAccessingSecurityScopedResource() } }

        guard let brut = try? Data(contentsOf: url), let image = UIImage(data: brut) else {
            refus = "Ce fichier n'est pas une image lisible."
            return
        }
        poser(image)
    }

    private func recevoirLaPhoto() async {
        guard let choix else { return }
        refus = nil
        chargeLaPhoto = true
        defer { chargeLaPhoto = false }

        guard let brut = try? await choix.loadTransferable(type: Data.self),
            let image = UIImage(data: brut)
        else { return }
        poser(image)
    }

    private func poser(_ image: UIImage) {

        // **On réduit avant d'écrire.** Une photo d'appareil moderne fait
        // plusieurs mégaoctets ; on en affiche un rond de 96 points. Garder
        // l'original coûterait le stockage du lecteur pour un détail que
        // personne ne verra jamais — et le ferait monter tel quel à la
        // synchronisation.
        guard let reduite = image.reduite(a: 512),
            let jpeg = reduite.sousLaBorne(ONTPortrait.borne)
        else {
            refus = "Cette image n'a pas pu être préparée."
            return
        }

        account.poserLePortrait(jpeg)
    }
}

/// Ce que le serveur admet pour un portrait.
enum ONTPortrait {
    /// La borne en octets **avant** encodage.
    ///
    /// Le serveur admet 150 Kio de base64, et le base64 enfle d'un tiers : on
    /// s'arrête donc à 110 Kio de JPEG. Écrire la borne du serveur ici sans
    /// compter cette inflation ferait refuser des images qui paraissent tenir.
    static let borne = 100 * 1024
}

extension UIImage {
    /// Encode en JPEG sous une borne, en baissant la qualité s'il le faut.
    ///
    /// On ne réduit **pas** les dimensions une seconde fois : elles ont déjà
    /// été choisies pour l'affichage, et les rogner encore rendrait le portrait
    /// flou sur les écrans à trois points par pixel. C'est la qualité qui cède,
    /// parce qu'un portrait de 96 points la pardonne.
    func sousLaBorne(_ borne: Int) -> Data? {
        for qualite in stride(from: 0.85, through: 0.35, by: -0.1) {
            guard let donnees = jpegData(compressionQuality: qualite) else { continue }
            if donnees.count <= borne { return donnees }
        }
        // Une image qui résiste à 0,35 est pathologique — un bruit de fond
        // photographique, que le JPEG ne sait pas compresser. On la réduit
        // alors vraiment, plutôt que de la refuser.
        return reduite(a: 256)?.jpegData(compressionQuality: 0.6)
    }

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
