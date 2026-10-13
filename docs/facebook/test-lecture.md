# Facebook — test de lecture de la page

Test en **lecture seule** (requêtes GET uniquement) de l'accès à la page Facebook
via l'API Graph `v26.0`. Aucune publication ni modification n'a été effectuée.

- **Date / heure (UTC)** : 2026-10-13T14:58:45Z
- **Version API** : v26.0

## 1. Variables d'environnement

| Variable        | État    | Détail                        |
|-----------------|---------|-------------------------------|
| `FB_PAGE_TOKEN` | présent | longueur : 201 caractères     |
| `FB_PAGE_ID`    | présent | valeur : `122441264553755`    |

Le jeton a été passé en paramètre de requête `access_token` lu depuis la
variable d'environnement. Sa valeur n'apparaît nulle part dans ce document.

## 2. Page — `GET /{FB_PAGE_ID}?fields=id,name,fan_count,followers_count,link,category`

**Résultat : HTTP 200 (succès)**

| Champ             | Valeur                                       |
|-------------------|----------------------------------------------|
| `id`              | `122441264553755`                            |
| `name`            | الإعراب                                      |
| `category`        | كلية وجامعة                                  |
| `link`            | https://www.facebook.com/122441264553755     |
| `fan_count`       | 14 335                                       |
| `followers_count` | 14 335                                       |

## 3. Derniers posts — `GET /{FB_PAGE_ID}/posts?fields=id,created_time,message,permalink_url&limit=3`

**Résultat : HTTP 200 (succès)** — 3 posts renvoyés.

| # | Date (`created_time`)      | Message (120 premiers caractères)                                   |
|---|----------------------------|---------------------------------------------------------------------|
| 1 | 2025-09-03T04:15:34+0000   | كيف نعرب سورة الإخلاص ؟                                              |
| 2 | 2024-08-07T13:45:27+0000   | *(pas de champ `message` — post sans texte, probablement média seul)* |
| 3 | 2024-07-15T20:14:42+0000   | المرجو إعراب الجملة التالية إعرابا تاما: أَ ناجِحٌ التلميذان ؟          |

Identifiants des posts :

- `122441264553755_1325185586062180`
- `122441264553755_1016831273564281`
- `122441264553755_1001390218441720`

## 4. Jeton — `GET /debug_token?input_token=…&access_token=…`

**Résultat : HTTP 200 (succès)**

| Champ        | Valeur                                                                 |
|--------------|------------------------------------------------------------------------|
| `type`       | `PAGE`                                                                 |
| `expires_at` | `0` → **jamais** (jeton de page sans expiration)                       |
| `is_valid`   | `true`                                                                 |
| `app_id`     | `3867086130122680`                                                     |
| `scopes`     | `pages_show_list`, `business_management`, `pages_read_engagement`, `pages_read_user_content`, `pages_manage_posts`, `pages_manage_engagement`, `public_profile` |

Remarque : le jeton porte les permissions `pages_manage_posts` et
`pages_manage_engagement`, il permettrait donc aussi de publier. Ce test ne
les a pas utilisées.

## 5. Identité — `GET /me?fields=id,name`

**Résultat : HTTP 200 (succès)** — renvoie bien la **page**, pas un utilisateur.

| Champ  | Valeur             |
|--------|--------------------|
| `id`   | `122441264553755`  |
| `name` | الإعراب            |

L'`id` renvoyé par `/me` est identique à `FB_PAGE_ID` et au `profile_id` du
`debug_token` : le jeton est bien un jeton de page.

## 6. Erreurs

Aucune. Les quatre appels ont renvoyé HTTP 200 sans objet `error` dans la réponse.

## 7. Conclusion

- Les deux secrets sont définis et le jeton est valide, de type page, sans expiration.
- La lecture des informations de la page et de ses posts fonctionne.
- `/me` résout vers la page elle-même : le jeton est utilisable pour agir au nom de la page.
