<p align="right"><a href="README.en.md">🇬🇧 Read in English</a></p>

# ArchCore Admin

[![Tests](https://github.com/BlaMacfly/ArchCoreAdmin/actions/workflows/tests.yml/badge.svg)](https://github.com/BlaMacfly/ArchCoreAdmin/actions/workflows/tests.yml)

Panneau de maître du jeu (MJ) pour le client **ArchRust**, connecté à un serveur
[**ArchCore**](https://github.com/BlaMacfly/ArchCore).
C'est un AddOn Lua qui reprend le principe d'[AzerothAdmin](https://github.com/superstyro/azerothadmin)
(WoW 3.3.5 / AzerothCore) : des onglets de boutons qui tapent les commandes MJ à votre place, et
la lecture des réponses du serveur pour remplir le panneau.

![Onglet Serveur : taux lus sur ArchCore](docs/captures/aca-2-serveur.png)

## 1. Ce que fait AzerothAdmin (analyse)

AzerothAdmin est un AddOn WoW 3.3.5 en Lua sur Ace3 (environ 130 000 lignes, dont 45 000 de
données de modèles 3D). Son fonctionnement se résume en cinq mécanismes :

| Mécanisme | Dans AzerothAdmin |
|---|---|
| **Envoi** | chaque bouton appelle `SendChatMessage(".commande arguments")` ; AzerothCore lit les commandes `.` dans la discussion et applique le niveau de sécurité du compte |
| **Lecture des réponses** | crochet sur `ChatFrame:AddMessage` : les messages système sont analysés pour remplir les résultats de recherche (`.lookup item`), les infos du serveur, des PNJ ou des objets, et le journal |
| **Contexte** | la cible courante sert d'argument (`UnitName("target")`) ; certains boutons sont activés ou grisés à `PLAYER_TARGET_CHANGED` |
| **Organisation** | un onglet par famille (Main, Char, Tele, Ticket, Server, NPC, GO, Misc, Log) ; pour chacun, un fichier `Commands/*.lua` (logique) et un `Frames/Frames_Section*.lua` (disposition) |
| **Confort** | confirmations des commandes dangereuses, favoris et historique, points de téléportation, mini-menu, AceDB (réglages par compte et par personnage), 12 langues |

## 2. Transposition à ArchRust et ArchCore

| AzerothAdmin (WoW) | ArchCore Admin (ArchRust) |
|---|---|
| commandes `.gm on`, `.tele`, `.additem`… | commandes `/kill`, `/move x,z`, `/create`… d'ArchCore (`crates/archcore/src/world/gm.rs`), les mêmes que le panneau « Admin Commands » d'Archonia |
| `SendChatMessage(".cmd")` | `RunMacroText("/cmd")` : le client envoie au serveur toute commande `/` qu'il ne connaît pas, sans écho dans la discussion |
| crochet `ChatFrame:AddMessage` | filtres `ChatFrame_AddMessageEventFilter` : ArchCore répond à chaque commande par **un** message de discussion de type système, qu'ArchRust remet en `CHAT_MSG_SAY` **sans auteur** (lignes `[?]`) ; `CHAT_MSG_SYSTEM` est écouté aussi |
| `UnitIsPlayer("target")` | sous ArchRust, `UnitIsPlayer` ne vaut que pour soi : un autre personnage se reconnaît à son CID (< `0x40000000` chez ArchCore ; PNJ à partir de `0x40000000`, monstres de `0x50000000`) |
| niveau de sécurité connu du client | le client ne donne pas le niveau MJ aux AddOns : l'AddOn envoie `/SetExp` sans argument (sans effet) et lit la réponse (`Commande inconnue` → 0, `Niveau MJ 3 requis… (le vôtre : 2)` → 2, erreur de syntaxe → 3 ou plus) |
| `.lookup item` (recherche par nom) | absente d'ArchCore : objets désignés par TID, nom **appris** dans la réponse de `/create` ou `/additem`, favoris |
| `.account onlinelist` | absente : liste des personnages **en vue** (`ArchRust.GetUnits()`) |
| AceGUI / AceConfig, XML, FrameLib | non fournis par ArchRust : frames créées en Lua (`Widgets.lua`) ; les ScrollFrame ne découpant pas leur contenu, les listes défilent par décalage des données (molette) |
| icône de mini-carte | bouton « MJ » déplaçable + raccourci clavier (`ArchRust.SetBinding`) |

Les onglets reprennent ceux d'AzerothAdmin pour lesquels ArchCore a des commandes :

| Onglet | Commandes |
|---|---|
| **MJ** | niveau MJ détecté, `/invincible`, `/speed` (vitesse ×1 à ×10), `/recast`, `/questreset`, commande libre avec historique, catalogue de toutes les commandes, réglages |
| **Joueurs** | `/kill`, `/level`, `/money`, `/rename_char`, `/chatban` (5 min, 15 min, 1 h, 1 jour, durée libre, lever) sur un nom saisi, ciblé ou choisi parmi les joueurs en vue |
| **Objets** | `/create "nom" <TID> <quantité> <0\|1>`, `/additem <TID> [quantité]` (pour soi), favoris, noms d'objets appris |
| **Téléport** | `/move x,z` vers des coordonnées, sa position, celle de la cible ou un point enregistré (villages de départ d'ArchCore fournis) |
| **Serveur** | taux `/GetExp`… `/SetPrestigeRate`, bonus de discussion, `/announce_restart` (et annulation) |
| **Journal** | commandes envoyées et réponses du serveur, horodatées, 300 lignes par personnage |

Les onglets Ticket, NPC et GO d'AzerothAdmin n'ont pas d'équivalent : ArchCore n'a pas encore ces
commandes. Les commandes d'Archonia qu'il ne gère pas (arène, événements, failles…) sont listées
en gris dans le catalogue (case « Afficher les commandes d'Archonia non gérées ») et restent
envoyables par la commande libre.

## 3. Installation

1. Télécharger `ArchCoreAdmin-vX.Y.Z.zip` sur la page
   [Releases](https://github.com/BlaMacfly/ArchCoreAdmin/releases) et copier le dossier
   `ArchCoreAdmin/` qu'il contient dans le dossier `addons/` d'ArchRust, à côté d'`ArchRust.exe`
   (`addons/ArchCoreAdmin/ArchCoreAdmin.toc`).
2. Donner les droits MJ au compte, côté serveur, puis se reconnecter :

   ```sql
   UPDATE archcore_auth.account SET gm_level = 3 WHERE username = 'admin';
   ```

3. En jeu : `/addons` doit lister « ArchCore Admin ». À l'entrée en jeu, la discussion affiche le
   niveau MJ détecté.

## 4. Utilisation

- Ouvrir : bouton **MJ** (déplaçable), **Ctrl+Maj+A**, ou `/aca`. Échap ferme la fenêtre.
- `/aca gm|players|items|teleport|server|log` : ouvre un onglet.
- `/aca probe` : redétecte le niveau MJ. `/aca send <commande>` : envoie une commande libre.
- `/aca bind <touche>` (`/aca bind` seul : aucun raccourci), `/aca confirm on|off`,
  `/aca replies on|off` (réponses du serveur dans la discussion), `/aca launcher on|off`, `/aca reset`.
- Les boutons d'une commande que votre niveau ne permet pas sont grisés. Le niveau requis vient
  du catalogue, corrigé par le serveur dès qu'il répond « Niveau MJ X requis » (les niveaux se
  changent dans `world.conf`, `GM.CommandLevel.<commande>`).
- `/kill`, `/level`, `/rename_char`, `/chatban` et `/announce_restart` demandent une confirmation
  qui affiche la commande exacte.

Réglages enregistrés dans `saved-variables/ArchCoreAdmin.lua` : profil (réglages, positions),
global (points de téléportation, objets favoris et noms appris, niveaux requis appris), par
personnage (journal, historique des commandes libres).

## 5. Organisation du code

```text
ArchCoreAdmin/
  ArchCoreAdmin.toc   manifeste (ordre de chargement, SavedVariables)
  Locales.lua         textes anglais (par défaut) et français (AceLocale)
  Catalog.lua         catalogue des commandes : nom, niveau, arguments, confirmation
  Core.lua            objet AddOn (Ace3), construction et envoi des commandes, niveau MJ, /aca
  Replies.lua         lecture des réponses d'ArchCore (niveau, taux, objets, invincibilité)
  Widgets.lua         boutons, champs, cases, listes à la molette ; grisage selon le niveau
  Frames.lua          fenêtre, onglets, bouton lanceur
  Sections/*.lua      un fichier par onglet
tests/banc-essai/     banc d'essai Rust (moteur d'AddOns d'ArchRust, sans affichage)
```

### Ajouter une commande quand ArchCore en gère une nouvelle

1. `Catalog.lua` : `def("nom", niveau, { NAME, INT_OPT… }, { section = "players", confirm = true })`
   (le nom respecte la casse du serveur).
2. Dans l'onglet voulu : `W.Button(page, L["LIBELLE"], 120, function() ACA:Run("nom", { … }) end, L["TIP_…"], "nom")`.
3. `Locales.lua` : libellé et info-bulle en anglais et en français.
4. Si la réponse du serveur apporte une information utile au panneau, un analyseur dans `Replies.lua`.

## 6. Limites connues

- Les réponses d'ArchCore sont en français : leur lecture (`Replies.lua`) suit les textes de
  `gm.rs`. Si le serveur change une phrase, la commande marche toujours mais le panneau ne met plus
  à jour la valeur correspondante.
- La sonde du niveau MJ (`/SetExp` sans argument) apparaît dans le journal MJ du serveur, une fois
  par connexion (désactivable : case « Détecter mon niveau MJ »). Sa réponse est masquée dans la
  discussion.
- Une réponse est rattachée à la plus ancienne commande en attente (5 s au plus) : un message
  système sans rapport arrivé au même moment peut être noté comme réponse dans le journal.
- `/move` garde l'altitude actuelle (ArchCore n'a pas de carte des hauteurs).
- ArchRust dessine les boutons et champs du panneau par-dessus la fenêtre de confirmation quand
  elles se recouvrent : la confirmation de l'AddOn s'ouvre donc sous le panneau.
- Les réponses du serveur arrivant en `CHAT_MSG_SAY` sans auteur, tout message sans auteur reçu
  dans les 5 s qui suivent une commande peut lui être attribué.

## 7. Tests

```bash
cd tests/banc-essai
cargo run --release
```

Le banc charge l'AddOn dans `archrust-addons`, le vrai moteur Lua d'ArchRust, pris dans la
branche `client` du dépôt ArchCore (une copie locale se branche par `[patch]`, voir
`tests/banc-essai/Cargo.toml`). Il tourne sur GitHub Actions à chaque envoi et vérifie
62 points : chargement sans erreur, sonde et lecture des trois réponses possibles, construction
de chaque type d'argument et refus des entrées invalides, grisage selon le niveau, confirmation au
clic, lecture des taux et des noms d'objets, discussion des joueurs non confondue avec les
réponses, reconnaissance des personnages ciblés, clics à la souris sur les boutons, absence de
chevauchement et de débordement dans les six onglets, SavedVariables.

**Essai en jeu (2026-10-22)** : client ArchRust contre ArchCore (Rust) et MariaDB locaux, compte
MJ de niveau 3. Niveau détecté (« 3 ou plus ») et réponse de la sonde masquée, sept taux lus,
objet créé (TID 136, nom appris), invincibilité activée puis désactivée, journal rempli,
confirmation de `/kill`. Captures dans [`docs/captures/`](docs/captures/). Non essayés en jeu :
`/kill`, `/level`, `/money`, `/rename_char`, `/chatban`, `/move` et `/announce_restart` sur un vrai
personnage (seule leur construction est vérifiée par le banc), et la détection d'un niveau 1 ou 2.

## Publier une version

1. Mettre à jour `## Version:` dans `ArchCoreAdmin/ArchCoreAdmin.toc` et ajouter une section
   `## X.Y.Z — date` en tête de `CHANGELOG.md`.
2. Pousser une étiquette : `git tag vX.Y.Z && git push origin vX.Y.Z`. Le workflow `Release`
   vérifie que l'étiquette correspond au `.toc` et publie le zip avec les notes du changelog.

## Licence

GPL-3.0-or-later, comme ArchRust, ArchCore et AzerothAdmin (dont aucun code n'est repris :
seul le principe l'est).
