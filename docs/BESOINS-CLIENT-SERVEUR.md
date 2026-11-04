# Ce que le panneau attend d'ArchRust et d'ArchCore

État au 2026-11-04 (ArchCore Admin 1.4.0). L'AddOn détecte chacun de ces points et s'en sert dès qu'il
est là : aucun changement du panneau n'est nécessaire le jour où ils arrivent. Le banc d'essai simule
l'API des points 2 et 3 en Lua (section 15 de `tests/banc-essai/src/main.rs`).

## 1. Les refus du serveur n'arrivent pas aux AddOns

**Constat.** ArchCore répond à une commande MJ refusée par un message de la forme :

```text
/create : objet inconnu : TID 15151. Syntaxe : /create "nom" <TID> <quantité> <0|1>
```

(`crates/archcore/src/world/gm.rs`, `format!("/{name} : {}. Syntaxe : {}", …)`, envoyé par `send_system`.)

ArchRust jette tout message reçu qui commence par `/`, avant les filtres des AddOns et avant la
discussion (`crates/archrust-engine/src/app_chat.rs`, `chat_received`) :

```rust
if message.starts_with('/') || message.is_empty() {
    return;
}
```

**Conséquences.**

- `/create`, `/additem`, `/simloot`… refusés : ni le panneau ni la discussion ne montrent rien. C'est
  l'échec muet du point 14 du retour de bug n° 2. Il touche aussi un MJ qui tape la commande à la main.
- Sonde du niveau MJ : pour un compte de niveau 3, `/SetExp : argument manquant…` se perd, d'où
  « Niveau MJ : inconnu » et « Pas de réponse du serveur ».

**Ce qu'il faut**, au choix :

- côté ArchRust (recommandé) : ne pas écarter les messages système en `/` dans `chat_received`, au moins
  pour le type `WHOLE_WORLD` (7) qu'emploie `send_system` ;
- côté ArchCore : faire précéder le message d'un autre texte. Il faudra alors adapter le motif
  `^/(%S+) : (.+)%. Syntaxe : ` de `Replies.lua`.

**En attendant**, le panneau tient compte du silence : au bout de 5 secondes sans réponse, il donne les
causes possibles au lieu de rester muet, et la sonde se complète par `/GetExp`. La cause exacte ne peut
pas être affirmée tant que le refus n'arrive pas.

## 2. Fiche des objets : ce qui existe sur le serveur, classes, emplacements, statistiques

**Constat.** `ArchRust.GetItemTemplate` et `ArchRust.SearchItems` lisent `ItemTemplateAll.ini` du client,
qui contient aussi les ajouts d'Archonia, et ne donnent que `tid, name, icon, level, type, kind, part,
stack, category`. Le panneau propose donc des objets que le serveur ne connaît pas (TID 15151) et n'a ni
classe, ni emplacements, ni statistiques. Un AddOn ne peut pas lire `server-data/` lui-même : pas d'`io`,
et `require` ne lit que les `.lua` des dossiers d'AddOns.

**Ce qu'il faut** : dans `item_templates` (`crates/archrust-engine/src/app_addons.rs`), lire aussi
`ini/itemdatatable.txt` par la couche habituelle (`server-data/` d'abord) et ajouter à la table Lua de
chaque modèle (`item_template_table`, `crates/archrust-addons/src/api.rs`) :

| Champ | Type | Colonne de `itemdatatable.txt` | Remarque |
|---|---|---|---|
| `server` | booléen | ligne présente ou non | seulement s'il existe un dossier `server-data/` ; `false` : l'objet n'est pas sur le serveur. Sans ce dossier : `nil` |
| `classes` | liste d'entiers | `Class` | valeurs séparées par `;` (`1;2;3;4`) ; liste vide si la colonne est vide. Sa présence dit au panneau que ce client donne ces champs |
| `races` | liste d'entiers | `Race` | de même (`1;2`) |
| `minSocket`, `maxSocket` | entiers | `MinSocket`, `MaxSocket` | absents si la colonne est vide |
| `stats` | table `colonne → nombre` | ci-dessous | valeurs non nulles seulement ; seulement dans `GetItemTemplate`, pas besoin de la mettre dans `SearchItems` |

Colonnes de `stats`, avec les noms exacts de l'en-tête, espaces en bord de nom retirés :

- dégâts : `Physical_Min_Damage`, `Physical_Max_Damage`, et `<E>_Min_Damage`, `<E>_Max_Damage` ;
- défense : `Physical_Defense_Point`, `PDR`, `BlockRate`, `<E>_Defense_Point`, `<E>_Defense_Rate` ;
- attaque : `ATK Speed`, `ATK Range`, `Physical_ATKRate`, `Magic_ATKRate` ;
- bonus : `CON_Bonus_Point`, `STR_Bonus_Point`, `DEX_Bonus_Point`, `INT_Bonus_Point`, `Wis_Bonus_Point`,
  `HP`, `SP`, `MP`, `Hp_Buff`, `Mp_Buff`, `Attack_Buff`, `Defense_Buff`, `Run_Buff` ;
- divers : `Rank`, `DUR`.

`<E>` vaut `Magic`, `Water`, `Fire`, `Earth`, `Air`, `Poison`, `Ice`, `Linghtning` (orthographe de la
colonne). Les objets du client absents de la table restent listés avec `server = false` : leur nom permet
d'expliquer le refus. `Class` et `Race` suivent `CharacterDataTable.txt` : Knight (race 1, classe 1), Archer
(1, 2), Mage (1, 4), Berserker (2, 1), Hunter (2, 2), Sorcerer (2, 4), Swashbuckler (3, 1), Ranger (3, 2),
Elementalist (3, 4), Slayer (4, 1), Orbiter (4, 2), Scion (4, 3), Summoner (4, 4).

**Ce que le panneau en fait** :

- objets `server = false` retirés des listes, signalés dans l'aperçu et l'info-bulle (point 14) ;
- info-bulle : classes, emplacements, statistiques (point 05) ;
- bouton de filtre par classe, affiché seulement si `classes` existe (point 11).

## 3. Liste des monstres

**Constat.** L'API ne donne que les unités en vue (`ArchRust.GetUnits`), sans leur niveau (`unit_of` met
`level: 1`). Le panneau liste donc les monstres déjà rencontrés, retenus d'une session à l'autre.

**Ce qu'il faut** : `ArchRust.GetMonsterTemplates()`, qui rend la liste de tous les monstres :
`{ { tid = 450, name = "…", level = 1 }, … }`. Source : `ini/CharacterDataTable.txt` par la même couche,
colonnes `TID`, `Name` et `LVL`, lignes dont `Type` a le bit `0x4` (monstre, voir `character_types` dans
`app_combat.rs`). Le nom suit la langue du client si `ini_<langue>/CharacterDataTable.txt` existe.

**Ce que le panneau en fait** : la liste de l'onglet Butin devient complète, avec le niveau (point 06). Le
serveur reste juge : `/simloot` refuse un modèle qu'il n'a pas chargé.
