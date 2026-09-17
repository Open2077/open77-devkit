# rp_jobs — métiers d'un serveur RP

Ressource serveur (plus un mini script client) pour Open77, build `2.31.13+op77.76`.
Un joueur occupe au plus un métier ; il est sauvegardé dans le KVP de la ressource
sous l'identifiant durable du joueur et restauré quand il revient.

Métiers : `livreur`, `taxi`, `mecano`, `medecin`, `police`.

## Commandes

| Commande | Effet |
|---|---|
| `/jobs` | Liste les métiers avec une ligne de description ; le métier actuel est marqué `[actuel]`. |
| `/job <nom>` | Prend le métier `<nom>`. Annoncé au joueur, sauvegardé, événement `rp_jobs:changed` levé. |
| `/job quit` | Démissionne (annule la tournée en cours s'il y en a une). |
| `/mission` | Livreur uniquement : lance une tournée de 3 livraisons. |
| `/stopmission` | Annule la tournée en cours et rend le véhicule. |

Toutes les commandes refusent poliment la console serveur (`source == 0`).

## La tournée du livreur

1. Le serveur lit la position du joueur (`Open77.players.get`) et fait apparaître une
   Makigai MaiMai (`Vehicle.v_standard2_makigai_maimai_player`) 4 m à côté. Si le spawn est
   refusé, le joueur est prévenu et la tournée se fait à pied.
2. Trois points sont tirés à distance croissante (150–220 m, 230–310 m, 320–400 m) sur le
   plan du joueur : le `z` est celui du joueur, jamais deviné.
3. Pour chaque point : coordonnées et distance dans le chat, et un waypoint GPS placé sur
   la carte du joueur (relais `rp_jobs:waypoint` → `Open77.blips.setWaypoint` côté client).
4. Arrivée détectée côté serveur, un sondage par seconde, à 12 m (distance au sol).
5. Chaque livraison paie `exports.rp_economy:add(playerId, 150, "livraison")`. Si
   `rp_economy` est absent, le joueur est prévenu que l'argent est hors ligne et la tournée
   continue.
6. Le véhicule est retiré à la fin, sur `/stopmission`, sur `/job quit`, à la déconnexion
   et à l'arrêt de la ressource (un `ttlMs` de 30 min sert de filet de sécurité).

## Exports serveur

```lua
exports.rp_jobs:getJob(playerId)          -- "livreur" | nil
exports.rp_jobs:hasJob(playerId, "police") -- true | false
```

Événement hôte : `rp_jobs:changed (playerId, jobName | nil)` à chaque changement.

## Journal

```text
[rp_jobs] player 3 job=livreur
[rp_jobs] player 3 job=none
[rp_jobs] mission player 3 started vehicle=12
[rp_jobs] mission player 3 point 2/3 reached
[rp_jobs] mission player 3 finished
[rp_jobs] mission player 3 cancelled reason=player_request
```

## Tester en 2 minutes

1. Déposer `rp_jobs` (et `rp_economy`, déclaré en dépendance) dans le dossier des ressources ;
   démarrer le serveur, se connecter.
2. `/jobs` → la liste des cinq métiers, aucun marqué.
3. `/job livreur` → « Vous etes maintenant Livreur… » ; le journal affiche
   `[rp_jobs] player N job=livreur`.
4. `/mission` → une voiture apparaît à côté, le chat donne « Livraison 1/3 : rendez-vous en
   X=… Y=… (a … m) » et un waypoint apparaît sur la carte.
5. Rouler jusqu'au point : « Colis 1/3 livre ! » puis « Livraison payee : +150 $… », et le
   point suivant est annoncé. Après le 3e point la voiture disparaît.
6. Se déconnecter puis revenir : « Bon retour : vous reprenez votre poste de Livreur. »
7. `/stopmission` en cours de tournée rend le véhicule ; `/job quit` démissionne.
