# Mise en service de FasoFoot Pass

## Connexion et inscription

L'application utilise Supabase Auth avec e-mail et mot de passe. La confirmation d'adresse doit rester activée dans **Authentication → Providers → Email**. La politique de mot de passe est validée dans l'application (10 caractères minimum, au moins une lettre et un chiffre); configure aussi la longueur minimale serveur dans les paramètres de sécurité Auth.

Ajoute `fasofootpass://login-callback` dans **Authentication → URL Configuration → Redirect URLs**. Ce lien est déclaré dans Android et iOS et sert à la confirmation d'adresse, à la connexion sociale et à la récupération du mot de passe. Vérifie que le modèle d'e-mail de confirmation utilise le lien de confirmation Supabase afin que le `redirect_to` autorisé soit respecté.

Pour Google, active le fournisseur dans **Authentication → Providers**, crée un client OAuth Web dans Google Cloud, ajoute l'URL de rappel Supabase (`https://<project-ref>.supabase.co/auth/v1/callback`) parmi ses URI autorisées et saisis le client ID et le secret dans Supabase. Pour Apple, configure Sign in with Apple dans Apple Developer, crée un Services ID et une clé de connexion, puis renseigne les identifiants requis dans le fournisseur Apple Supabase. Les boutons sont présents dans l'application mais ces fournisseurs ne peuvent pas fonctionner tant que leurs secrets ne sont pas configurés.

Le service e-mail par défaut de Supabase est limité et convient aux essais. Configure un SMTP dédié avant l'ouverture publique pour fiabiliser les confirmations et les réinitialisations.

### Premier compte administrateur

Créez un compte par e-mail dans l'application, confirmez son adresse, puis connectez-vous. Les nouveaux comptes reçoivent automatiquement une ligne `supporter` dans `public.profiles`.

Pour promouvoir le premier compte, connectez-vous une première fois dans l’application, récupérez son identifiant dans **Supabase → Authentication → Users**, puis exécutez dans le SQL Editor en remplaçant l’UUID :

```sql
update public.profiles
set role = 'super_admin', managed_club_id = null
where id = 'UUID_DU_COMPTE_VERIFIE';
```

Vérifiez que la requête a modifié exactement une ligne. Pour un responsable de club, utilisez `role = 'admin_club'` et renseignez le `managed_club_id` du club. Ne donnez jamais ces rôles depuis l’application ou depuis une requête publique.

## Remise des articles

Le retrait se coordonne par téléphone : l’acheteur peut appeler le responsable marketing ou se rendre au siège de l’équipe. Dans l’onglet **Administration → Articles**, l’administrateur du club ou un super administrateur renseigne le téléphone et l’adresse du siège avec l’icône de contact. Il peut ensuite modifier l’article pour l’associer au bon club et le publier.

Une commande conserve un instantané de ces coordonnées. L’acheteur retrouve le téléphone et l’adresse dans **Boutique → Mes commandes**. L’onglet **Administration → Commandes** permet au club d’appeler l’acheteur et de suivre chaque ligne jusqu’à sa remise.

Les articles de démonstration existants ont été rattachés à l'équipe des Étalons, mais désactivés : aucun contact ni lieu de retrait vérifié n'était renseigné. Ils ne pourront être vendus qu'après configuration des coordonnées et réactivation par un administrateur. Le numéro ou l'adresse doivent être confirmés par le club avant publication.

## Clubs et programmation

Le super administrateur peut créer et modifier les fiches des clubs dans **Administration → Clubs**. Il y renseigne le nom officiel, le nom court et la ville, puis ajoute le logo JPG, PNG ou WebP (3 Mo maximum). Un administrateur de club ne voit et ne modifie que son club. Les logos sont publics afin d'être affichés dans la boutique et sur les matchs.

Dans **Administration → Matchs**, l'administrateur peut choisir les clubs enregistrés pour les équipes à domicile et visiteuse, ou saisir le nom manuellement pour une équipe internationale ou pas encore référencée. Quand un club enregistré est sélectionné, le match conserve son identifiant pour afficher le logo à côté de l'affiche. La date, l'heure, la ville, le stade, la compétition et le prix restent renseignés sur la fiche du match.

