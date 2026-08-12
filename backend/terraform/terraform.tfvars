# Le domaine public. Ici et pas dans une variable d'environnement : sans cette
# valeur, `terraform apply` détruirait le certificat et le domaine
# personnalisé sans le dire — il suffirait d'un déploiement lancé depuis un
# autre terminal. Ce n'est pas un secret, il peut être committé.
domaine = "ontbible.com"
