"""Les épreuves des scripts de livraison, sans toucher à App Store Connect.

## Pourquoi un faux client plutôt qu'un appel réel

Ces scripts ne peuvent pas être éprouvés contre l'API : il faudrait une clé en
CI, et une épreuve qui livre pour se vérifier n'est pas une épreuve. Le faux
client rend ce qu'Apple rend — la **forme** des réponses, relevée sur des
appels réels — et ce qu'on mesure est la branche, pas le réseau.

Ce qu'elles couvrent est donc étroit et il faut le dire : **le choix d'un objet
parmi plusieurs**. C'est là que les deux vrais défauts du 31 août 2026 se
tenaient, et c'est ce qu'aucun `py_compile` n'attrape.

    python3 -m unittest discover -s .github/scripts -p 'epreuves*.py'
"""

import contextlib
import io
import os
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asc
import beta
import fiche
import soumettre


class Reponse:
    """Ce que `requests` rend quand tout va bien."""
    status_code = 200

    def json(self):
        return {}


class FauxClient:
    """Un App Store Connect de papier.

    `reponses` associe un chemin — ou son suffixe — à ce que le vrai rendrait.
    Tout appel non prévu rend une collection vide plutôt que de lever : c'est ce
    que fait l'API pour une relation sans contenu, et une épreuve qui explose
    sur un chemin qu'elle n'a pas anticipé mesure sa propre incomplétude.
    """

    def __init__(self, reponses=None):
        self.reponses = reponses or {}
        self.demandes = []   # (chemin, paramètres)
        self.envois = []     # (chemin, corps)
        self.session = types.SimpleNamespace(patch=lambda *a, **k: Reponse())

    def _trouver(self, chemin):
        if chemin in self.reponses:
            return self.reponses[chemin]
        for cle, valeur in self.reponses.items():
            if chemin.endswith(cle):
                return valeur
        return {"data": []}

    def get(self, chemin, **params):
        self.demandes.append((chemin, params))
        return self._trouver(chemin)

    def post(self, chemin, corps, **k):
        self.envois.append((chemin, corps))
        return {"data": {"id": "cree", "attributes": {"state": "WAITING_FOR_REVIEW"}}}

    def patch(self, chemin, corps):
        self.envois.append((chemin, corps))
        return {"data": {"id": "modifie", "attributes": {"state": "WAITING_FOR_REVIEW"}}}


@contextlib.contextmanager
def env(**valeurs):
    """Les variables posées le temps d'une épreuve, et reprises après."""
    avant = {c: os.environ.get(c) for c in valeurs}
    os.environ.update({c: v for c, v in valeurs.items() if v is not None})
    try:
        yield
    finally:
        for c, v in avant.items():
            if v is None:
                os.environ.pop(c, None)
            else:
                os.environ[c] = v


def taire(fonction):
    """Ce que le script imprime, capté plutôt que déversé dans le rapport."""
    sortie = io.StringIO()
    with contextlib.redirect_stdout(sortie):
        fonction()
    return sortie.getvalue()


class LaRechercheDUnBuild(unittest.TestCase):
    """`attendre_le_build` — la plateforme doit être dans la requête."""

    def test_la_plateforme_est_demandee_a_apple(self):
        client = FauxClient({"builds": {"data": [
            {"id": "b-1", "attributes": {"processingState": "VALID"}}]}})

        asc.attendre_le_build(client, "app-1", "260831.1200", "MAC_OS")

        chemin, params = client.demandes[0]
        self.assertEqual(chemin, "builds")
        self.assertEqual(params.get("filter[preReleaseVersion.platform]"), "MAC_OS")

    def test_iOS_par_defaut(self):
        """Le défaut reconduit ce que faisait l'appel avant que le Mac existe.

        Un défaut qui change de comportement le jour où l'on ajoute un appelant
        est un défaut que personne ne relit.
        """
        client = FauxClient({"builds": {"data": [
            {"id": "b-1", "attributes": {"processingState": "VALID"}}]}})

        asc.attendre_le_build(client, "app-1", "260831.1200")

        self.assertEqual(
            client.demandes[0][1].get("filter[preReleaseVersion.platform]"), "IOS")


