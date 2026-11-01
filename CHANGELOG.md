# Journal des versions / Changelog

## 1.3.0 — 2026-11-01

- **Choix visuel des objets** (onglet Objets) : les objets du jeu s'affichent avec leur icône, leur
  nom, leur TID et leur niveau requis, par catégorie (Tous, Armes, Armures, Bijoux, Montures,
  Utilisables, Autres, Favoris) et par recherche (une partie du nom ou le début du TID) ; un clic
  choisit l'objet, l'aperçu montre son icône, son niveau et sa catégorie, le survol le détail. Le
  catalogue vient d'ArchRust (`ArchRust.SearchItems`, `ArchRust.GetItemTemplate`, `GetItemIcon` :
  ItemTemplateAll.ini, icônes du client) ; avec un client qui ne l'a pas, l'onglet revient à la
  saisie du TID et aux favoris, comme avant.
- **Simulateur de butin** (nouvel onglet Butin) : commande `/simloot <TID du monstre> <nombre>
  [taux de butin] [taux d'or]` d'ArchCore (niveau MJ 2). TID saisi ou pris sur le monstre ciblé,
  nombre de monstres (raccourcis 100, 1 000, 10 000), taux de butin et d'or (vides : ceux du
  serveur, rappelés à côté). Le serveur tire le butin de chaque monstre comme à sa mort, sans rien
  créer ; l'onglet liste les objets obtenus avec leur icône, leur quantité et leur fréquence pour
  100 monstres, et résume l'or et le nombre d'objets.
- **Réduire la fenêtre** : bouton « - » à côté de la fermeture ; la fenêtre devient une barre
  (titre et onglet ouvert) sans perdre les champs remplis ; « + », le bouton MJ, le raccourci ou
  `/aca` la rétablissent.
- Onglets resserrés pour en loger sept ; `/aca loot` ouvre l'onglet Butin.
- Banc d'essai : ArchRust est pris dans son propre dépôt (BlaMacfly/ArchRust) ; 98 vérifications,
  dont le catalogue, la simulation, la réduction et le repli sans catalogue.
- Visual item picker with game icons (Items tab), loot simulator (`/simloot`, new Loot tab), and a
  minimize button for the window.

## 1.2.0 — 2026-10-22

- Logo d'ArchCore Admin en tête de la fenêtre, à la place du titre texte ; la version est affichée
  en petit à sa droite. La fenêtre gagne 52 px de haut, les onglets gardent leur taille.
- ArchCore Admin logo at the top of the window instead of the text title.

## 1.1.0 — 2026-10-22

- Nouvelle commande `/speed <1-10>` d'ArchCore (niveau MJ 2) dans l'onglet MJ : champ et bouton
  « Fixer », raccourcis ×1, ×2, ×3, ×5, ×10 ; la vitesse appliquée est lue dans la réponse du serveur.
- Nouvelle commande `/additem <TID> [quantité]` d'ArchCore (niveau MJ 3) dans l'onglet Objets :
  bouton « Ajouter à mon sac » ; le nom de l'objet est appris comme avec `/create`.
- Onglet MJ réorganisé (remise à zéro de quête sur une ligne) pour faire place à la vitesse.
- New ArchCore commands `/speed <1-10>` (GM tab) and `/additem <TID> [count]` (Items tab).

## 1.0.0 — 2026-10-22

Première version / First release.

- Panneau MJ à six onglets : MJ, Joueurs, Objets, Téléport, Serveur, Journal.
- Toutes les commandes MJ d'ArchCore : taux (`/GetExp`… `/SetPrestigeRate`, `/SetChatBuff`),
  `/chatban`, `/kill`, `/invincible`, `/rename_char`, `/create`, `/questreset`, `/recast`,
  `/level`, `/money`, `/announce_restart`, `/move`.
- Détection du niveau MJ à l'entrée en jeu ; boutons grisés selon le niveau, niveaux requis
  appris dans les réponses du serveur.
- Lecture des réponses d'ArchCore : taux, noms d'objets, invincibilité ; journal horodaté.
- Confirmation des commandes sensibles, commande libre avec historique, catalogue des commandes
  (dont celles d'Archonia non gérées par ArchCore).
- Objets favoris, points de téléportation (villages de départ fournis), joueurs en vue.
- Bouton « MJ » déplaçable, raccourci Ctrl+Maj+A, `/aca`.
- Anglais et français.
- Validé en jeu avec ArchRust contre ArchCore (Rust) et MariaDB.
