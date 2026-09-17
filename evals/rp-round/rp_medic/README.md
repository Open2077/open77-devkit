# rp_medic — service médical (serveur uniquement)

> Les verbes sont `/soin` et `/reanimer` : `/heal` appartient déjà au menu admin (`open77_admin`) et `/revive` au freeroam, et un nom de commande enregistré deux fois est servi par la première ressource.

Ressource Lua Open77 (build `2.31.13+op77.76`) qui donne aux joueurs dont le métier est
`medecin` les moyens de soigner et de réanimer, et à tout le monde un appel d'urgence.
Tout est décidé côté serveur : aucun script client.

## Commandes

| Commande | Qui | Effet |
|---|---|---|
| `/soin <idJoueur>` | médecin | Soigne entièrement un patient **vivant** à moins de 5 m (`Open77.stats.restoreHealth`). Le patient paie **100 €$** au médecin ; s'il ne peut pas payer, le soin est fait quand même et annoncé comme gratuit. |
| `/reanimer <idJoueur>` | médecin | Réanime un patient **mort** à moins de 5 m, là où il est tombé, à pleine santé avec 5 s d'invulnérabilité (`Open77.players.revive`). **300 €$**, mêmes règles de paiement. |
| `/911 <message>` | tout le monde | Envoie le message et la position arrondie de l'appelant à chaque médecin et policier connecté. L'appelant apprend combien d'intervenants ont été prévenus. |
| `/medic` | tout le monde | Liste les médecins connectés, du plus proche au plus lointain, avec leur distance. Un médecin voit en plus ses compteurs (soins, réanimations, €$ gagnés). |

Règles communes à `/soin` et `/reanimer` :

- un seul **temps de recharge de 30 s** par médecin, partagé entre les deux commandes ;
- impossible d'intervenir sur soi-même, sur un joueur pas encore entré en jeu, ou hors des 5 m ;
- `/soin` sur un mort renvoie vers `/reanimer`, `/reanimer` sur un vivant renvoie vers `/soin` ;
- `/soin` sur un patient déjà à pleine santé ne prélève rien ;
- depuis la console serveur (`source = 0`) les quatre commandes refusent poliment.

L'identifiant d'un joueur s'obtient avec `/id` (commande intégrée du chat).

## Métier, ACL et argent

- Le métier vient de `rp_jobs` : `exports.rp_jobs:hasJob(id, "medecin")` pour `/soin` et
  `/reanimer`, `exports.rp_jobs:getJob(id)` pour dresser la liste des médecins et policiers.
- **Repli ACL** : si l'export de `rp_jobs` est absent (ressource arrêtée, en rechargement,
  export non publié), la ressource applique la sémantique d'une commande restreinte : seul un
  joueur qui détient le droit ACL `command.soin` peut soigner, `command.reanimer` réanimer
  (`Open77.acl.isAllowed`). Dans ce mode, `/medic` et `/911` considèrent comme médecin
  quiconque détient `command.soin`, et la police n'est pas joignable (aucun droit ne la
  désigne) — le message de `/911` le dit.
- L'argent vient de `rp_economy` : `remove` sur le patient puis `add` sur le médecin. Si
  `remove` répond `nil` (`insufficient_funds` ou autre), l'acte est gratuit ; si `add` échoue
  après un `remove` réussi, le patient est remboursé. Sans `rp_economy`, l'acte est gratuit et
  annoncé comme tel.
- Les deux ressources sont déclarées en `dependencies` : le serveur refuse de démarrer
  `rp_medic` si elles ne sont pas dans sa liste `load` (voir le guide *server-resources*). Le
  repli ci-dessus couvre un export absent ou une dépendance arrêtée à chaud, pas une
  dépendance jamais chargée.

## Persistance

Les compteurs par médecin (`heal:<id>`, `revive:<id>`, `earned:<id>`) sont stockés avec
`Open77.kvp.increment`, clé = identifiant durable `Open77.players.identifier`, jamais l'id de
session. Un identifiant introuvable (joueur parti) saute simplement l'écriture.

## Permissions du manifeste

`players.stats.read` (lecture de la santé), `players.stats.apply` (`restoreHealth`),
`players.life.read` (`isDead`), `players.life.revive` (`revive`), `network.events`
(`RegisterNetEvent("chat:ready")` pour les suggestions), `acl.read` (`acl.isAllowed`).

## Tester en 2 minutes

1. Charger `rp_economy`, `rp_jobs` et `rp_medic` dans `server.jsonc` (`resources.load`) et
   démarrer le serveur. Le journal affiche `[rp_medic] started: fees heal=100 revive=300 ...`.
2. Connecter deux clients A et B. Donner le métier à A via `rp_jobs` (par exemple `/job medecin`
   selon cette ressource) et de l'argent à B via `rp_economy` (`/givemoney`). Noter les ids avec `/id`.
3. B tape `/911 on m'a tiré dessus` : A reçoit l'alerte « 911 » avec la position arrondie, B lit
   « Appel transmis à 1 intervenant(s) ».
4. B tape `/medic` : la liste montre A et sa distance.
5. A se place à moins de 5 m de B, B perd de la vie, A tape `/soin <idB>` : B est à pleine
   santé, B a 100 €$ de moins, A 100 €$ de plus, journal `[rp_medic] player A healed player B fee=100`.
   Retaper aussitôt : « Patientez encore N s ». Depuis plus de 5 m : « Trop loin : x m ».
6. Tuer B (`/kill` de test, chute…), A tape `/reanimer <idB>` après 30 s : B se relève sur place,
   300 €$ transférés, journal `... revived ... fee=300`. Vider le compte de B puis recommencer :
   l'acte passe et s'annonce gratuit.
7. B (non médecin) tape `/soin <idA>` : « Réservé aux médecins. ». Arrêter `rp_jobs` puis retaper :
   le message cite le droit `command.soin` (mode ACL).
