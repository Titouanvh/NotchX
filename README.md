# NotchX

Tableau de bord natif pour macOS, sous l’encoche : calendrier, commandes média et dépôt de fichiers. Gratuit et open source, sous licence MIT.

[Site officiel](https://notchx.vercel.app/) · [Vidéo de lancement · 15 s](https://github.com/Titouanvh/NotchX/releases/latest/download/NotchX-launch.mp4)

## Télécharger et installer

Téléchargez l’archive Apple Silicon depuis [la dernière version](https://github.com/Titouanvh/NotchX/releases/latest), décompressez-la et glissez `NotchX.app` dans Applications. Cette version nécessite macOS 14 ou ultérieur sur un Mac Apple Silicon.

L’application utilise une signature ad hoc et n’est pas notariée par Apple. Au premier lancement, macOS peut bloquer son ouverture. Après avoir tenté de l’ouvrir, utilisez **Réglages Système → Confidentialité et sécurité → Ouvrir quand même** si vous faites confiance au téléchargement. Vous pouvez aussi compiler les sources ci-dessous.

## Ouvrir

Ouvrez NotchX depuis Applications ou, après compilation, `build/NotchX.app`. Survolez l’encoche pendant 0,2 s ou cliquez sur l’icône NotchX dans la barre des menus. Le panneau s’ouvre depuis le centre de l’encoche et disparaît lorsqu’il se replie. Cliquez sur l’épingle pour garder le panneau ouvert. Dans **Réglages → Général → Taille**, choisissez **Compact** (480 × 230 pt), **Petit** (540 × 250 pt), **Moyen** (590 × 270 pt) ou **Grand** (650 × 310 pt). Moyen est le format par défaut et reprend les dimensions de l’ancien Compact. Dans **Apparence**, choisissez parmi 30 palettes classées par style ou personnalisez le fond, les panneaux et l’accent. Le thème sombre classique est sélectionné par défaut.

- **Dépôt** · Glissez des fichiers ou des dossiers du Finder sous l’encoche. NotchX ouvre l’onglet **Dépôt** pendant le survol. Après avoir changé de fenêtre, rouvrez le panneau et glissez un élément vers la destination. Le dépôt conserve des références aux originaux. Retirer un élément du dépôt laisse son fichier dans le Finder.
- **Calendrier** · Cliquez sur **Connecter mes calendriers** dans le panneau ou dans **Réglages → Calendrier**. Si l’accès a été refusé, utilisez **Ouvrir Confidentialité**, puis autorisez l’accès complet pour NotchX dans Calendriers. macOS demande l’accès complet pour permettre la lecture via EventKit. NotchX consulte les événements. Le texte des événements reprend une nuance discrète de la palette NotchX. Apple Calendrier conserve ses couleurs. Utilisez **Calendriers** pour isoler vos cours, **Jour** pour agrandir une date, **2 jours** pour comparer deux dates côte à côte et cliquez sur un cours pour lire son intitulé, son horaire et sa salle. Si votre EDT est fourni par abonnement ICS, ajoutez cet abonnement dans Calendrier sur le Mac.
- **YouTube** · Sélectionnez Safari dans NotchX. Dans **Safari → Réglages → Développeur**, activez **Autoriser JavaScript à partir des évènements Apple**. Si l’onglet manque, affichez les fonctionnalités pour les développeurs dans **Avancés**. Le bouton **Réglages Safari…** ouvre Safari et, si NotchX dispose déjà de l’autorisation Accessibilité, tente d’ouvrir **Développeur**. Lancez une vidéo dans Safari, cliquez une fois sur **Connecter Safari** et acceptez l’autorisation Automatisation de macOS. NotchX mémorise la connexion et retrouve la vidéo à l’ouverture du panneau. Le bouton de déconnexion désactive cette reprise. Le volet affiche le titre et la progression du lecteur détecté, avec lecture/pause et saut de 15 s.
- **Apple Podcasts** · Ouvrez le lecteur dans Podcasts, puis cliquez sur **Connecter Podcasts** et autorisez NotchX dans **Confidentialité et sécurité → Accessibilité**. Les commandes proposées dépendent de celles que Podcasts expose. L’affichage du titre et de la progression de l’épisode reste à intégrer.

[Accès EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) · [Menu Développement de Safari](https://support.apple.com/fr-fr/guide/safari/sfri20948/mac)

Dans la colonne d’aujourd’hui, un trait rouge indique l’heure actuelle dans les vues **Jour**, **2 jours** et **Semaine**.

## Compiler

Exécutez les commandes dans le dossier NotchX, avec macOS 14 ou ultérieur et les outils de ligne de commande Xcode.

```sh
./build.sh
open build/NotchX.app
```

Le binaire livré cible Apple Silicon. Le script accepte aussi `x86_64` et `universal`. L’application locale utilise une signature ad hoc. macOS peut redemander les autorisations après remplacement de l’application par un nouveau build.

Pour ouvrir un aperçu interactif avec des données fictives, exécutez cette commande.

```sh
open -n build/NotchX.app --args --preview
```

Ajoutez `--preview-size compact`, `petit`, `moyen` ou `grand` après `--preview` pour comparer les formats avec les mêmes données fictives.

## Confidentialité et autorisations

NotchX conserve vos réglages et les références du dépôt de fichiers dans les préférences locales de macOS. Le calendrier utilise EventKit. Les commandes Safari utilisent les événements Apple ; les commandes Podcasts utilisent les API d’accessibilité. Accordez ces autorisations seulement pour les fonctions souhaitées. Le code de l’application n’intègre ni compte utilisateur, ni télémétrie, ni serveur distant.

## Licence et provenance

Le code de NotchX est une implémentation originale en SwiftUI et AppKit, publiée sous [licence MIT](LICENSE). Vous pouvez l’utiliser, le modifier et le redistribuer gratuitement selon les conditions de cette licence. Le dépôt ne contient aucun code ni actif extrait d’une autre application.

Pour contribuer, ouvrez une issue ou une pull request en décrivant le comportement observé, la version de macOS et les étapes pour le reproduire. Ne joignez pas vos événements de calendrier ni vos fichiers personnels.

## Inspirations des palettes

[Dracula](https://draculatheme.com/contribute) · [Catppuccin](https://catppuccin.com/palette/) · [Nord](https://www.nordtheme.com/docs/colors-and-palettes/) · [Rosé Pine](https://rosepinetheme.com/palette/) · [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) · [Gruvbox](https://github.com/morhetz/gruvbox) · [Flexoki](https://stephango.com/flexoki)
