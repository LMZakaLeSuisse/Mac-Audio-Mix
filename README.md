# Source Audio

Une application macOS native pour choisir rapidement le périphérique d’entrée (microphone ou interface) et le périphérique de sortie (casque, enceintes ou écran).

## Télécharger l’application prête à l’emploi

1. Télécharge le fichier **TELECHARGER-Source-Audio-macOS.zip** depuis la racine du dépôt.
2. Décompresse-le en double-cliquant dessus.
3. Fais un clic droit sur **Source Audio.app**, puis choisis **Ouvrir**.
4. Confirme une seconde fois avec **Ouvrir** lors de la première utilisation.

N’ouvre pas un ancien dossier `Source Audio.app` provenant d’un téléchargement précédent : il était incomplet. Utilise uniquement l’application contenue dans la nouvelle archive ci-dessus.

Le clic droit est nécessaire au premier lancement, car cette version personnelle n’est pas signée avec un compte Apple Developer. Les lancements suivants se font normalement par double-clic.

## Utilisation

1. Double-clique sur **Lancer Source Audio.command**.
2. Choisis une entrée et une sortie dans la fenêtre.
3. Ensuite, utilise l’icône en forme d’onde dans la barre des menus pour changer de périphérique sans rouvrir la fenêtre.

Les changements sont appliqués directement avec Core Audio et apparaissent dans les Réglages Système. L’application ne capture et n’enregistre aucun son.

Pour recompiler l’application après une modification, double-clique sur **Construire Source Audio.command**.
