# rp_economy — portefeuille serveur (eurodollars)

Ressource **serveur uniquement** pour Open77 (build `2.31.13+op77.76`). Chaque joueur possède un
solde entier en €$, rattaché à son identifiant durable (`Open77.players.identifier`), chargé
quand le joueur est prêt (`onPlayerReady`) et sauvegardé dans le KVP de la ressource à chaque
changement. Un nouveau joueur démarre avec **500 €$**.

## Commandes

| Commande | Qui | Effet |
|---|---|---|
| `/money` | tout joueur | Affiche le solde dans le chat (et une notification si `open77_notifications` tourne). |
| `/pay <playerId> <montant>` | tout joueur | Envoie `montant` €$ à un joueur connecté et prêt. Refusé si : montant non entier positif, fonds insuffisants, cible hors ligne, ou soi-même. Les deux joueurs sont prévenus. |
| `/givemoney <playerId> <montant>` | admin (ACL `command.givemoney`) ou console | Crédite un joueur. Depuis la console seul le joueur crédité est prévenu. |
| `/payday` | admin (ACL `command.payday`) ou console | Déclenche une paie immédiate pour tous les joueurs prêts. |

**Paie automatique** : toutes les 10 minutes, chaque joueur connecté et prêt reçoit 200 €$ avec la
ligne de chat `Paie : +200 €$`.

Les commandes restreintes utilisent `RegisterCommand(..., true)` : un joueur sans le droit ACL est
refusé par le serveur avant le handler (la réponse arrive dans le terminal Open77, pas dans le chat).
Pour autoriser un admin, ajouter `command.givemoney` et `command.payday` (ou `command.*`) à son
principal dans `acl.jsonc`, puis `acl.reload`.

## Exports serveur (contrat partagé)

```lua
exports.rp_economy:getBalance(playerId)        -- integer, 0 si inconnu
exports.rp_economy:add(playerId, amount, reason)    -- newBalance | nil, reason
exports.rp_economy:remove(playerId, amount, reason) -- newBalance | nil, "insufficient_funds" | nil, reason
```

Validation : `playerId` entier positif d'un joueur **chargé** (sinon `invalid_player_id` /
`player_not_found`), `amount` entier positif (`invalid_amount`), `reason` chaîne de 1 à 64 octets
sans caractère de contrôle, ou `nil` (`invalid_reason`). `balance_limit` si le solde dépasserait
10^12. Après chaque changement :

```lua
TriggerEvent("rp_economy:changed", playerId, newBalance, delta, reason)
```

Les exports sont synchrones et ne yieldent jamais : l'appel `exports.rp_economy:add(...)` est sûr.
Déclarer `dependency "rp_economy"` dans le manifeste de la ressource appelante.

## Journal

Chaque changement est imprimé sous une forme grep-able :

```
[rp_economy] +200 player 3 payday balance=700
[rp_economy] -50 player 3 pay:to:4 balance=650
[rp_economy] +50 player 4 pay:from:3 balance=550
[rp_economy] +1000 player 4 givemoney:by:0 balance=1550
```

## Tester en 2 minutes

1. Placer le dossier dans la racine des ressources du serveur (`auto_start true`), démarrer.
2. Se connecter avec un client : à l'arrivée en jeu le chat affiche `Solde : 500 €$`, et le log
   serveur `[rp_economy] new wallet player <id> <userId> balance=500`.
3. `/money` → `Solde : 500 €$` (+ toast si les notifications tournent).
4. Console serveur : `givemoney <id> 1000` → le joueur voit `Un administrateur t'a crédité de
   1000 €$. Solde : 1500 €$`.
5. Console serveur : `payday` → le joueur voit `Paie : +200 €$`, log `+200 player <id> payday`.
6. Avec un second client (`id2`) : `/pay id2 300` → les deux joueurs voient la ligne de transfert ;
   `/pay id2 999999` → `Fonds insuffisants` ; `/pay <soi> 10` → refusé.
7. Se déconnecter puis revenir : le solde est conservé (`[rp_economy] loaded player ...`).
8. Depuis une autre ressource : `print(exports.rp_economy:getBalance(id))`.