def groupe(nom, identifiant, interne=False):
    return {"id": identifiant,
            "attributes": {"name": nom, "isInternalGroup": interne}}


class LeChoixDUnGroupeDeTesteurs(unittest.TestCase):
    """`beta.py` — le groupe est cherché par son nom, qui peut être partagé."""

    def executer(self, groupes, plateforme="IOS"):
        client = FauxClient({"betaGroups": {"data": groupes}})
        beta.Client = lambda: client
        beta.application = lambda c: "app-1"
        beta.attendre_le_build = lambda c, a, n, p="IOS": "b-1"
        with env(BUILD="260831.1200", GROUPE_BETA="Dev",
                 NOTES_BETA="un sujet", PLATEFORME=plateforme):
            return taire(beta.main), client

    def test_un_seul_groupe_le_build_est_rattache(self):
        texte, client = self.executer([groupe("Dev", "g-1")])
        self.assertIn("rattaché", texte)
        self.assertTrue(
            any("relationships/builds" in c for c, _ in client.envois),
            "le build devrait être rattaché au groupe")

    def test_aucun_groupe_les_noms_existants_sont_nommes(self):
        with self.assertRaises(SystemExit) as bilan:
            self.executer([groupe("Beta", "g-2")])
        self.assertIn("Beta", str(bilan.exception))

    def test_deux_homonymes_le_script_refuse_de_choisir(self):
        """Le cas que l'achat universel rend possible.

        Si App Store Connect range ses groupes par plateforme, deux « Dev »
        coexistent. Prendre le premier rattacherait le build du Mac au groupe
        de l'iPhone — sans un mot, les deux étant valides.
        """
        with self.assertRaises(SystemExit) as bilan:
            self.executer([groupe("Dev", "g-ios"), groupe("Dev", "g-mac")])
        message = str(bilan.exception)
        self.assertIn("g-ios", message)
        self.assertIn("g-mac", message)


# L'état réel de la fiche « La Bible ONT » au 31 août 2026, une heure après que
# la plateforme macOS y a été ajoutée. C'est ce qui a armé le défaut ci-dessous.
FICHE_A_DEUX_PLATEFORMES = [
    {"id": "v-ios-104", "attributes": {"platform": "IOS", "versionString": "1.0.4",
                                       "appStoreState": "READY_FOR_SALE"}},
    {"id": "v-mac-10", "attributes": {"platform": "MAC_OS", "versionString": "1.0",
                                      "appStoreState": "PREPARE_FOR_SUBMISSION"}},
]


