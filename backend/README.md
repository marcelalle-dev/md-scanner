# MD SCANNER — backend

Petit serveur **Cloudflare Workers** (TypeScript) placé entre l'application et les services qui exigent un secret :

```
Application Flutter  →  ce backend  →  API Claude (assistant IA)
                                   →  API Google Play Developer (vérification des achats)
```

Aucune clé ne vit dans l'application. Le backend est **sans état** pour les contenus : ni le texte des documents, ni les questions, ni les réponses ne sont enregistrés ou journalisés.

> **État.** Le code passe la vérification de types et ses 93 tests (avec des doublures des API d'Anthropic et de Google). Il n'a **jamais été déployé** ni appelé avec de vraies clés : le premier déploiement est à valider par vos soins.

## Points d'accès

| Méthode | Chemin | Rôle |
| --- | --- | --- |
| `GET` | `/v1/health` | État du service et intégrations configurées (booléens, aucun secret) |
| `POST` | `/v1/ai/tasks` | Assistant documentaire |
| `POST` | `/v1/purchases/verify` | Vérification d'un achat Google Play |

### `POST /v1/ai/tasks`

En-têtes :

| En-tête | Valeur |
| --- | --- |
| `Content-Type` | `application/json` |
| `X-Install-Id` | UUID aléatoire de l'installation (quotas) |
| `Authorization` | `Bearer <jeton d'achat Google Play>` |
| `X-Product-Id` | identifiant du produit acheté |

Corps :

```json
{
  "task": "summary",
  "outputLanguage": "fr",
  "documentText": "…",
  "question": "seulement pour qa",
  "targetLanguage": "seulement pour translate"
}
```

`task` : `summary`, `section_summary`, `qa`, `extract`, `translate`, `flashcards`, `admin_analysis`.

Réponse : `{ "result": { … }, "usage": { … }, "quota": { "remaining": 29, "resetsAt": "…" } }`. La structure de `result` dépend de la tâche ; elle est validée par un schéma avant d'être renvoyée.

Un document trop long est **refusé** (`payload_too_large`, avec la limite et la taille reçue), jamais tronqué en silence.

### `POST /v1/purchases/verify`

```json
{
  "packageName": "dev.marcelalle.mdscanner",
  "productId": "md_scanner_premium_yearly",
  "purchaseToken": "…",
  "type": "subscription"
}
```

Réponse : `{ "valid": true, "state": "active", "expiryTimeMillis": 1790000000000, "autoRenewing": true, "acknowledged": true }`.

Tout autre nom de package et tout produit inconnu sont refusés.

### Erreurs

Corps `{ "error": { "code": "…", "message": "…" } }` avec le statut HTTP correspondant : `invalid_request` (400), `unauthorized` (401), `premium_required` (403), `payload_too_large` (413), `rate_limited` et `quota_exceeded` (429, avec `Retry-After`), `upstream_unavailable` (502–504), `internal_error` (500).

## Accès et maîtrise des coûts

- L'assistant est une fonction **Premium** : chaque requête porte un jeton d'achat, vérifié auprès de Google Play puis mis en cache quelques minutes. `FREE_DAILY_REQUESTS` (0 par défaut) peut offrir un petit quota d'essai aux installations non Premium.
- Quota journalier de requêtes et budget mensuel de jetons **par installation**.
- Limitation de débit par adresse IP.
- **Budget global journalier** : au-delà, le service répond `upstream_unavailable` jusqu'au lendemain. C'est le garde-fou contre une facture imprévue.
- Taille d'entrée et nombre de jetons de sortie plafonnés par tâche ; délai maximal sur l'appel au modèle.

Compteurs et cache vivent dans un **Durable Object SQLite**, disponible sur l'offre gratuite de Cloudflare.

Toutes les limites se règlent dans `wrangler.jsonc` (section `vars`).

## Modèle d'IA

Le modèle par défaut est `claude-opus-5-5`, avec un effort `low` et une sortie structurée. Le repli côté serveur en cas de refus est activé.

`ANTHROPIC_MODEL` et `ANTHROPIC_EFFORT` permettent d'en changer. Ordre de grandeur des tarifs (par million de jetons, entrée / sortie) : Opus 5.5 : 4 $ / 20 $ · Sonnet 5.5 : 2 $ / 10 $ · Haiku 5.5 : 0,10 $ / 0,50 $. Un modèle moins cher réduit la facture au prix d'analyses moins fines sur les documents complexes : c'est votre arbitrage, à mesurer sur vos propres documents.

## Installation locale

```bash
cd backend
npm ci
npm run check        # vérification de types + tests
cp .dev.vars.example .dev.vars   # puis renseignez les deux secrets
npm run dev
```

## Déploiement

1. Créer un compte Cloudflare et se connecter : `npx wrangler login`.
2. Déposer les secrets (ils ne figurent jamais dans le dépôt) :

   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   npx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON
   ```

3. Déployer : `npm run deploy`.
4. Vérifier : `GET https://<votre-worker>.workers.dev/v1/health`.
5. Fournir l'URL à l'application au build :

   ```bash
   flutter build appbundle --release \
     --dart-define=AI_BACKEND_URL=https://<votre-worker>.workers.dev \
     --dart-define=PURCHASE_VERIFICATION_URL=https://<votre-worker>.workers.dev/v1/purchases/verify
   ```

## À fournir par l'éditeur

| Élément | Où l'obtenir |
| --- | --- |
| Compte Cloudflare | https://dash.cloudflare.com |
| Clé d'API Anthropic | https://platform.claude.com → API keys |
| Compte de service Google Cloud | Console Google Cloud, puis invitation dans la Play Console (*Utilisateurs et autorisations*) avec le droit de consulter les données financières et les commandes |

## Confidentialité

- Seul du **texte** transite, jamais de fichier.
- Les journaux ne contiennent que : identifiant de requête, tâche, tailles, statut, durée. Les journaux d'invocation de la plateforme (URL, en-têtes) sont désactivés.
- Le texte des documents est traité comme une donnée non fiable : les consignes système le signalent au modèle, et la sortie est validée avant d'être renvoyée.
- L'option Play Integrity est documentée dans le code mais désactivée (`PLAY_INTEGRITY_MODE=off`).

## Structure

```
src/
  app.ts            routage
  ai/               requête, tâches et schémas, appel au modèle
  purchases/        vérification d'achat et droit Premium
  google/           jeton OAuth du compte de service, API Play
  limiter/          quotas, budgets et limitation de débit (Durable Object)
  http/             erreurs, identité, corps de requête
  logging/          journal structuré sans contenu
test/               tests vitest avec doublures
```
