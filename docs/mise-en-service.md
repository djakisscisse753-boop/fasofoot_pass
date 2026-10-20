# Mise en service de FasoFoot Pass

## Premier compte administrateur

Les nouveaux comptes créés par OTP téléphonique reçoivent automatiquement une ligne `supporter` dans `public.profiles`.

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

Les articles de démonstration existants ont été rattachés à l’équipe des Étalons, mais désactivés : aucun contact ni lieu de retrait vérifié n’était renseigné. Ils ne pourront être vendus qu’après configuration des coordonnées et réactivation par un administrateur. Le numéro ou l’adresse doivent être confirmés par le club avant publication.

## YengaPay

Le serveur Supabase utilise les secrets `YENGA_API_KEY`, `YENGA_ORG_ID` et `YENGA_PROJECT_ID`. Il lui manque encore `YENGAPAY_WEBHOOK_SECRET` pour confirmer les paiements. Configurez le secret dans Supabase, puis dans la console YengaPay :

```text
https://ltcxfrazkgseuyfstwkw.supabase.co/functions/v1/yenga-webhook
```

Activez les notifications du projet et vérifiez le parcours dans le sandbox avant toute ouverture publique. Ne copiez aucun secret dans le dépôt ou dans l’application mobile.

## Contrôle des billets

Le scan est réservé aux comptes `agent_stade` et `super_admin`. Le rôle `admin_club` gère les articles et les commandes du club, sans accès au contrôle des entrées. Un billet n’est validé que s’il est payé, non utilisé et associé à un match qui n’est ni annulé ni reporté. Un match terminé ou dont le coup d’envoi date de plus de six heures rend le billet expiré. La validation et le marquage comme utilisé sont effectués dans une seule transaction côté base de données.

Si l’appel à YengaPay expire ou renvoie une réponse serveur incertaine après l’envoi, le billet reste `pending` afin qu’un webhook de paiement tardif puisse encore le confirmer. Le supporter reçoit un message lui demandant de vérifier son compte Mobile Money avant de relancer le paiement. Les rejets explicites du prestataire restent marqués `failed`.

Chaque réservation bloque une place pendant 15 minutes. Si un paiement arrive après expiration alors qu’il n’y a plus de place, le billet est marqué `refund_required` et le webhook l’acquitte pour éviter les nouvelles tentatives. Cette situation exige encore une vérification et un remboursement manuel depuis YengaPay ; l’écran d’administration dédié reste à construire.

## Git et VS Code

Le dépôt Git local est initialisé sur la branche `main`. VS Code peut le détecter directement depuis ce dossier. Aucun dépôt distant (`origin`) n’a été configuré et aucun commit initial n’a été créé. Les fichiers `.env`, le cache Supabase et les clés de signature sont ignorés par Git.