Chaque match est aussi rattaché à une saison / édition saisie par l'administrateur (par exemple `2026-2027`). Le nom est réutilisé pour les matchs suivants de la même compétition; la dernière saison utilisée devient la saison active. Les résultats publiés depuis un match héritent automatiquement de sa compétition et de sa saison. Dans **Résultats & classements**, le classement d'une ligue s'ouvre sur la saison active et peut être filtré par édition. Les résultats plus anciens qui n'étaient liés à aucun match restent accessibles dans « Toutes les saisons » et ne sont pas attribués automatiquement à une saison incertaine.

## YengaPay

Le serveur Supabase utilise les secrets `YENGA_API_KEY`, `YENGA_ORG_ID`, `YENGA_PROJECT_ID` et `YENGAPAY_WEBHOOK_SECRET`. Vérifiez leur présence dans la configuration sécurisée Supabase, puis configurez le webhook dans la console YengaPay :

```text
https://ltcxfrazkgseuyfstwkw.supabase.co/functions/v1/yenga-webhook
```

Activez les notifications du projet et vérifiez le parcours dans le sandbox avant toute ouverture publique. Ne copiez aucun secret dans le dépôt ou dans l’application mobile.

Seul le webhook YengaPay, après validation de sa signature, peut confirmer automatiquement une commande boutique. Le bouton de vérification dans l'application ne fait que relire l'état déjà confirmé par le webhook; ni le supporter ni un administrateur ne peut marquer une commande comme payée depuis l'application. Les commandes anciennes sans identifiant de transaction du prestataire doivent être rapprochées manuellement avec YengaPay et le club avant remise. Ne les marquez pas payées sur la seule base d'une capture d'écran ou d'une déclaration du client.

Le code de retrait est créé côté base uniquement lorsqu'une référence de transaction YengaPay accompagne le passage de la commande à `paid`. Il n'est pas communiqué lors de la création du paiement.

## Contrôle des billets

Le scan est réservé aux comptes `agent_stade` et `super_admin`. Le rôle `admin_club` gère les articles et les commandes du club, sans accès au contrôle des entrées. Un billet n’est validé que s’il est payé, non utilisé et associé à un match qui n’est ni annulé ni reporté. Un match terminé ou dont le coup d’envoi date de plus de six heures rend le billet expiré. La validation et le marquage comme utilisé sont effectués dans une seule transaction côté base de données.

Si l’appel à YengaPay expire ou renvoie une réponse serveur incertaine après l’envoi, le billet reste `pending` afin qu’un webhook de paiement tardif puisse encore le confirmer. Le supporter reçoit un message lui demandant de vérifier son compte Mobile Money avant de relancer le paiement. Les rejets explicites du prestataire restent marqués `failed`.

Chaque réservation bloque une place pendant 15 minutes. Si un paiement arrive après expiration alors qu'il n'y a plus de place, le billet est marqué `refund_required` et le webhook l'acquitte pour éviter les nouvelles tentatives. L'onglet **Administration → Remboursements**, réservé au super administrateur, liste ces paiements. Après traitement dans YengaPay, l'administrateur enregistre la référence et indique si le remboursement a été effectué ou si le paiement a été annulé/reversé. Cette action est auditée et ne déclenche pas elle-même un transfert d'argent.

## Mode maintenance

Dans **Administration → Maintenance**, le super administrateur peut activer ou désactiver le mode et modifier le message public (10 à 500 caractères). L'application vérifie l'état à l'ouverture puis toutes les 30 secondes et bloque les écrans après connexion tant que la maintenance est active. L'écran de connexion reste disponible pour permettre au super administrateur de se reconnecter; ce rôle conserve l'accès pour désactiver le mode. Le serveur vérifie également son rôle avant d'accepter tout changement; les autres rôles ne peuvent pas modifier ce réglage. Les nouvelles réservations de billets et commandes marketplace ainsi que les scans sont également bloqués en base. Les webhooks continuent de traiter les paiements engagés avant l'activation afin de ne pas perdre une confirmation tardive.

## Git et VS Code

Le dépôt Git local est initialisé sur la branche `main` avec le commit initial `79ba852`. VS Code peut le détecter directement depuis ce dossier. Aucun dépôt distant (`origin`) n'a été configuré. Les fichiers `.env`, le cache Supabase et les clés de signature sont ignorés par Git.
