import Foundation

/// Le choix entre les deux seconds noms — le pont français ou la glose.
///
/// Tout ce que le lecteur parcourt porte deux noms sous son nom ONT : un
/// **pont de navigation** vers le français reçu — *Gevurot ha-Neviim* →
/// « Actes des Apôtres » — et une **glose**, qui dit ce que le nom ONT veut
/// dire en gardant ses intraduisibles — « les gevurot de YHWH par ses neviim ».
/// L'écart entre les deux est ce que le projet montre ; l'interrupteur « Le
/// français reçu » décide lequel s'affiche.
///
/// **La règle vit ici et non dans une vue.** Elle était écrite trois fois :
/// une copie privée dans la liste de la Bible, aucune dans le sélecteur de
/// référence — qui affichait donc le français quel que soit le réglage. Une
/// règle recopiée est une règle qu'un écran finit par ne pas appliquer.
public enum Registre {
    /// Le second nom à afficher, ou `nil` quand il n'y a rien à dire.
    ///
    /// **Le français par défaut** : un lecteur qui arrive doit pouvoir se
    /// repérer avec les mots qu'il connaît. En glose, il lit ce que le nom ONT
    /// veut dire.
    ///
    /// Rend `nil` quand la ligne se répéterait : une section dont la glose
    /// redirait le pont — *Ketouvim* est « Écrits » des deux côtés — n'en
    /// porte pas, et la ligne disparaît plutôt que de se redoubler.
    public static func second(
        french: String?, glose: String?, francaisRecu: Bool
    ) -> String? {
        let choisi = francaisRecu ? french : (glose ?? french)
        guard let choisi, !choisi.isEmpty else { return nil }
        return choisi
    }
}