class LeChoixDUneVersionDeLaFiche(unittest.TestCase):
    """`soumettre.py` — une fiche en achat universel porte deux plateformes."""

    def executer(self, versions, plateforme):
        client = FauxClient({
            "appStoreVersions": {"data": versions},
            "appStoreReviewDetail": {"data": {"id": "d-1",
                                              "attributes": {"notes": "déjà écrites"}}},
        })
        soumettre.Client = lambda: client
        soumettre.application = lambda c: "app-1"
        soumettre.attendre_le_build = lambda c, a, n, p="IOS": "b-1"
        soumettre.numero_de_version = lambda c, b: "1.0.5"
        with env(BUILD="260831.1200", PLATEFORME=plateforme,
                 ASC_CONTACT_EMAIL="x@exemple.fr",
                 ASC_CONTACT_TELEPHONE="+33 6 00 00 00 00"):
            return taire(soumettre.main), client

    def test_une_livraison_iphone_ne_reprend_pas_la_version_du_mac(self):
        """Le défaut du 31 août 2026, et la raison d'être de ce fichier.

        La version macOS `1.0` est `PREPARE_FOR_SUBMISSION`, donc modifiable ;
        l'iOS `1.0.4` est `READY_FOR_SALE` et ne l'est plus. « La première
        modifiable » rendait donc celle du Mac à une livraison iPhone, qui y
        aurait écrit ses informations de revue et rattaché son binaire.
        """
        texte, client = self.executer(FICHE_A_DEUX_PLATEFORMES, "IOS")

        self.assertNotIn("version 1.0 reprise", texte)
        creees = [c for c, _ in client.envois if c == "appStoreVersions"]
        self.assertEqual(len(creees), 1, "une version iOS aurait dû être créée")
        corps = next(b for c, b in client.envois if c == "appStoreVersions")
        self.assertEqual(corps["data"]["attributes"]["platform"], "IOS")

    def test_une_livraison_mac_reprend_bien_la_sienne(self):
        texte, _ = self.executer(FICHE_A_DEUX_PLATEFORMES, "MAC_OS")
        self.assertIn("version 1.0 reprise", texte)

    def test_la_soumission_de_revue_porte_la_plateforme(self):
        _, client = self.executer(FICHE_A_DEUX_PLATEFORMES, "MAC_OS")
        corps = next(b for c, b in client.envois if c == "reviewSubmissions")
        self.assertEqual(corps["data"]["attributes"]["platform"], "MAC_OS")

    def test_sans_le_champ_plateforme_rien_n_est_ecarte(self):
        """Le filtre dégrade vers « ne rien faire », pas vers « tout rejeter ».

        Si Apple cessait de rendre `platform`, un filtre écrit « garder ce qui
        correspond » viderait la liste, et la chaîne créerait une version de
        plus à chaque passage — sans rien dire. Écrit « garder ce qui ne
        contredit pas », il se contente de ne plus filtrer.
        """
        muette = [{"id": "v-muette",
                   "attributes": {"versionString": "1.0.5",
                                  "appStoreState": "PREPARE_FOR_SUBMISSION"}}]
        texte, client = self.executer(muette, "MAC_OS")

        self.assertIn("version 1.0.5 reprise", texte)
        self.assertFalse([c for c, _ in client.envois if c == "appStoreVersions"],
                         "aucune version ne devrait être créée en double")


class LaFicheDesMagasins(unittest.TestCase):
    """`fiche.py` — le texte et les captures vont sur la bonne plateforme."""

    def choisir(self, versions, plateforme):
        client = FauxClient({"appStoreVersions": {"data": versions}})
        return fiche.version_a_remplir(client, "app-1", plateforme), client

    def test_la_fiche_de_l_iphone_ne_va_pas_sur_la_version_du_mac(self):
        """Le même défaut que `soumettre.py` portait, et qui n'a jamais tiré.

        `fiche.yml` est manuel et n'avait jamais tourné quand on l'a trouvé.
        Une exécution après l'ajout de la plateforme macOS aurait écrit la
        description, les mots-clés et les captures de l'iPhone sur la version
        du Mac — la seule modifiable.
        """
        _, client = self.choisir(FICHE_A_DEUX_PLATEFORMES, "IOS")
        creees = [b for c, b in client.envois if c == "appStoreVersions"]
        self.assertEqual(len(creees), 1, "une version iOS aurait dû être créée")
        self.assertEqual(creees[0]["data"]["attributes"]["platform"], "IOS")

    def test_la_fiche_du_mac_reprend_la_sienne(self):
        version, _ = self.choisir(FICHE_A_DEUX_PLATEFORMES, "MAC_OS")
        self.assertEqual(version, "v-mac-10")

    def test_chaque_plateforme_a_ses_formats_de_capture(self):
        """Le Mac n'a qu'un format, et ce n'est pas celui de l'iPhone."""
        self.assertIn("APP_DESKTOP", fiche.FORMATS["MAC_OS"].values())
        self.assertNotIn("APP_DESKTOP", fiche.FORMATS["IOS"].values())


if __name__ == "__main__":
    unittest.main(verbosity=2)
