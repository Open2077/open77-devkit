# rp_chat — commandes de chat roleplay

Ressource **serveur uniquement** pour Open77 (build `2.31.13+op77.76`). Elle ajoute les
commandes de chat classiques d'un serveur RP : le serveur décide de l'audience (proximité),
lit les noms, les emplois et les soldes, et pousse les lignes par `Open77.chat`.

## Commandes

| Commande | Effet | Audience |
|---|---|---|
| `/me <action>` | `* <Nom> <action>` en violet | tous les joueurs à **30 m** (vous compris) |
| `/do <description>` | `** <description> ((<Nom>))` en violet clair | 30 m |
| `/ooc <texte>` | `(( OOC ) <Nom>: <texte>` en gris | **tout le serveur** |
| `/w <playerId> <texte>` | murmure : la cible voit `(murmure) <Nom> : <texte>`, vous voyez `(murmure à <Cible>) <Nom> : <texte>`, en gris sombre | vous et la cible, qui doit être à **10 m** |
| `/dice [faces]` | `<Nom> lance un dé (6) : 4` en doré ; 6 faces par défaut, 2 à 1000 | 30 m |
| `/showid [playerId]` | carte d'identité : nom, emploi, et **votre solde uniquement sur votre propre carte** | vous seul ; la cible doit être à **5 m** |

Les `playerId` sont les identifiants de session (`/id` dans le chat). Le nom vient de
`Open77.players.name`. Toute commande lancée depuis la console serveur est refusée
poliment (journal seulement) : elles exigent un personnage dans le monde.

Chaque refus est expliqué au joueur en français : joueur introuvable, trop loin
(distance affichée), position inconnue, message vide ou trop long (512 octets), nombre
de faces invalide, etc.

## Sources des données

- **Audience de proximité** : `Open77.players.nearby(joueur, rayon, { includeSelf = true })`
  (documenté par le MCP, disponible depuis op77.67). Il respecte le bucket de routage du
  joueur. Si la position du joueur est inconnue (pas encore dans le monde), le message
  n'est pas envoyé et le joueur en est informé — il n'y a pas de repli vers « tout le
  monde », qui serait un faux positif en RP.
- **Distance** (`/w`, `/showid`) : `Open77.players.distance(a, b)`, en 3D.
- **Emploi** : `exports.rp_jobs:getJob(playerId)` ; `sans emploi` quand l'export manque,
  échoue ou rend `nil`.
- **Solde** : `exports.rp_economy:getBalance(playerId)` ; `indisponible` quand l'export
  manque ou échoue. Les exports synchrones lèvent une erreur en cas d'échec : chaque
  appel est enveloppé dans `pcall`, rien ne plante.
- **Carte d'identité** : envoyée en **notification** (`Open77.notifications.send`) quand
  la native existe **et** que la ressource `open77_notifications` est `running`
  (`Open77.resource.state`) ; sinon, ou si l'envoi échoue, en lignes de chat (une par
  tick pour garder l'ordre). Le manifeste ne déclare pas `open77_notifications` en
  dépendance dure : sans le paquet, les commandes de chat restent disponibles et la
  carte s'affiche dans le chat.

## Manifeste

- `permissions { "network.events" }` : exigé par `RegisterNetEvent("chat:ready")` et
  `Open77.notifications.send`.
- `dependency "rp_jobs"`, `dependency "rp_economy"` : les deux ressources dont les
  exports sont appelés (ordre de démarrage ; l'absence d'un export reste gérée).
- Aucune persistance : cette ressource ne stocke rien, le KVP n'est pas nécessaire.

## Tester en deux minutes

1. Déposer `rp_chat/` dans la racine des ressources, avec `rp_jobs` et `rp_economy`.
   Démarrer le serveur ; le journal affiche
   `[rp_chat] started: /me /do /ooc /w /dice /showid (notifications: toast|chat fallback)`.
2. Se connecter avec **deux clients** (A et B), noter leurs `/id`.
3. A et B côte à côte : `/me regarde autour de lui` → les deux voient
   `* A regarde autour de lui`. `/do Il pleut.` → `** Il pleut. ((A))`.
4. B s'éloigne à plus de 30 m : `/me tousse` chez A n'atteint plus B (A le voit toujours).
5. `/ooc salut` → tout le serveur voit `(( OOC ) A: salut` en gris.
6. À moins de 10 m : `/w <idB> psst` → B voit `(murmure) A : psst`, A voit
   `(murmure à B) A : psst`. À plus de 10 m : `Trop loin : B est à 14 m (10 m maximum).`
7. `/dice` → `A lance un dé (6) : n` ; `/dice 20` → `(20)` ; `/dice 1` → refus.
8. `/showid` → carte avec nom, emploi et solde. `/showid <idB>` à moins de 5 m → carte de
   B **sans** solde ; à plus de 5 m → refus avec la distance.
9. Depuis la console serveur, `me test` → rien dans le chat, une ligne de refus dans le
   journal.
10. Ouvrir le chat et taper `/` : les six commandes apparaissent dans la complétion.
