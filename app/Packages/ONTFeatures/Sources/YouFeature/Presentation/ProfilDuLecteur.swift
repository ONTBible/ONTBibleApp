import ONTDesignSystem
import ONTKit
import CryptoKit
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
                            .font(ONTUI.headline)
                            .foregroundStyle(theme.ink)
                    } else {
                        // **Pas un espace réservé vide.** Un nom manquant est
                        // une invitation, pas un défaut d'affichage.
                        Text("Ajouter votre nom")
                            .font(ONTUI.headline)
                            .foregroundStyle(theme.accent)
                    }

                    // L'arobase sous le nom, en accent : c'est un identifiant,
                    // pas une description, et rien d'autre sur cet écran n'en
                    // est un.
                    if let arobase = account.profil.arobase {
                        Text(arobase)
                            .font(ONTUI.subheadline)
                            .foregroundStyle(theme.accent)
                    }

                    // **Par quoi on s'est connecté**, dit par son logo.
                    //
                    // Sur la même ligne que l'adresse et non au-dessus : c'est
                    // une **qualification** de cette adresse — celle-ci vient
                    // d'Apple —, pas un renseignement de plus. Séparés, ils se
                    // liraient comme deux faits sans rapport.
                    if let session = account.session {
                        HStack(spacing: 5) {
                            if let fournisseur = session.provider {
                                Image(systemName: logo(fournisseur))
                                    .font(ONTUI.caption2)
                                    .accessibilityLabel("Connecté avec \(fournisseur.label)")
                            }
                            // **Pas de `.font` ici.** `ONTUI.ligneDeListe`
                            // vaut `nil` sur iOS, et `.font(nil)` ne veut pas
                            // dire « hérite » : il veut dire ==réinitialise au
                            // défaut du système==. Posé ici, il révoquait le
                            // `caption` de la ligne — le logo restait en
                            // `caption2` et le mot d'à côté remontait à la
                            // taille du corps. « Apple » s'affichait deux fois
                            // plus gros que son propre logo.
                            //
                            // Relevé par l'auteur le 22 septembre 2026 :
                            // « le Apple à côté du logo Apple est écrit en trop
                            // gros, y a un problème de cohérence de taille ».
                            if let adresse = session.email {
                                Text(adresse)
                            } else if let fournisseur = session.provider {
                                // L'adresse n'arrive qu'avec le serveur
                                // déployé. Le nom du fournisseur tient lieu
                                // d'information en attendant — il est vrai, et
                                // c'est ce que la question demandait.
                                Text(fournisseur.label)
                            }
                        }
                        .font(ONTUI.caption)
                        .foregroundStyle(.secondary)
                    }

                    let bio = account.profil.bio.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !bio.isEmpty {
                        Text(bio)
                            .font(ONTUI.footnote)
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

/// Le glyphe du fournisseur.
///
/// Les symboles du système plutôt que des logos de marque : Apple interdit de
/// redessiner le sien, et embarquer trois images pour trois glyphes qui
/// existent déjà coûterait la moitié d'un mégaoctet et une revue de licence.
private func logo(_ provider: AuthProvider) -> String {
    switch provider {
    case .apple: "apple.logo"
    case .google: "g.circle.fill"
    case .github: "chevron.left.forwardslash.chevron.right"
    }
}

/// Le portrait, ou ce qui en tient lieu.
///
/// **Public parce qu'il paraît maintenant hors du compte** : en bas de la barre
/// latérale de l'iPad, et dans l'onglet de l'iPhone. Le trois-temps — la photo,
/// les initiales, la silhouette — doit être le même partout, sinon le lecteur
/// se voit d'une façon dans un écran et d'une autre ailleurs.
/// Le portrait **avec sa pastille d'appareil photo** — l'étiquette du menu.
///
/// Séparée de `Portrait` parce que ce n'est pas le même objet : `Portrait` est
/// une **image de quelqu'un**, employée dans une ligne de liste, dans la barre
/// d'onglets et dans une carte. Celle-ci est une **commande**, et la pastille
/// est ce qui le dit. Les confondre mettrait un appareil photo partout où l'on
/// montre une tête.
struct PortraitTouchable: View {
    @Environment(\.ontTheme) private var theme
    let profil: Profil
    let octets: Data?
    let charge: Bool

    var body: some View {
        // **144 points**, à mi-chemin des deux essais. Il faisait 96, le
        // doublement demandé l'a porté à 192 — « c'est trop gros », et
        // l'auteur a tranché pour l'entre-deux le 22 septembre 2026.
        //
        // Ce n'est pas un compromis mou : à 192 le portrait devenait le sujet
        // de l'écran, alors que l'écran sert à **modifier** un profil, pas à
        // le contempler. À 96 il était une vignette. 144 le donne à voir sans
        // lui laisser prendre la page.
        //
        // Et il reste sous la borne : on réduit les images à 512 px avant de
        // les écrire, 144 points font 432 px sur un écran ×3. ==L'image est
        // donc rendue en deçà de sa définition==, ce qui n'était plus vrai à
        // 192.
        Portrait(profil: profil, octets: octets, taille: 144)
            .overlay(alignment: .bottom) {
                // La pastille chevauche le bord bas du rond, comme dans Apple
                // Music : posée à l'intérieur elle mangerait le visage, posée
                // à l'extérieur elle se lirait comme un bouton séparé.
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ONTColors.onBrandAccent(theme.mode))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(ONTColors.brandInk(theme.mode)))
                    .overlay(Circle().stroke(theme.background, lineWidth: 4))
                    .offset(y: 10)
            }
            .overlay {
                if charge {
                    Circle().fill(.black.opacity(0.35))
                    ProgressView().tint(.white)
                }
            }
            .frame(height: 154, alignment: .top)
            .contentShape(.circle)
    }
}

