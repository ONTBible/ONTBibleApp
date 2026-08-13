# Le domaine public. Ici et pas dans une variable d'environnement : sans cette
# valeur, `terraform apply` détruirait le certificat et le domaine
# personnalisé sans le dire — il suffirait d'un déploiement lancé depuis un
# autre terminal. Ce n'est pas un secret, il peut être committé.
domaine = "ontbible.com"

# L'adresse propre de l'API. Additive : `ontbible.com` continue de servir
# l'API tant qu'on ne l'a pas basculée vers le site, et les deux noms
# répondent en parallèle. C'est ce recouvrement qui rend la bascule
# réversible.
api_domaine = "api.ontbible.com"
