# API du backend

> **État : client livré, serveur non livré.** L'application contient le client (assistant IA et vérification des achats) et s'en passe proprement tant qu'aucune URL n'est configurée. Le serveur dans `backend/` est une ébauche Cloudflare Workers inachevée — sa vérification de types échoue encore — non versionnée, à ne pas déployer en l'état.

Ce document fixe l'architecture et le contrat visés, pour que l'implémentation reste cohérente.

## Architecture

```
Application Flutter  →  Backend MD SCANNER  →  Fournisseur d'IA
                                            →  API Google Play Developer
```

La clé du fournisseur d'IA et le compte de service Google ne vivent **que** sur le backend. Rien de secret n'est embarqué dans l'APK.

## Configuration côté application

| Variable de build | Rôle | Sans valeur |
| --- | --- | --- |
| `AI_BACKEND_URL` | URL de base du backend | Assistant IA désactivé, l'application fonctionne sans |
| `PURCHASE_VERIFICATION_URL` | Vérification serveur des achats | Vérification sur l'appareil |

## Contrat visé

### `POST /v1/purchases/verify`

Requête :

```json
{
  "packageName": "dev.marcelalle.mdscanner",
  "productId": "md_scanner_premium_yearly",
  "purchaseToken": "…",
  "type": "subscription"
}
```

Réponse :

```json
{
  "valid": true,
  "state": "active",
  "expiryTimeMillis": 1790000000000,
  "autoRenewing": true,
  "acknowledged": true
}
```

Le serveur refuse tout autre nom de package et tout identifiant de produit inconnu.

### `POST /v1/ai/tasks`

En-têtes : `X-Install-Id` (UUID aléatoire de l'installation), `Authorization: Bearer <jeton d'achat>` et `X-Product-Id`.

Corps : `{ "task", "outputLanguage", "documentText", "question"?, "targetLanguage"? }` avec `task` parmi `summary`, `section_summary`, `qa`, `extract`, `translate`, `flashcards`, `admin_analysis`.

Réponse : `{ "result": { … }, "quota": { "remaining": n } }`. L'application affiche `result` quelle que soit sa structure.

L'application n'envoie que du **texte** extrait localement, jamais de fichier, et seulement après consentement explicite de l'utilisateur.

Tâches prévues : résumé, résumé par section, questions-réponses, extraction de dates / montants / noms, traduction, fiches de révision, analyse de document administratif.

### `GET /v1/health`

État du service, sans secret.

## Exigences

- **Contrôle des coûts** : quota par installation, limitation de débit, budget global journalier, taille d'entrée et de sortie plafonnées.
- **Confidentialité** : traitement sans conservation ; ni le texte des documents, ni les questions, ni les réponses ne sont journalisés ou stockés.
- **Accès** : l'assistant étant une fonction Premium, chaque requête porte un jeton d'achat vérifié côté serveur.
- **Erreurs** : codes stables (`invalid_request`, `payload_too_large`, `premium_required`, `quota_exceeded`, `rate_limited`, `upstream_unavailable`) avec les statuts HTTP correspondants.