public struct Portrait: View {
    @Environment(\.ontTheme) private var theme
    let profil: Profil
    let octets: Data?
    var taille: CGFloat = 56

    public init(profil: Profil, octets: Data?, taille: CGFloat = 56) {
        self.profil = profil
        self.octets = octets
        self.taille = taille
    }

    public var body: some View {
        Group {
            if let octets, let image = ONTImage(data: octets) {
                Image(ontImage: image)
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
    @State private var choisitDansLaPhototheque = false
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
                        // **Le portrait est le bouton.**
                        //
                        // Les deux origines étaient posées côte à côte sous
                        // l'image, en toutes lettres — « Photothèque » et
                        // « Fichiers ». À deux elles tenaient déjà mal sur la
                        // largeur ; une troisième n'entrait pas, et c'est
                        // exactement ce que Gravatar demandait d'ajouter.
                        //
                        // ==Une liste horizontale de verbes ne s'agrandit
                        // pas== : chaque origine de plus la rapproche du bord,
                        // et le libellé rétrécit jusqu'à mentir sur ce qu'il
                        // ouvre.
                        //
                        // Un menu, lui, s'allonge. C'est la forme qu'emploie
                        // Apple Music pour la même décision, et celle que
                        // l'auteur a demandée le 22 septembre 2026 : « c'est
                        // plutôt un bouton, un menu comme ça qui apparaît ».
                        // La pastille d'appareil photo dit que l'image se
                        // touche — sans elle, rien ne l'annoncerait.
                        Menu {
                            Button {
                                choisitDansLaPhototheque = true
                            } label: {
                                Label("Photothèque", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                parcourtLesFichiers = true
                            } label: {
                                Label("Fichiers", systemImage: "folder")
                            }
                            // **Seulement si l'adresse est connue.** Gravatar
                            // ne répond qu'à une empreinte d'adresse ; sans
                            // elle il n'y a rien à demander, et un bouton qui
                            // ne peut pas aboutir n'a rien à faire dans un
                            // menu — c'est la règle déjà tenue pour les
                            // fournisseurs de connexion.
                            if adresseDuCompte != nil {
                                Button {
                                    Task { await importerDeGravatar() }
                                } label: {
                                    Label("Importer depuis Gravatar", systemImage: "at.circle")
                                }
                            }
                            if account.profil.portrait != nil {
                                Divider()
                                // **Le rôle rougit le mot, pas le glyphe.**
                                //
                                // `role: .destructive` peint le libellé en
                                // rouge, et laisse l'icône prendre la teinte
                                // courante — le bordeaux de l'app. La ligne
                                // disait donc deux choses à la fois : un
                                // avertissement à droite, une action ordinaire
                                // à gauche.
                                //
                                // `.tint(.red)` porte la teinte à l'icône.
                                // Relevé par l'auteur le 22 septembre 2026.
                                Button(role: .destructive) {
                                    account.profil.portrait = nil
                                } label: {
                                    Label("Retirer la photo", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        } label: {
                            PortraitTouchable(
                                profil: account.profil,
                                octets: account.portrait(),
                                charge: chargeLaPhoto
                            )
                        }
                        .accessibilityLabel("Changer la photo de profil")

                        if let refus {
                            Text(refus)
                                .font(ONTUI.caption)
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
                        .font(ONTUI.ligneDeListe)
                    TextField("nomdusage", text: $account.profil.nomDUsage)
                        .ontSansCapitaleAutomatique()
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
                    .font(ONTUI.enteteDeListe)
            } footer: {
                // Le reproche ne paraît que s'il y a quelque chose à reprocher,
                // et il nomme ce qui manque — jamais la règle entière.
                if let reproche = NomDUsage.reproche(account.profil.nomDUsage) {
                    Text(reproche).foregroundStyle(.red)
                        .font(ONTUI.piedDeListe)
                } else {
                    Text("Ce par quoi les autres lecteurs vous nommeront, au Qahal.")
                        .font(ONTUI.piedDeListe)
                }
            }
            .ontRow()

            Section(header: Text("Nom").font(ONTUI.enteteDeListe)) {
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
                TextField("vous@exemple.com", text: $account.profil.courriel)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profil.courriel")
            } header: {
                Text("Adresse courriel")
                    .font(ONTUI.enteteDeListe)
            } footer: {
                // **Dire ce que l'adresse fait aujourd'hui, pas ce qu'elle
                // fera.** Une explication qui annonce des courriels que rien
                // n'envoie encore est une promesse, et une promesse dans un
                // pied de section se lit comme un fait.
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Sert à retrouver votre portrait sur Gravatar. Elle reste "
                            + "sur cet appareil."
                    )
                    if adresseInvalide {
                        Text("Cette adresse ne ressemble pas à une adresse courriel.")
                            .foregroundStyle(.red)
                    }
                }
                .font(ONTUI.piedDeListe)
            }
            .ontRow()

            // **Le consentement n'apparaît qu'avec une adresse.**
            //
            // Un interrupteur qui accepte des courriels sans adresse où les
            // envoyer recueillerait un accord sur rien. Et il resterait allumé
            // après que le lecteur a effacé son adresse — un consentement qui
            // survit à son objet est un consentement qu'on ne peut plus
            // rattacher à personne.
            if !account.profil.courriel.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            {
                Section {
                    Toggle("Me prévenir des parutions", isOn: consentementAuxCourriels)
                        .accessibilityIdentifier("profil.courriels")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "Un courriel quand une unité paraît ou qu'une traduction "
                                + "est révisée. Jamais rien d'autre, et vous pouvez "
                                + "éteindre cet interrupteur à tout moment."
                        )
                        // **La date se montre.** Le RGPD demande de pouvoir
                        // prouver un consentement ; la moindre des choses est
                        // que le lecteur voie ce qu'il a accepté, et quand.
                        if let quand = account.profil.courrielsConsentis {
                            Text("Accepté le \(quand.formatted(date: .long, time: .shortened)).")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(ONTUI.piedDeListe)
                }
                .ontRow()
            }

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
                    .font(ONTUI.enteteDeListe)
            } footer: {
                Text("\(account.profil.bio.count) / \(bornDeLaBio)")
                    .font(ONTUI.caption2.monospacedDigit())
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
                    .font(ONTUI.footnote)
                    .foregroundStyle(.secondary)
                        .font(ONTUI.ligneDeListe)
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .ontRow()
        }
        .ontFormulaire()
        .navigationTitle("Profil")
        .ontTitreCompact()
        .ontScreen()
        .task(id: choix) { await recevoirLaPhoto() }
        // Le sélecteur ne peut pas vivre **dans** le menu : un
        // `PhotosPicker` y serait une ligne qui se présente elle-même, et
        // le menu se referme avant qu'elle n'ait la main. Il est donc posé
        // sur l'écran, et le menu ne fait que lever le drapeau.
        .photosPicker(isPresented: $choisitDansLaPhototheque, selection: $choix, matching: .images)
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

        guard let brut = try? Data(contentsOf: url), let image = ONTImage(data: brut) else {
            refus = "Ce fichier n'est pas une image lisible."
            return
        }
        poser(image)
    }

    /// L'interrupteur des courriels, monté sur une **date**.
    ///
    /// Le modèle ne porte pas de booléen : `nil` veut dire « pas consenti »,
    /// et une date veut dire « consenti ce jour-là ». Cette liaison traduit
    /// l'un dans l'autre — et ==n'écrase pas la date existante quand on
    /// rallume==, parce que la première acceptation est celle qu'il faudrait
    /// pouvoir montrer.
    private var consentementAuxCourriels: Binding<Bool> {
        Binding(
            get: { account.profil.courrielsConsentis != nil },
            set: { accepte in
                if accepte {
                    if account.profil.courrielsConsentis == nil {
                        account.profil.courrielsConsentis = Date()
                    }
                } else {
                    account.profil.courrielsConsentis = nil
                }
            }
        )
    }

    /// L'adresse saisie ne ressemble pas à une adresse.
    ///
    /// **Un signalement, pas un refus.** On n'empêche pas d'enregistrer : le
    /// lecteur tape, et une saisie à moitié écrite serait refusée à chaque
    /// caractère. Ce qui compte est qu'il voie que Gravatar ne répondra pas —
    /// et la vraie vérification, c'est la réponse de Gravatar, pas une
    /// expression rationnelle. ==Une adresse bien formée peut n'exister pas.==
    private var adresseInvalide: Bool {
        let a = account.profil.courriel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return false }
        let morceaux = a.split(separator: "@", omittingEmptySubsequences: false)
        return morceaux.count != 2 || morceaux.contains(where: \.isEmpty)
            || !morceaux[1].contains(".")
    }

    /// L'adresse à laquelle demander un Gravatar, ou `nil`.
    ///
    /// Elle vient de la **session**, pas du profil : c'est celle que le
    /// fournisseur a certifiée, et Gravatar n'indexe que des adresses réelles.
    private var adresseDuCompte: String? {
        // **Celle que le lecteur a déclarée d'abord.** La session peut en
        // porter une, mais « Se connecter avec Apple » permet de la masquer :
        // le compte s'ouvre alors sous un relais `@privaterelay.appleid.com`
        // qu'aucun Gravatar ne connaît. Une adresse déclarée à la main est
        // toujours celle que le lecteur emploie vraiment ; celle de la session
        // ne l'est que parfois.
        for brute in [account.profil.courriel, account.session?.email ?? ""] {
            let propre = brute.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !propre.isEmpty { return propre }
        }
        return nil
    }

    /// Chercher le portrait que le lecteur a déjà, ailleurs.
    ///
    /// ## Pourquoi cette origine existe
    ///
    /// Gravatar — *globally recognized avatar* — est l'annuaire d'images le
    /// plus ancien du web : on y associe une photo à une adresse, et des
    /// milliers de sites la reprennent. Un lecteur qui en a un n'a alors rien
    /// à choisir ni à téléverser. YouVersion le propose pour cette raison, et
    /// l'auteur l'a demandé le 22 septembre 2026.
    ///
    /// ## Ce que l'adresse ne quitte pas
    ///
    /// ==On n'envoie pas l'adresse, on envoie son empreinte.== Gravatar indexe
    /// par SHA-256 de l'adresse en minuscules, débarrassée de ses espaces —
    /// c'est le protocole, et c'est aussi ce qui fait qu'aucune adresse ne
    /// voyage en clair dans l'URL ni dans les journaux du serveur.
    ///
    /// ## `d=404`, et pourquoi il compte
    ///
    /// Sans ce paramètre, Gravatar rend **toujours** une image : une silhouette
    /// grise engendrée pour l'empreinte. On l'enregistrerait comme portrait, et
    /// le lecteur croirait avoir importé le sien. `d=404` fait répondre 404
    /// quand il n'y a rien — ==l'absence redevient distinguable d'une réponse==,
    /// et on peut le dire au lieu de poser une image vide.
    private func importerDeGravatar() async {
        guard let adresse = adresseDuCompte else { return }
        refus = nil
        chargeLaPhoto = true
        defer { chargeLaPhoto = false }

        let empreinte = SHA256.hash(data: Data(adresse.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let url = URL(string: "https://gravatar.com/avatar/\(empreinte)?s=512&d=404")
        else { return }

        do {
            let (octets, reponse) = try await URLSession.shared.data(from: url)
            if let http = reponse as? HTTPURLResponse, http.statusCode == 404 {
                refus = "Aucun Gravatar n'est associé à cette adresse."
                return
            }
            guard let image = ONTImage(data: octets) else {
                refus = "Gravatar a répondu autre chose qu'une image."
                return
            }
            poser(image)
        } catch {
            // Le message dit **ce que le lecteur peut faire**, pas ce que
            // l'erreur contenait : hors ligne, il n'y a rien à corriger dans
            // l'app.
            refus = "Gravatar n'a pas répondu. Vérifiez votre connexion."
        }
    }

    private func recevoirLaPhoto() async {
        guard let choix else { return }
        refus = nil
        chargeLaPhoto = true
        defer { chargeLaPhoto = false }

        guard let brut = try? await choix.loadTransferable(type: Data.self),
            let image = ONTImage(data: brut)
        else { return }
        poser(image)
    }

    private func poser(_ image: ONTImage) {

        // **On réduit avant d'écrire.** Une photo d'appareil moderne fait
        // plusieurs mégaoctets ; on en affiche un rond de 96 points. Garder
        // l'original coûterait le stockage du lecteur pour un détail que
        // personne ne verra jamais — et le ferait monter tel quel à la
        // synchronisation.
        guard let reduite = image.ontReduite(a: 512),
            let jpeg = reduite.ontSousLaBorne(ONTPortrait.borne)
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
