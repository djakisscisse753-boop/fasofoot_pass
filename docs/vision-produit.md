# FasoFoot Pass — vision produit et plan de réalisation

## Vision

FasoFoot Pass devient le point d'entrée numérique du football burkinabè : les supporters suivent les compétitions, achètent des billets et des produits officiels, puis retrouvent leurs achats dans un espace personnel. Les clubs et organisateurs publient les matchs, résultats et articles. Les agents de stade contrôlent les billets rapidement, y compris lorsque le réseau est faible.

Le produit doit rester simple sur téléphone, fonctionner avec les moyens de paiement locaux et afficher uniquement des informations sportives vérifiées.

## Utilisateurs et responsabilités

| Rôle | Capacités principales |
| --- | --- |
| Supporter | Découvrir les compétitions, consulter les matchs, résultats et classements, acheter et télécharger ses billets, suivre un club, parcourir la boutique et gérer son profil. |
| Gestionnaire de compétition | Créer les compétitions et saisons, publier les matchs, saisir et corriger les scores, publier les classements lorsque le format n'est pas une ligue. |
| Gestionnaire de club | Gérer la fiche du club et son catalogue d'articles, suivre les commandes et les stocks de son club. |
| Agent de stade | Scanner les QR codes et voir immédiatement si le billet est valide, déjà utilisé, annulé ou expiré. |
| Administrateur plateforme | Gérer les rôles, les accès, la configuration, les signalements et l'audit. |

Les rôles sont contrôlés côté base de données et côté serveur. Masquer un bouton dans l'application ne constitue jamais une autorisation.

## Parcours produit

1. Le supporter se connecte par téléphone, choisit éventuellement son club et sa compétition préférée.
2. Il consulte les matchs disponibles avec stade, heure, tribunes, prix et places restantes.
3. Le serveur vérifie le prix et le stock, crée une commande en attente, puis ouvre le paiement Mobile Money.
4. Une notification de paiement signée confirme la commande. Le billet reçoit un QR code à usage unique et apparaît dans « Mes billets » avec téléchargement/partage.
5. À l'entrée, l'agent scanne le QR. La validation atomique empêche toute seconde entrée avec le même billet.
6. Le supporter consulte les scores et un classement calculé à partir des résultats officiels. Les formats à élimination directe affichent un tableau de compétition plutôt qu'un classement de ligue.
7. La boutique présente les articles officiels par club. Panier, stock, paiement et suivi de commande sont traités comme un flux distinct de la billetterie.

## Architecture fonctionnelle

- **Compétitions et calendrier :** compétitions, saisons, clubs, journées, matchs, stades et catégories de billets.
- **Résultats et classement :** résultats validés, historique des changements et classement calculé pour les compétitions de ligue. Les données officielles restent modifiables seulement par les rôles autorisés.
- **Billetterie :** catalogue lié aux zones et capacités, réservation à durée limitée, commande, transaction, billet, QR secret, scan et audit.
- **Marketplace :** produits, variantes/taille, stock, panier, commande, lignes de commande, paiement et livraison/retrait.
- **Compte supporter :** profil, club favori, billets, commandes, préférences et notifications.
- **Administration :** tableaux de bord adaptés aux rôles, publication, correction, gestion des stocks et journal d'audit.

## État technique connu

Le dépôt utilise Flutter et Supabase. La base distante contient `clubs`, `matches`, `match_results`, `match_ticket_categories`, `stadiums`, `stadium_zones`, `products`, `profiles`, `tickets`, `transactions`, `polls` et `votes`. Les schémas distants et locaux ont divergé sur les zones de stade; le catalogue `ticket_catalog` est la source de vérité pour les billets. Vérifier les matchs, résultats et produits comme données officielles avant lancement public.

L'application a déjà les premiers écrans d'authentification, billets, scan et boutique, mais certains écrans ne sont pas reliés à la navigation ou ne font qu'afficher une maquette. Le webhook YengaPay doit être configuré avec son secret de signature avant d'activer les paiements réels.

## Plan de réalisation

### Étape 1 — socle supporter

- Navigation réelle entre accueil, matchs, résultats/classement, billets, boutique et profil.
- Résultats filtrés par compétition et classement calculé depuis les scores terminés.
- Profil alimenté par Supabase, club favori et déconnexion.
- États de chargement, erreur, absence de données et rafraîchissement cohérents.

### Étape 2 — administration sportive

- Rôles séparés : compétition, club, scan et administration plateforme.
- Création/publication des compétitions, matchs, résultats et produits via des opérations serveur autorisées.
- Validation des scores, audit des modifications, prévention des doublons et publication explicite.

### Étape 3 — billetterie prête à encaisser

- Capacité/stock réellement réservé de façon transactionnelle, expiration des commandes et prévention de survente.
- Paiement YengaPay en sandbox, webhooks signés et idempotents, puis essais de bout en bout avant la production.
- Billet exportable, QR non devinable, contrôle unique et suivi de scan.
- Mode scanner tolérant aux coupures réseau avec synchronisation et règles de conflit définies avant production.

### Étape 4 — marketplace transactionnelle

- Détails produit, variantes, panier persistant, commande et décrémentation atomique du stock.
- Parcours de livraison ou retrait à définir avec les clubs; suivi de commande et remboursements à traiter.
- Paiement et webhook reliés à la commande, jamais à une simple action d'interface.

### Étape 5 — qualité et lancement

- Tests unitaires, intégration, règles RLS, flux de paiement sandbox et essais sur appareils Android modestes.
- Mesures de performance, sauvegardes, journalisation, procédures d'assistance et suivi d'incidents.
- Publication progressive avec quelques clubs/compétitions pilotes, puis extension.

## Indicateurs de réussite

- Taux de paiement confirmé et billets remis sans intervention manuelle.
- Temps moyen de validation à l'entrée et taux de doubles scans bloqués.
- Exactitude des résultats/classements comparée aux données officielles.
- Commandes marketplace honorées, erreurs de stock et remboursements.
- Taux de réussite sur réseau faible et appareils Android d'entrée de gamme.

## Avancement de cette première tranche

- Navigation Flutter reliée aux écrans de résultats/classement, de billets, de boutique et de profil.
- La confirmation des paiements marketplace est réservée au webhook YengaPay signé; l'interface ne peut que rafraîchir l'état du paiement.
- Le code de retrait est masqué tant qu'un paiement n'a pas été confirmé par le prestataire.
- Classement de ligue calculé depuis les résultats terminés; les autres compétitions ne sont pas présentées comme des ligues.
- Profil relié à Supabase avec modification du nom et du club favori; l'attribution des rôles reste réservée à un canal de confiance.
- Première console d'administration : programmer un match, publier/corriger un score, ajouter/masquer un produit selon le rôle.
- Rôles `admin_competition` et rattachement `managed_club_id`; les permissions de base empêchent un supporter de changer son rôle.
- Les commandes de boutique, le paiement de produits, le téléchargement de billets, l'édition complète du calendrier, le journal d'audit et le scan tolérant aux coupures restent à réaliser.
