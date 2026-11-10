# FasoFoot Pass

FasoFoot Pass est une application Flutter qui rassemble la billetterie, les résultats et classements, la boutique des clubs et les outils d'exploitation pour le football burkinabè. Le backend s'appuie sur Supabase; YengaPay est prévu pour les paiements Mobile Money.

## Démarrer l'application

1. Installer Flutter/Dart selon les contraintes de `pubspec.yaml`.
2. Configurer l'URL Supabase et la clé publique dans `lib/Config/constants.dart`. Ne jamais embarquer une clé `service_role` ni une clé YengaPay dans l'application.
3. Installer les dépendances avec `flutter pub get`.
4. Lancer `flutter run` et vérifier le projet avec `flutter analyze`.

## Base de données

Les migrations doivent être appliquées dans l'ordre avec le projet Supabase lié :

1. `202610190001_ticket_catalog.sql` — billets, catalogue de tribunes, politiques d'accès et validation atomique du scan.
2. `202610190002_restrict_ticket_privileges.sql` — droits minimaux sur les billets et le catalogue.
3. `202610190003_sync_ticket_catalog.sql` — synchronisation des catégories de tribunes vers le catalogue de vente.
4. `202610190004_competitions_admin_security.sql` — compétitions, saisons, accès d'administration, rattachement des matchs et résultats.
5. `202610190005_marketplace_orders.sql` — commandes, lignes d'articles, réservation atomique du stock et historique supporter.
6. `202610190006_late_marketplace_payment_review.sql` — traitement des notifications de paiement tardives et statut de remboursement à suivre.
7. `202610190007_marketplace_club_handoff.sql` — coordonnées de remise, suivi par club et politiques d'accès des commandes.
8. `202610190008_catalog_handoff_readiness.sql` — rattachement de l'ancien catalogue et blocage de publication sans moyen de remise.
9. `202610200009_profile_on_signup.sql` — création automatique du profil supporter après inscription OTP.

Les migrations ultérieures maintiennent le catalogue et les paiements. La migration `202610210022_stadium_capacity_and_pricing.sql` ajoute les capacités au catalogue sans remplir de zones génériques, car leur structure dépend du stade. `202610260023_sync_existing_ticket_categories.sql` reprend les catégories existantes. `202610260024_sync_ticket_catalog_to_match_categories.sql` est volontairement sans effet : aucune correspondance fiable entre les stades des matchs et les zones n'est disponible. `20261105110945_ticket_catalog_checkout.sql` rend le catalogue source de vérité pour la réservation. `20261110124645_secure_order_and_ticket_confirmation.sql` réserve la confirmation des commandes au webhook signé et au rôle serveur, limite le scan aux agents de stade et super-administrateurs et transforme l'action de vérification en simple lecture d'état. `20261110125932_pickup_code_after_payment.sql` empêche l'exposition d'un code de retrait avant confirmation effective du paiement. `20261110130501_scope_payment_status_by_club.sql` applique aux lectures de statut les mêmes limites RLS que les écrans de commandes.

Avant un déploiement, vérifier les migrations avec `supabase migration list --linked`, puis simuler `supabase db push --linked --dry-run`. Ne pas pousser si la liste locale et distante diverge ou si une migration échoue; examiner le schéma et réconcilier explicitement l'historique avant toute application. Les comptes d'administration doivent recevoir leur rôle depuis un canal de confiance; l'application interdit aux utilisateurs de modifier eux-mêmes leur rôle. Les comptes `admin_club` doivent également avoir leur `managed_club_id` renseigné. Voir [la procédure de mise en service](docs/mise-en-service.md) pour créer le premier administrateur et configurer les points de retrait.

À la dernière vérification de FasoFootBD, les versions 022–024 n'étaient pas enregistrées dans l'historique distant. Elles ont été rendues compatibles avec le catalogue source de vérité, mais leur simulation (`--dry-run`) reste obligatoire avant `db push`.

Les matchs proviennent de `matches`, les scores de `match_results`, et les articles de `products`. Vérifier les matchs, résultats et produits existants comme données officielles avant lancement public.

## Paiements YengaPay

Les clés et secrets sont définis côté serveur Supabase, jamais dans l'application :

```sh
supabase secrets set YENGA_API_KEY=... YENGA_ORG_ID=... YENGA_PROJECT_ID=... YENGAPAY_WEBHOOK_SECRET=...
```

Pour le sandbox, configurer `YENGAPAY_BASE_URL=https://api.sandbox.yengapay.com/api/v1`. En production, utiliser `https://api.yengapay.com/api/v1`. Déployer seulement après la configuration des secrets :

```sh
supabase functions deploy initiate-yenga-payment
supabase functions deploy initiate-marketplace-payment
supabase functions deploy yenga-webhook --no-verify-jwt
```

Configurer ensuite dans la console YengaPay l'URL HTTPS du webhook Supabase et vérifier la signature avant d'accepter un paiement. Tester le parcours de bout en bout dans le sandbox avant de basculer en production.

## Rôles

- `supporter` : compte, club favori, consultation et achats.
- `admin_competition` : calendrier et résultats.
- `admin_club` : catalogue et commandes de son club.
- `agent_stade` : contrôle des billets.
- `super_admin` : gestion transversale.

Les règles RLS Supabase sont la frontière d'autorisation. Un bouton caché côté Flutter ne remplace jamais ces règles.

## Vision produit

Le périmètre, les rôles et le plan par étapes sont décrits dans [`docs/vision-produit.md`](docs/vision-produit.md).
