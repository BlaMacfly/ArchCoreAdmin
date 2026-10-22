# Journal des versions / Changelog

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
