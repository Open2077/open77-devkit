# rp_shop — boutique serveur

Ressource **serveur uniquement** : une boutique pour serveur RP. L'argent passe
toujours par les exports de `rp_economy`, jamais par cette ressource.

## Commandes

| Commande | Effet |
|---|---|
| `/shop` | Affiche le catalogue (une ligne par objet, groupé par famille) et ton solde. |
| `/buy <objet>` | Débite le prix via `rp_economy`, puis livre l'objet. Fonds insuffisants ou système monétaire hors ligne : rien n'est livré. Si la livraison échoue (natif refusé), tu es remboursé et la raison est affichée. |
| `/sell <objet>` | Uniquement pour les véhicules achetés ici : retire ton dernier véhicule de ce modèle encore en circulation et rembourse 50 % du prix. Sans argument : ton dernier véhicule acheté ici, quel que soit le modèle. |

Un joueur mort ne peut ni acheter ni vendre. La console serveur est refusée
(`/shop` depuis la console imprime seulement le catalogue dans le log).

## Catalogue

| Objet | Famille | Prix | Livraison |
|---|---|---|---|
| `soin` | consommable | 50 $ | vie au maximum (`Open77.stats.restore` health) |
| `stim` | consommable | 30 $ | endurance au maximum (`Open77.stats.restore` stamina) |
| `armure` | consommable | 150 $ | armure 100 (`Open77.players.setArmor`) |
| `pistolet` | arme | 400 $ | `Items.Preset_Lexington_Default`, emplacement 1 |
| `fusil` | arme | 1 200 $ | `Items.Preset_Carnage_Default`, emplacement 2 |
| `katana` | arme | 900 $ | `Items.Preset_Katana_Default`, emplacement 3 |
| `hella` | véhicule | 15 000 $ | `Vehicle.v_standard2_archer_hella_player`, à 3,5 m à ta droite, même orientation |
| `quadra` | véhicule | 60 000 $ | `Vehicle.v_sport1_quadra_turbo_r_player`, idem |

Les armes sont livrées par le relais client `open77_weapons` : la commande
répond « livraison en cours », puis « Livré » (ou remboursement) quand le client
a confirmé. Les véhicules sont créés `persistent = true` : seul `/sell` (ou un
admin) les retire.

## Persistance

Les véhicules achetés sont mémorisés dans le KVP de la ressource sous la clé
`garage:<identifiant durable>` (JSON), donc `/sell` survit à un rechargement de
la ressource. Une entrée dont le véhicule n'existe plus (ou dont l'id a été
recyclé pour un autre modèle) est ignorée puis purgée.

## Dépendances et permissions

- `dependency "rp_economy"` — exports `getBalance`, `add`, `remove`.
- `dependency "open77_weapons >=0.1.0"` — relais des armes.
- `network.events` (armes, `chat:ready`), `world.vehicles`, `players.stats.apply`,
  `players.life.read`.

Si `rp_economy` n'est pas chargée, la boutique reste utilisable en lecture
(`/shop`) et refuse les achats avec un message clair.

## Tester en 2 minutes

1. Démarrer le serveur avec `rp_economy`, `open77_weapons` et `rp_shop` ; se
   connecter et être vivant.
2. `/shop` — le catalogue s'affiche en trois familles, puis ton solde.
3. `/buy soin` — le log serveur affiche `[rp_shop] player <id> bought soin for 50`
   et la vie est au maximum. Sans argent : « Fonds insuffisants ».
4. `/buy katana` — « livraison en cours… » puis « Livré : Katana (emplacement 3) ».
5. `/buy hella` — une Archer Hella apparaît à ta droite, orientée comme toi.
6. `/sell hella` — la voiture disparaît, 7 500 $ sont recrédités.
7. `/sell hella` à nouveau — « Tu n'as aucun Archer Hella (berline) acheté ici
   encore en circulation. »
