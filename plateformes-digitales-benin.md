# 4 plateformes digitales pour gérer l'Agriculture, l'Éducation, la Santé et le Foncier au Bénin

> ## 🛑 RÈGLE N°1, NON NÉGOCIABLE : LA DÉMO NE DOIT JAMAIS PLANTER
>
> Phase actuelle = **présentation**. Les 4 plateformes sont hébergées sur **Vercel**, branchées à une **vraie base PostgreSQL sur Neon**, remplie de **données fictives** réalistes. Le front et le back sont réellement connectés : ce qui est créé pendant la démo est enregistré en base. Tout le projet est **conteneurisé avec Docker** pour que n'importe quel développeur puisse le reprendre en une commande. **Aucune fonctionnalité ne vaut une démo qui plante.**

### La phase actuelle : présentation

| Élément | Choix |
|---|---|
| Hébergement des apps | **Vercel**, **un projet Vercel par plateforme** (AgriSɛn, Kplɔn, Gbɛ/HEMORA, Anyigba, explorateur BéninChain) |
| Base de données | **PostgreSQL sur Neon** : un projet créé sur la console Neon, **une base par plateforme** (`agrisen`, `kplon`, `gbe`, `anyigba`, `beninchain`), extension **PostGIS** activée pour les cartes et parcelles |
| ORM et migrations | **Drizzle ORM** + **drizzle-kit** : schémas en TypeScript, migrations versionnées dans le dépôt |
| Données | **Données fictives** injectées par des scripts de *seed* : vraies communes, vrais marchés, vraies cultures, noms crédibles, groupes sanguins, parcelles dessinées sur la vraie carte. **Aucune donnée réelle** |
| Connexion front ↔ back | Pages Next.js (Server Components) et **Route Handlers `/api/v1/`** → couche *repository* → Drizzle → Neon. Validation Zod à l'entrée et à la sortie |
| Conteneurisation | **Docker** : `docker compose up` lance PostgreSQL + PostGIS en local, les migrations, le seed et les 5 apps. Vercel n'utilise pas Docker : Docker sert au développement local, à la reprise du projet et au futur hébergement national |
| Paiements, SMS, USSD, appels vocaux | **Mode simulation** : l'écran montre exactement ce que l'usager recevrait (SMS affiché, menu USSD dans un faux téléphone, audio joué dans le navigateur) ; les transactions simulées sont bien **enregistrées en base** |
| Blockchain | Empreintes calculées pour de vrai et stockées en base ; inscription BéninChain simulée par défaut ; ancrage réel OpenTimestamps ou testnet activable par variable d'environnement |
| Plan Vercel / Neon | Le plan gratuit de Vercel (Hobby) est réservé à un usage non commercial : pour présenter à un client, un ministère ou un partenaire, prévoir le **plan Pro**. Vérifier aussi les limites du plan Neon choisi (stockage, heures de calcul) |

### Structure du dépôt

```
benin-platforms/                     (monorepo Turborepo + pnpm)
├── apps/
│   ├── agrisen/                     Next.js — Agriculture
│   ├── kplon/                       Next.js — Éducation
│   ├── gbe/                         Next.js — Santé (intègre HEMORA)
│   ├── anyigba/                     Next.js — Foncier
│   └── beninchain-explorer/         Next.js — explorateur BéninChain
├── packages/
│   ├── db/
│   │   ├── src/schema/              schémas Drizzle, un dossier par plateforme
│   │   ├── src/client.ts            connexion (Neon en ligne, Postgres local en Docker)
│   │   ├── migrations/              migrations SQL générées par drizzle-kit
│   │   └── seed/                    scripts de données fictives, un par plateforme
│   ├── repositories/                accès aux données : les pages et API ne parlent qu'à eux
│   ├── schemas/                     schémas Zod partagés front / back
│   ├── ui/ · auth-npi/ · payments/ · channels/ · beninchain-sdk/ · geo/ · i18n-audio/
├── contracts/                       smart contracts Solidity (Foundry)
├── docker/
│   └── Dockerfile.next              image multi-étapes commune aux 5 apps
├── docker-compose.yml               environnement complet en local
├── .env.example                     toutes les variables, documentées
└── README.md                        « reprendre le projet en 5 minutes »
```

### La base Neon

**Création (console Neon)**
1. Créer un projet `benin-platforms`, **région la plus proche de la région Vercel choisie** (latence minimale entre les fonctions et la base).
2. Créer les bases : `agrisen`, `kplon`, `gbe`, `anyigba`, `beninchain`.
3. Activer PostGIS (dans la première migration de chaque base) : `CREATE EXTENSION IF NOT EXISTS postgis;`
4. Récupérer pour chaque base **deux chaînes de connexion** :
   - `DATABASE_URL` (**poolée**, via PgBouncer de Neon) → utilisée par les apps sur Vercel ;
   - `DATABASE_URL_UNPOOLED` (**directe**) → utilisée uniquement pour les migrations.
5. Relier Neon à Vercel (intégration officielle) : chaque projet Vercel reçoit ses variables automatiquement.

**Branches Neon (le gros atout pour la démo)**

| Branche | Rôle |
|---|---|
| `seed` | État de référence : schéma migré + données fictives. **On n'y touche jamais pendant une démo** |
| `main` | Branche de la démo en production, créée à partir de `seed` |
| `preview/*` | Une branche par *preview deployment* Vercel, créée automatiquement : on teste sans abîmer la démo |

**Bouton « Réinitialiser la démo »** = remettre la branche `main` à l'état de `seed` (*reset from parent* de Neon). En quelques secondes, toutes les données reviennent exactement à leur état de départ.

**Connexion depuis le code**

```ts
// packages/db/src/client.ts
import { drizzle as drizzleNeon } from "drizzle-orm/neon-http";
import { drizzle as drizzlePg } from "drizzle-orm/node-postgres";
import { neon } from "@neondatabase/serverless";
import { Pool } from "pg";
import * as schema from "./schema";

const url = process.env.DATABASE_URL!;
const isLocal = process.env.DB_DRIVER === "pg"; // Docker local

export const db = isLocal
  ? drizzlePg(new Pool({ connectionString: url }), { schema })
  : drizzleNeon(neon(url), { schema }); // driver HTTP serverless, idéal sur Vercel
```

```ts
// packages/db/drizzle.config.ts
import { defineConfig } from "drizzle-kit";
export default defineConfig({
  schema: "./src/schema/agrisen",        // un fichier de config par plateforme
  out: "./migrations/agrisen",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL_UNPOOLED! },
});
```

### Migrations et seed

| Commande | Effet |
|---|---|
| `pnpm db:generate` | Génère la migration SQL à partir des schémas Drizzle modifiés |
| `pnpm db:migrate` | Applique les migrations (connexion directe) |
| `pnpm db:seed` | Vide et remplit la base avec les données fictives (idempotent : relançable sans doublons) |
| `pnpm db:reset` | Migrate + seed depuis zéro (local) |

**Règles**
- **Les migrations ne tournent jamais pendant le build Vercel.** Elles tournent dans la **CI (GitHub Actions)**, avant le déploiement, sur la bonne branche Neon. Un build qui modifie la base en production = risque de casser la démo.
- **Jamais de modification manuelle du schéma** dans la console Neon : tout passe par une migration versionnée.
- **Seed déterministe** : graine aléatoire fixe (`faker.seed(2026)`), donc les mêmes données à chaque fois.
- **Personas fixes** créés en premier par le seed et utilisés comme fil rouge de chaque démo : Awa la maraîchère de Djidja, Bio la femme enceinte de Kalalé, un apprenti couturier de Porto-Novo, une famille propriétaire à Ouidah.
- **Volumes réalistes mais raisonnables** : par exemple quelques milliers de producteurs et parcelles, quelques centaines d'élèves par école pilote, de quoi rendre les tableaux de bord crédibles sans alourdir la base.

```ts
// packages/db/seed/agrisen.ts (extrait)
import { faker } from "@faker-js/faker/locale/fr";
import { db } from "../src/client";
import { producteurs, parcelles } from "../src/schema/agrisen";
import { COMMUNES, CULTURES } from "./referentiels"; // vraies communes et cultures du Bénin

faker.seed(2026);

await db.delete(parcelles); await db.delete(producteurs);

const awa = await db.insert(producteurs).values({
  npi: "FICTIF-0000001", nom: "Awa Houngbo", commune: "Djidja",
  langue: "fon", telephone: "+229 01 00 00 00 01", cultures: ["tomate", "piment", "oignon", "gombo"],
}).returning();
// … puis génération des autres producteurs, parcelles (polygones PostGIS), plans, prix, alertes
```

Tous les identifiants et numéros générés sont **marqués « FICTIF »** : impossible de confondre avec une vraie personne.

### Connexion front ↔ back

```
Page Next.js (Server Component)         Formulaire / action utilisateur
        │ lecture                                │ écriture
        ▼                                        ▼
repositories/  ◄────────── Route Handler /api/v1/... (validation Zod, contrôle du rôle)
        │
        ▼
Drizzle ORM ──► Neon PostgreSQL (+ PostGIS)
```

- **Lectures** : directement dans les Server Components via les *repositories* (pas d'appel HTTP inutile).
- **Écritures** : Route Handlers versionnés `/api/v1/` (ou Server Actions), validation Zod, contrôle d'accès, puis écriture en base.
- **Côté client** : TanStack Query pour le cache et la mise à jour de l'écran après chaque action.
- Les mêmes Route Handlers servent aussi le **faux téléphone USSD** et les **appels vocaux simulés** : quand le vrai opérateur sera branché, il appellera exactement la même URL.

### Docker : reprendre le projet en une commande

```yaml
# docker-compose.yml (extrait)
services:
  db:
    image: postgis/postgis:16-3.4
    environment: { POSTGRES_PASSWORD: dev, POSTGRES_USER: dev }
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data, ./docker/init-dbs.sql:/docker-entrypoint-initdb.d/init.sql]
    healthcheck: { test: ["CMD", "pg_isready", "-U", "dev"], interval: 5s, retries: 10 }

  migrate-seed:
    build: { context: ., dockerfile: docker/Dockerfile.tools }
    command: pnpm db:reset
    environment: { DB_DRIVER: pg, DATABASE_URL: postgres://dev:dev@db:5432/agrisen }
    depends_on: { db: { condition: service_healthy } }

  agrisen:
    build: { context: ., dockerfile: docker/Dockerfile.next, args: { APP: agrisen } }
    environment: { DB_DRIVER: pg, DATABASE_URL: postgres://dev:dev@db:5432/agrisen }
    ports: ["3001:3000"]
    depends_on: { migrate-seed: { condition: service_completed_successfully } }
  # kplon :3002 · gbe :3003 · anyigba :3004 · beninchain-explorer :3005

volumes: { pgdata: {} }
```

```dockerfile
# docker/Dockerfile.next — image multi-étapes, Next.js en mode standalone
FROM node:22-alpine AS deps
WORKDIR /repo
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile

FROM deps AS build
ARG APP
RUN pnpm turbo run build --filter=${APP}

FROM node:22-alpine AS run
ARG APP
WORKDIR /app
ENV NODE_ENV=production
ENV APP=${APP}
COPY --from=build /repo/apps/${APP}/.next/standalone ./
COPY --from=build /repo/apps/${APP}/.next/static ./apps/${APP}/.next/static
COPY --from=build /repo/apps/${APP}/public ./apps/${APP}/public
USER node
CMD ["sh", "-c", "node apps/$APP/server.js"]   # ARG n'existe pas à l'exécution : on passe par ENV
```

**Pour celui qui reprend le projet** :
```bash
git clone … && cd benin-platforms
cp .env.example .env
docker compose up --build
# → base créée, migrée, remplie de données fictives, 5 apps sur localhost:3001 à 3005
```

Pourquoi Docker alors que tout est sur Vercel :
- **Reprise immédiate** par un nouveau développeur, sans installer PostgreSQL ni configurer Neon.
- **Même environnement pour tous** : fin du « ça marche sur ma machine ».
- **Portabilité** : le jour où la production doit être hébergée au Bénin (cloud souverain, serveurs ANDF, hébergement santé), les mêmes images Docker y sont déployées telles quelles.

### Les 10 commandements de la démo

1. **Aucune dépendance extérieure obligatoire pendant la démo.** Mobile Money, SMS, USSD, OpenTimestamps, testnet, météo : mode simulation activé par défaut. Seules Vercel et Neon doivent répondre.
2. **La branche Neon `seed` est sacrée.** On ne la modifie que par migration + seed, jamais à la main.
3. **« Réinitialiser la démo »** remet `main` à l'état de `seed` avant chaque présentation.
4. **Migrations en CI uniquement**, jamais pendant le build Vercel, jamais à la main en production.
5. **Chaque plateforme reste un projet Vercel séparé, avec sa propre base** : une erreur sur l'une n'emporte pas les autres.
6. **On ne présente jamais la version en cours de développement.** On travaille sur les *preview deployments* et leurs branches Neon ; la démo tourne sur la **production figée**, version notée, rollback en un clic.
7. **Connexions poolées** (`DATABASE_URL` poolée + driver serverless Neon) : pas d'épuisement des connexions quand plusieurs personnes testent en même temps.
8. **Requêtes rapides** : index sur les colonnes filtrées, index spatiaux GiST sur les géométries, pas de calcul lourd dans une fonction Vercel. Tester la démo sur un téléphone moyen en 3G, la cible réelle.
9. **Mode hors ligne testé** : la PWA est installée et testée réseau coupé ; les actions faites hors ligne se synchronisent en base au retour du réseau.
10. **Répétition générale** la veille, sur l'appareil et le réseau de la présentation. Une capture vidéo de la démo est toujours prête en secours.

### Et le VPS (Cloud VPS 6 : 6 vCPU, 12 Go RAM, 200 Go SSD, 2 snapshots, 6 €/mois) ?
Il n'est **pas nécessaire en phase de présentation** : les apps sont sur Vercel et la base sur Neon. Il servira plus tard pour ce que ni Vercel ni Neon ne font : un **nœud BéninChain (Besu)** et les services qui tournent en continu (versements Lightning de HEMORA via Breez, tâches planifiées d'ancrage). Les images Docker du projet y seront déployées directement. La règle restera la même : **aucun build Next.js sur le VPS, un plafond de RAM par conteneur, une marge de 2,5 Go jamais consommée, sauvegardes hors du serveur**.

### Ce que cette phase n'est pas
- **Ce n'est pas la production.** La section 6 décrit la cible nationale. Aucune donnée réelle de santé, de foncier ou d'identité ne passe par la version de présentation : uniquement des données fictives.
- Vercel et Neon sont des infrastructures étrangères : parfait pour présenter, mais la production devra être validée au regard de la protection des données et de la future loi sur la localisation des données (voir 6.4). Grâce à Docker et à PostgreSQL standard, le passage vers une infrastructure béninoise se fait sans réécrire le code.

---

> Chaque plateforme est pensée comme **l'outil de gestion du domaine** : l'État pilote, les acteurs travaillent dedans au quotidien, le citoyen y accède même sans savoir lire et sans smartphone.
> **La blockchain est au cœur des 4 plateformes** : elle garantit que toute donnée officielle validée (un titre, un diplôme, une ordonnance, une vente, un versement d'aide) ne peut plus être modifiée ou effacée en silence.
> **Une seule technologie, quatre déploiements** : tout le code applicatif est en **Next.js**, hébergé sur **Vercel**, avec **PostgreSQL sur Neon** et **Docker** pour la reprise du projet ; chaque plateforme est une application indépendante, déployée selon ses usagers et la sensibilité de ses données (voir section 6).
> Alignement : programme Wadagni–Talata 2026-2033. Inspirations : France, États-Unis, Afrique. Contraintes : réalités béninoises actuelles.

---

## 0. Le socle commun aux 4 plateformes

Les 4 plateformes ne sont pas 4 silos. Elles reposent sur un **socle numérique partagé**. C'est l'application du principe « dites-le-nous une seule fois » du programme : une information fournie une fois à l'administration (identité, adresse, parcelle, état civil) n'est plus jamais redemandée, parce que les bases sont interconnectées.

```
┌─────────────────────────────────────────────────────────────────────┐
│     AgriSɛn        Kplɔn          Gbɛ          Anyigba              │
│  (Agriculture)  (Éducation)     (Santé)       (Foncier)             │
├─────────────────────────────────────────────────────────────────────┤
│                    SOCLE COMMUN (services partagés)                 │
│  Identité NPI · Paiement Mobile Money · Notifications SMS/voix      │
│  Passerelle USSD · Moteur de langues (audio) · Cartographie PostGIS │
│  Coffre-fort documents · Journal d'audit · Tableau de bord national │
├─────────────────────────────────────────────────────────────────────┤
│        🔗 BÉNINCHAIN — COUCHE DE CONFIANCE (blockchain nationale)    │
│  Empreintes immuables · Smart contracts · Attestations vérifiables  │
│  Nœuds : ANDF · Ministères · ARS · Universités · Notaires · CSAF    │
│          Cour des comptes · Communes · Autorité de protection données│
├─────────────────────────────────────────────────────────────────────┤
│  CANAUX : Web/PWA · App mobile · USSD *xxx# · Appel vocal (IVR)     │
│           WhatsApp · SMS · Guichet assisté (relais communautaire)   │
└─────────────────────────────────────────────────────────────────────┘
```

| Service commun | Rôle |
|---|---|
| **Identité (NPI)** | Même identifiant pour le paysan, l'élève, le patient, le propriétaire. Connexion par NPI + code OTP SMS |
| **Paiement** | MTN MoMo, Moov Money, Celtiis Cash. Encaissements, versements d'aides, ventilation automatique |
| **Notifications** | SMS, appel vocal pré-enregistré en fon, yoruba, bariba, dendi, goun, adja…, push, WhatsApp |
| **Mode assisté** | Un relais (agent ATDA, agent de santé communautaire, enseignant, agent foncier) agit pour le compte d'un citoyen, avec son consentement tracé |
| **Cartographie** | Même référentiel géographique (départements, communes, arrondissements, villages, parcelles) |
| **Accessibilité** | Norme WCAG 2.1 AA, lecture audio de chaque écran, contrastes élevés, sous-titres, pictogrammes |
| **Offline** | Les apps terrain fonctionnent sans réseau et synchronisent au retour de la connexion |
| **BéninChain** | Couche blockchain commune qui rend immuables les données officielles des 4 plateformes (détail en 0.1) |

### 0.1 BéninChain : la blockchain au cœur des 4 plateformes

#### Pourquoi une blockchain commune
Dans les 4 domaines, le problème de fond est le même : **la confiance dans la donnée**.
- Agriculture : un versement d'aide ou une indemnisation a-t-il vraiment été payé à la bonne personne ?
- Éducation : ce diplôme, ce relevé de notes, ce résultat d'examen sont-ils authentiques ?
- Santé : cette ordonnance a-t-elle déjà été utilisée ? Ce certificat de vaccination est-il vrai ? Qui a consulté mon dossier ?
- Foncier : ce titre a-t-il été modifié ? Cette parcelle a-t-elle déjà été vendue ?

Une base de données classique peut être modifiée par quiconque a les bons accès, y compris un agent malhonnête, sans laisser de trace fiable. La blockchain rend chaque écriture **horodatée, signée, chaînée et impossible à réécrire sans que tout le réseau le voie**.

#### Le principe fondamental : on met la preuve sur la chaîne, pas la donnée

```
DONNÉE OFFICIELLE (base de la plateforme, protégée, chiffrée)
   ex. ordonnance, diplôme, acte de vente, paiement
        │
        │ 1. empreinte SHA-256 (+ sel secret pour les données personnelles)
        ▼
BÉNINCHAIN (blockchain permissionnée nationale)
   enregistre : empreinte · type d'événement · horodatage · signature de l'institution
        │
        │ 2. ancrage périodique (ex. toutes les heures) de la racine de Merkle
        ▼
BITCOIN via OpenTimestamps (preuve vérifiable par le monde entier)
```

- **Aucune donnée personnelle en clair** sur la chaîne : ni nom, ni diagnostic, ni note, ni coordonnées. Seulement des empreintes.
- Vérifier une donnée = recalculer son empreinte et la comparer à celle de la chaîne. Si un seul caractère a changé, l'empreinte ne correspond plus → **falsification détectée**.
- Les **règles métier sensibles** sont écrites en smart contracts : verrou anti-double-vente, ordonnance à usage unique, ventilation des « 3 parts », versements d'aides conditionnels. Personne, même un administrateur, ne peut contourner la règle sans que ce soit visible.

#### Ce qui est inscrit sur BéninChain, plateforme par plateforme

| Plateforme | Événements rendus immuables |
|---|---|
| **AgriSɛn** | Enregistrement d'un producteur et de ses parcelles · ventes et paiements · ventilation des 3 parts · crédits intrants et remboursements · déclenchement et paiement des indemnisations d'assurance · traçabilité des lots (du champ à l'export) · encaissements des recettes publiques · subventions versées |
| **Kplɔn** | Résultats officiels d'examens (CEP, BEPC, BAC) · diplômes et relevés · validations de compétences et certifications des enseignants · attributions de bourses · versements des transferts fléchés éducation (empreinte des présences agrégées qui les déclenchent) |
| **Gbɛ** | Émission et délivrance des ordonnances · certificats de vaccination · accréditations des soignants · consentements du patient (donnés, retirés) · journal des accès au dossier · traçabilité des lots de médicaments · versements des transferts fléchés santé |
| **Anyigba** | Création des parcelles · titres et certificats · mutations · verrous et litiges · successions · actes notariés et d'huissier · calcul et reversement de la plus-value |

#### Les attestations vérifiables (le citoyen porte sa preuve)
Chaque document officiel important devient une **attestation vérifiable** (norme W3C *Verifiable Credentials*) : diplôme, certificat de vaccination, titre foncier, carte de producteur, attestation d'assurance.
- Le document porte un **QR code**.
- N'importe qui (employeur, pharmacie, banque, douane, frontière) scanne le QR → l'application vérifie l'empreinte et la signature de l'institution sur BéninChain → ✅ authentique ou ❌ falsifié.
- Pas besoin d'appeler l'administration, pas besoin d'internet rapide : la vérification tient en quelques octets.

Inspirations : Blockcerts (diplômes du MIT sur blockchain), EBSI (infrastructure blockchain européenne pour diplômes et attestations), X-Road et la chaîne KSI d'Estonie (intégrité des registres publics, dont la santé), Géorgie (titres fonciers).

#### Concilier immutabilité et protection des données personnelles
Le Bénin protège les données personnelles par son Code du numérique, avec une autorité de protection des données. Une blockchain qui « n'oublie jamais » doit respecter ce cadre. Les solutions :

| Exigence | Comment on la respecte |
|---|---|
| **Confidentialité** | Seules des empreintes salées sont sur la chaîne ; la donnée reste dans la base chiffrée de la plateforme |
| **Droit de rectification** | On ne modifie jamais : on ajoute une **nouvelle version** qui annule la précédente. L'historique montre qu'une correction a eu lieu, par qui et pourquoi (c'est même un gain de transparence) |
| **Droit à l'effacement** | **Effacement cryptographique** : la donnée hors chaîne et son sel sont détruits ; l'empreinte restante sur la chaîne ne permet plus de rien retrouver |
| **Secret médical** | Aucune information médicale sur la chaîne ; seuls les accès et les consentements sont tracés |
| **Minimisation** | Pour les présences scolaires ou les suivis de santé, on inscrit des empreintes de lots agrégés, pas chaque ligne individuelle |

#### Architecture et gouvernance

| Élément | Choix |
|---|---|
| Type de chaîne | **Consortium permissionné** (Hyperledger Besu, compatible Ethereum) : seuls des acteurs institutionnels identifiés valident les blocs |
| Consensus | QBFT (tolère des nœuds défaillants ou malhonnêtes, très peu énergivore, rapide) |
| Nœuds validateurs | ANDF, ministères (Agriculture, Éducation, Santé, Finances), ARS, universités, Chambre des notaires, CSAF, communes, Cour des comptes. L'autorité de protection des données et des organisations de la société civile peuvent être **nœuds observateurs** |
| Ancrage public | Racine de Merkle horodatée sur **Bitcoin via OpenTimestamps** (standard ouvert, gratuit, déjà éprouvé dans HEMORA) : même le consortium ne peut pas réécrire l'histoire, et n'importe qui peut vérifier sans dépendre de l'État |
| Clés des institutions | Stockées dans des modules matériels sécurisés (HSM), signature à plusieurs pour les actions critiques |
| Clés des citoyens | Invisibles pour l'usager : portefeuille géré par l'institution, rattaché au NPI, récupérable en agence ; l'usager agit par app, USSD ou appel vocal |
| Mode hors ligne | L'app terrain signe l'événement sur l'appareil ; il est inscrit sur la chaîne à la synchronisation, avec deux horodatages (création sur le terrain, inscription sur la chaîne) |
| Performance | Les événements sont regroupés en lots (arbres de Merkle) : des milliers d'écritures par seconde, coût quasi nul |
| Hébergement | Nœuds dans les data centers nationaux, répartis dans plusieurs villes |

#### Ce que la blockchain ne fait pas (à dire clairement)
- Elle ne garantit pas que la donnée saisie est **vraie** : elle garantit qu'elle n'a **pas été modifiée** depuis. D'où les validations humaines avant inscription (géomètre et voisins pour une parcelle, jury pour un examen, soignant pour une ordonnance).
- Elle ne remplace ni l'ANDF, ni le notaire, ni le médecin, ni l'enseignant : elle rend leur travail **opposable et vérifiable**.
- Sa valeur juridique dépend de la loi : il faudra reconnaître la preuve blockchain dans les textes (code du numérique, loi-cadre sur l'innovation).

---

## 1. AgriSɛn — Plateforme nationale de gestion de l'agriculture

### 1.1 Mission
Gérer toute la chaîne agricole sur un seul outil : **produire mieux** (conseil, alertes), **vendre mieux** (marché, prix), **protéger le producteur** (assurance, épargne, retraite) et **donner à l'État une vue en temps réel** du secteur.

**Engagements du programme couverts, et comment la plateforme y répond**

| Engagement du programme | Réponse d'AgriSɛn |
|---|---|
| Tripler les rendements de certaines filières (manioc, maïs) et doubler ceux d'autres (cajou, riz, soja, karité) grâce à un meilleur encadrement : semences à haut rendement, intrants de qualité, mécanisation, bonnes pratiques | Planificateur de culture, conseil technique en langues locales, commande d'intrants et réservation de mécanisation dans un même outil |
| Protection sociale des agriculteurs : assurance, épargne, retraite, avec une production répartie en trois parts (revenu immédiat, remboursement des intrants, fonds de prévoyance) | Ventilation automatique de chaque paiement Mobile Money en 3 parts, assurance récolte indicielle, épargne consultable par appel vocal |
| Mécanisme de rachat et revente partielle des récoltes pour alimenter le fonds de protection et compenser les mauvaises récoltes | Module Marché avec séquestre et traçabilité des volumes, base de calcul des compensations |
| Modernisation par le numérique : agriculture de précision (drones, IA, capteurs), suivi des cultures, traçabilité, accès aux marchés y compris export | Surveillance phytosanitaire et climatique, traçabilité des lots par QR, accès aux exigences export |
| Mini-stations météo, capteurs de sol, drones phytosanitaires, plateformes mobiles d'accès aux intrants et aux marchés | Intégration des données météo et capteurs dans le calcul de risque et le recalcul des plans |
| Meilleur accès au financement et renforcement du Fonds National de Développement Agricole (FNDA) | Dossier de crédit alimenté automatiquement par le plan, l'historique de production et les ventes |
| 13 filières locomotives, 8 interprofessions, 7 pôles de développement agricole, sociétés spécialisées (mécanisation, semences, irrigation, agrégation, aviculture) | Chaque acteur a son espace ; tableau de bord par filière pour les interprofessions |
| Unités industrielles de transformation à façon accessibles à tous les producteurs | Réservation de créneaux de transformation quand le planificateur prévoit un surplus |

### 1.2 Qui utilise la plateforme et pour quoi

| Acteur | Ce qu'il fait dans AgriSɛn |
|---|---|
| **Producteur** | S'enregistre (ou est enregistré par un agent), déclare ses parcelles et cultures, reçoit conseils et alertes, vend sa récolte, suit son épargne/assurance |
| **Coopérative / groupement** | Gère ses membres, agrège les récoltes, négocie avec les acheteurs, distribue les intrants |
| **Agent ATDA (conseiller terrain)** | Visite, diagnostic, signalements de ravageurs, formation, accompagne les producteurs non alphabétisés |
| **Acheteur / transformateur / exportateur** | Publie ses besoins, achète, suit la traçabilité des lots |
| **Fournisseur d'intrants** (SoDeSeP, distributeurs) | Catalogue, commandes, crédit intrants, suivi des remboursements |
| **SoNaMA / prestataires mécanisation** | Réservation de tracteurs et de services de labour |
| **Interprofessions** | Statistiques de filière, prix de référence, campagnes |
| **Ministère de l'Agriculture** | Pilotage national : surfaces, rendements prévus, alertes, subventions, recettes |
| **FNDA / banques / SFD / assureurs** | Crédit agricole, assurance récolte, sur base de l'historique réel du producteur |

### 1.3 Modules fonctionnels

**M1. Registre des exploitants et des exploitations**
- Fiche producteur liée au NPI : identité, langue, téléphone, coopérative, filières.
- Parcelles cartographiées (tracé GPS en marchant sur les limites), culture, surface, date de semis.
- Lien direct avec Anyigba (foncier) : le producteur prouve son droit d'usage sur la terre.

**M2. Planificateur de culture — « l'agronome de poche »** ⭐ *module phare*

> **Du « je cultive au feeling » à « j'ai un plan écrit, comme une entreprise ».**

**Le problème concret**
Un maraîcher a 1 hectare et veut faire tomate, piment, oignon et gombo. Il décide de tête, par habitude. Résultat : trois semaines où tout arrive à maturité en même temps (il brade, une partie pourrit), puis deux mois sans rien à vendre (pas de revenu, clients perdus). Il ne fait pas de rotation, donc les maladies du sol s'installent.

**Ce que fait l'outil**
Le producteur répond à 5 questions simples (écran pictogrammes, USSD ou appel vocal, ou avec l'agent ATDA) :
1. **Où** es-tu ? (commune → zone climatique et saisons des pluies)
2. **Quel sol** ? (sableux / argileux / terre de bas-fond, en images)
3. **Quelle surface** ? (en m², en hectares ou en nombre de planches)
4. **Qu'est-ce que tu veux cultiver ?** (icônes des légumes)
5. **As-tu de l'eau en saison sèche ?** (puits, forage, rivière, rien)

En 2 minutes, il reçoit **son plan de l'année** :
- quoi semer en pépinière chaque semaine,
- quand repiquer, sur quelle planche,
- quand récolter et combien il peut espérer,
- ce qui remplace quoi sur chaque planche après la récolte (rotation).

**Le moteur de planification (la logique derrière)**

| Étape | Ce que calcule le moteur |
|---|---|
| 1. Fenêtres possibles | Pour chaque culture, les mois favorables selon la zone : le Sud a deux saisons des pluies, le Nord une seule ; la tomate souffre des maladies en pleine saison des pluies ; l'oignon préfère la saison sèche fraîche. Les mois à risque sont signalés en 🔴 |
| 2. Cycles | Durée pépinière → repiquage → première récolte → fin de récolte pour chaque culture (ex. gombo en semis direct, oignon avec longue pépinière) |
| 3. Rétro-planning | On part de l'objectif **« avoir quelque chose à vendre chaque semaine »** et on remonte aux dates de semis |
| 4. Échelonnement | Au lieu d'un gros semis, plusieurs petits semis décalés (ex. tomate toutes les 3-4 semaines) pour lisser les récoltes |
| 5. Rotation | Règles de famille : ne pas remettre tomate ou piment (même famille) sur une planche qui vient d'en porter ; alterner avec oignon ou gombo |
| 6. Répartition de la surface | Selon l'eau disponible, la main-d'œuvre, et les **prix du marché** : plus de surface sur les cultures dont les prix montent à la période de récolte |
| 7. Contrôle | Pas plus de planches occupées que disponibles, pas de pic de travail impossible, pas de culture en saison défavorable sans irrigation |

> Les cycles et fenêtres sont des valeurs de référence à **calibrer avec l'INRAB et les ATDA** par zone agroécologique. Le moteur est une base de règles lisibles, pas une boîte noire : l'agent peut expliquer chaque décision.

**Ce que reçoit le producteur**
- **Le calendrier semaine par semaine** : une carte par semaine avec les icônes des actions (semer, repiquer, arroser, traiter, récolter).
- **Le plan des planches** : une grille de son terrain, chaque planche colorée par culture, qui change au fil de l'année.
- **La courbe « avant / après »** : ses récoltes prévues au feeling (un gros pic puis le vide) contre ses récoltes avec le plan (un flux régulier). C'est l'image qui convainc.
- **La prévision de revenus** mois par mois, avec les prix de référence du module Marché.
- **Rappels vocaux** chaque lundi dans sa langue : « Cette semaine : semez la tomate en pépinière, récoltez le gombo planche 4. »
- **Version papier** imprimable (calendrier mural à pictogrammes) pour ceux qui n'ont pas de smartphone.

**Le plan vit avec la réalité**
- Le producteur confirme les actions faites (une touche) ; si un semis est en retard, le plan se recalcule.
- Une alerte ravageur (M3) ou météo (pluie tardive, sécheresse) décale automatiquement les dates concernées.
- À la fin de la saison, on compare prévu / réalisé : le plan de l'année suivante s'améliore.

**Ce que ça débloque pour le reste de la plateforme**
- **Marché (M4)** : l'acheteur voit à l'avance les volumes qui arrivent → contrats de livraison régulière, prévente possible.
- **Crédit (M5)** : un plan écrit + un historique = un dossier de crédit crédible pour le FNDA ou une SFD. Le crédit intrants est calé sur les dates de semis.
- **Assurance (M6)** : les surfaces et dates de semis déclarées servent de base à l'assurance récolte.
- **État (M9)** : en agrégeant les plans, le ministère voit **avant** qu'elles n'arrivent les périodes de surproduction ou de pénurie de tomate, d'oignon… par zone, et peut orienter les producteurs ou organiser le stockage et la transformation (unités de transformation à façon prévues par le programme, où le producteur apporte sa récolte et repart avec un produit transformé qui se conserve et se vend mieux).

**Inspirations**
France : Elzeard et les planificateurs maraîchers utilisés en maraîchage diversifié, outils des chambres d'agriculture. USA : Tend, Seedtime, calculateurs de semis échelonnés (succession planting) des semenciers. Open source : Qrop (planificateur maraîcher). La différence au Bénin : entrée par la voix et les pictogrammes, fenêtres calées sur les saisons locales, et lien direct avec le marché, le crédit et l'assurance.

**Indicateurs propres au module**
Nombre de plans générés · part des semaines de l'année avec des récoltes à vendre · réduction des pertes post-récolte déclarées · écart entre revenu prévu et réalisé · taux de suivi des rappels.

**M2 bis. Conseil technique**
- Fiches techniques audio et vidéo courtes par culture, en langues locales, reliées à chaque étape du plan (« comment repiquer la tomate »).

**M3. Surveillance phytosanitaire et climatique (alerte précoce)**
- Signalements géolocalisés de ravageurs et maladies (photo, ou touche USSD) par producteurs et agents.
- Croisement avec la météo (Météo-Bénin / ANAM, stations et capteurs locaux, données satellites).
- Calcul d'un niveau de risque par commune : 🟢 🟠 🔴.
- Validation par un expert, puis diffusion d'alertes ciblées (culture + zone) en SMS et appel vocal.
- Suivi de la réponse : combien de producteurs ont reçu, compris, traité.

**M4. Marché agricole**
- Offres de vente (vocales ou écrites), demandes d'achat, mise en relation.
- Prix du jour par marché (Dantokpa, Glazoué, Malanville, Parakou…), consultables par SMS.
- Paiement Mobile Money sécurisé (séquestre : l'argent est libéré à la livraison).
- Accès à l'export : exigences qualité, certifications, traçabilité des lots (QR sur les sacs/cartons).

**M5. Intrants, mécanisation et crédit**
- Commande d'intrants (semences, engrais, produits phytosanitaires autorisés).
- Réservation de services de mécanisation (modèle Hello Tractor).
- Crédit intrants remboursé automatiquement à la vente.
- Dossier de crédit FNDA / SFD alimenté par l'historique de production.

**M6. Protection sociale du producteur (les « 3 parts »)**
- À chaque vente passant par la plateforme, ventilation automatique : revenu immédiat / remboursement des intrants / fonds de prévoyance.
- Assurance récolte indicielle : si la pluie mesurée dans la zone passe sous un seuil, indemnisation automatique (modèle ACRE Africa, Kenya).
- Épargne et retraite agricole consultables par appel vocal.

**M7. Règlementation et information**
- Pesticides autorisés / interdits, normes d'export, droits des producteurs, aides disponibles.
- Format audio, pictogrammes, questions fréquentes par serveur vocal.

**M8. Recettes publiques et redevances**
- Collecte des taxes de marché, redevances, frais de services via Mobile Money.
- Reçus numériques, traçabilité des encaissements, fin des collectes en espèces non tracées.

**M9. Tableau de bord national**
- Surfaces emblavées par filière et commune, production prévue, alertes en cours, prix, volumes vendus, crédits, sinistres.
- Export des données pour la statistique agricole et les interprofessions.

**M10. Warrantage digital — « stocker pour vendre au bon prix »** ⭐ *module innovant prioritaire*

> **Le problème** : juste après la récolte, tout le monde vend en même temps, les prix s'effondrent. Le producteur a besoin d'argent tout de suite (scolarité, dettes, santé), donc il brade. Trois mois plus tard, le même maïs vaut beaucoup plus cher, mais il n'en a plus.

**Le principe (le warrantage existe déjà en Afrique de l'Ouest, il manque l'outil de confiance)**
1. Le producteur ou sa coopérative dépose sa récolte dans un **magasin agréé** (coopérative, SoDAPA, entrepôt privé certifié).
2. Le magasinier pèse, contrôle la qualité (humidité, propreté), et émet un **récépissé d'entrepôt numérique** : produit, quantité, qualité, date, magasin.
3. Le récépissé est **tokenisé sur BéninChain** : impossible de le dupliquer ou de le gager deux fois.
4. Le producteur l'utilise comme **garantie** : la SFD ou la banque accorde un crédit (en général une partie de la valeur du stock), versé en Mobile Money en quelques heures.
5. Quand les prix remontent, il vend depuis la plateforme ; le smart contract rembourse d'abord le crédit, puis lui verse le reste (et alimente les 3 parts).

**Pour qui**
- Producteur : il n'est plus obligé de brader.
- SFD / banque : garantie réelle, vérifiable, contrôlable à distance → elle prête enfin au monde rural.
- Magasin agréé : revenu de stockage.
- État : régulation des prix et visibilité sur les stocks nationaux (sécurité alimentaire).

**Écrans clés** : dépôt au magasin (tablette du magasinier, hors ligne), récépissé avec QR, demande de crédit en un clic, suivi du prix et bouton « vendre maintenant », tableau des stocks par commune pour l'État.

**Garde-fous** : magasins audités et assurés, contrôle qualité photographié, relevés de température et d'humidité, inventaires inopinés dont le résultat est aussi inscrit sur la chaîne.

**M11. Chambres froides solaires « payer pour stocker »**
- **Le problème** : la tomate, le piment, le gombo pourrissent en quelques jours ; une grande partie peut être perdue entre champ et marché.
- **La solution** : chambres froides solaires installées près des marchés et des bassins maraîchers, louées **à la caisse et au jour** (modèle ColdHubs, Nigeria).
- Réservation et paiement par Mobile Money, USSD ou sur place auprès de l'opérateur.
- **Lien direct avec le planificateur (M2)** : quand le plan prévoit un pic de récolte, la plateforme propose de réserver des caisses à l'avance.
- Capteurs de température remontés dans la plateforme : l'acheteur sait que la chaîne du froid a été respectée.
- Modèle économique : opérateurs privés, équipement cofinancé (partenaires, fonds d'amorçage), tarif régulé.

**M12. Diagnostic de maladies par photo, hors ligne**
- Le producteur ou l'agent photographie une feuille ou un fruit malade.
- Un **modèle d'IA embarqué dans le téléphone** (fonctionne sans réseau) propose un diagnostic parmi les maladies et ravageurs courants au Bénin (modèle PlantVillage Nuru).
- Réponse **en audio dans sa langue** : ce que c'est, quoi faire, quel produit autorisé utiliser, ou « appelez votre agent ».
- Chaque diagnostic géolocalisé alimente la **surveillance phytosanitaire (M3)** : l'alerte régionale part plus tôt.
- Le modèle est entraîné et amélioré avec les photos validées par les agents ATDA et l'INRAB : c'est une donnée béninoise qui prend de la valeur.

**M13. Gestion de contenu (back-office)**
- Cultures, ravageurs, zones, fiches, audios par langue, marchés, prix, règles d'alerte.

### 1.4 La blockchain dans AgriSɛn
- **Paiements et 3 parts** : le smart contract reçoit le paiement de l'acheteur, le garde en séquestre, et à la confirmation de livraison verse automatiquement les trois parts. La règle de répartition est publique et ne peut pas être détournée.
- **Assurance indicielle** : les relevés météo de référence sont inscrits sur la chaîne ; quand le seuil est franchi, l'indemnisation part automatiquement. Aucun producteur ne peut être « oublié », aucun faux sinistre ne peut être ajouté.
- **Traçabilité des lots** : chaque sac ou carton porte un QR ; chaque étape (récolte, agrégation, transformation, export) est inscrite. L'acheteur étranger vérifie l'origine béninoise et le respect des normes.
- **Subventions et recettes** : chaque franc versé ou encaissé laisse une trace immuable, auditable par la Cour des comptes.
- **Historique du producteur** : ses ventes et remboursements forment un historique certifié qui lui ouvre le crédit.
- **Récépissés de warrantage** : chaque récépissé est un token unique ; il ne peut être gagé qu'une fois, et il est « brûlé » à la sortie du stock.
- **Chaîne du froid** : les relevés de température des chambres froides sont scellés, preuve de qualité pour l'acheteur.

### 1.5 Workflows clés
0. **Plan de l'année** : 5 questions → moteur de planification → calendrier + plan des planches → rappels hebdomadaires → confirmation des actions → recalcul si imprévu.
1. **Alerte ravageur** : signalement → agrégation → risque → validation expert → diffusion → retour producteur.
2. **Vente** : offre → acheteur → paiement en séquestre → livraison confirmée → ventilation 3 parts.
3. **Sinistre** : seuil météo franchi → liste des producteurs assurés de la zone → indemnisation Mobile Money.
4. **Warrantage** : dépôt au magasin → récépissé tokenisé → crédit Mobile Money → hausse des prix → vente → remboursement automatique → solde au producteur.
5. **Diagnostic** : photo → diagnostic hors ligne → conseil audio → signalement automatique dans la surveillance phytosanitaire.

### 1.6 Indicateurs de pilotage
Nombre de producteurs enregistrés · volumes sous warrantage et crédits accordés · écart entre prix de vente à la récolte et prix obtenu après stockage · pertes post-récolte évitées grâce au froid · diagnostics photo réalisés · surfaces cartographiées · délai entre signalement et alerte · taux de producteurs alertés à temps · rendement moyen par filière · écart prix bord-champ / prix marché · montant du fonds de prévoyance · recettes collectées.

### 1.7 Inspirations
France : Télépac (déclaration PAC), Bulletins de Santé du Végétal (alertes ravageurs). USA : Farmers.gov, USDA Crop Progress. Afrique : Esoko (Ghana), FAMEWS (FAO), ACRE Africa (Kenya), Hello Tractor (Nigeria), systèmes de récépissés d'entrepôt (Ghana, Éthiopie, warrantage au Niger et au Burkina Faso), ColdHubs (Nigeria), PlantVillage Nuru.

---

## 2. Kplɔn — Plateforme nationale de gestion de l'éducation

### 2.1 Mission
Suivre **chaque apprenant de la maternelle au premier emploi**, outiller les enseignants, informer les parents (même non alphabétisés) et donner au ministère un pilotage en temps réel, avec une accessibilité totale (handicap visuel et auditif).

**Engagements du programme couverts, et comment la plateforme y répond**

| Engagement du programme | Réponse de Kplɔn |
|---|---|
| Identifiant unique et livret scolaire digital pour chaque apprenant, pour suivre son parcours en continu et personnaliser l'accompagnement | Registre des apprenants lié au NPI, livret unique de la maternelle au supérieur |
| Système d'information suivant apprenants et enseignants : scolarisation effective, assiduité, besoins en formation | Module vie scolaire (appel, notes), tableaux de bord établissement, circonscription et ministère |
| Digitalisation des curricula, référentiels et contenus pédagogiques pour harmoniser les pratiques | Bibliothèque de contenus par niveau et compétence, disponible hors ligne |
| Formation continue des enseignants par MOOC, vidéos et quiz | Module de formation continue avec certification et recommandations personnalisées |
| Parcours passerelles pour ramener à l'école les enfants déscolarisés et non scolarisés | Alerte décrochage et orientation automatique vers les passerelles |
| Salles de classe numériques, télé-enseignement, campus numériques et Sèmè City Hubs | Contenus et cours à distance accessibles depuis ces espaces, même connexion |
| IA pour analyser les performances, détecter les difficultés d'apprentissage et adapter les contenus | Parcours adaptatif par compétence et signalement des élèves en difficulté à l'enseignant |
| Gratuité du secondaire pour les filles, bourses dans les filières prioritaires, alternance | Module orientation, bourses et premier emploi, suivi de la gratuité |

### 2.2 Acteurs

| Acteur | Ce qu'il fait dans Kplɔn |
|---|---|
| **Élève / étudiant** | Cours, exercices, progression, livret, orientation, bourses, stages |
| **Parent** | Présence, résultats, messages de l'école — par appel vocal dans sa langue ou via l'app |
| **Enseignant** | Appel, notes, cahier de textes, ressources, formation continue, alertes décrochage |
| **Chef d'établissement** | Gestion de l'école : classes, emplois du temps, effectifs, cantine, infrastructures |
| **Inspection / circonscription** | Suivi des écoles, visites, besoins en enseignants |
| **Ministères** (maternel-primaire, secondaire, technique, supérieur) | Pilotage national, carte scolaire, examens, affectations, statistiques |
| **Universités / centres de formation** | Inscriptions, parcours, diplômes vérifiables |
| **Entreprises, ONG, Sèmè City** | Stages, alternance, bourses, projets collaboratifs |

### 2.3 Modules fonctionnels

**M1. Registre des apprenants et livret scolaire unique**
- Identifiant unique (NPI) de la maternelle au supérieur.
- Livret numérique : établissements fréquentés, résultats, compétences, examens (CEP, BEPC, BAC), diplômes.
- Le livret suit l'élève en cas de changement d'école ou de département.

**M2. Vie scolaire**
- Appel en un geste par élève (fonctionne hors ligne).
- Notes, bulletins, cahier de textes, emplois du temps.
- Justification des absences par le parent (touche téléphone ou message vocal).

**M3. Alerte décrochage et passerelles**
- Règles lisibles : absences répétées + chute des résultats = alerte.
- Appel automatique au parent, notification à l'enseignant puis à la circonscription.
- Orientation vers les parcours passerelles prévus pour les enfants déscolarisés : l'enfant est inscrit dans un parcours de rattrapage, suivi par un référent, puis réintégré dans une classe correspondant à son niveau réel.

**M4. Apprentissage et contenus**
- Curricula numérisés, cours, exercices, quiz, par niveau et compétence.
- Contenus disponibles **hors ligne** (téléchargés à l'école, modèle Kolibri).
- Formats accessibles : audio, texte agrandi, vidéos sous-titrées et en langue des signes.
- Parcours adaptatif : l'exercice suivant dépend de ce que l'élève maîtrise (modèle Khan Academy).

**M5. Formation continue des enseignants**
- Micro-modules vidéo + quiz (MOOC), certification, suivi des heures.
- Recommandations de formation selon les résultats de ses classes.

**M6. Gestion des établissements**
- Effectifs, salles, équipements numériques, cantines scolaires (repas servis, stocks), eau/électricité.
- Remontée des besoins de réhabilitation.

**M7. Examens et diplômes**
- Inscriptions aux examens, résultats, relevés.
- Diplômes vérifiables par QR code (fin des faux diplômes pour les employeurs).
- Interopérable avec Educmaster, déjà utilisé au Bénin.

**M8. Orientation, bourses et premier emploi**
- Orientation post-BEPC / post-BAC vers filières prioritaires (santé, agriculture, technologie).
- Candidatures aux bourses, gratuité, alternance.
- Offres de stages et projets collaboratifs publiées par entreprises et structures.

**M9. Messagerie et interactions**
- Échanges enseignant–parent, école–ministère, étudiant–établissement.
- Messages vocaux et écrits, traduits en audio pour les parents.

**M10. Tableau de bord ministériel**
- Taux de scolarisation, présence, réussite, décrochage par commune.
- Ratio élèves/enseignant, besoins en recrutement, suivi de la gratuité des filles.

**M11. Livret d'apprentissage numérique — reconnaître l'apprentissage informel** ⭐ *module innovant prioritaire*

> **Le problème** : une grande partie des jeunes Béninois apprennent un métier chez un patron (couture, coiffure, mécanique, soudure, menuiserie, électricité) pendant des années, sans aucun document qui prouve ce qu'ils savent faire. À la « libération », ils ont un savoir-faire réel mais invisible pour une banque, un client, un employeur ou un programme d'aide.

**La solution**
- Chaque apprenti a un **livret d'apprentissage numérique** lié à son NPI, et chaque atelier est enregistré (en lien avec la Chambre des Métiers de l'Artisanat et la base nationale des artisans).
- Le **référentiel de compétences** de chaque métier est découpé en étapes simples et illustrées (ex. couture : prendre les mesures, couper un patron, monter une manche, finitions…).
- Quand l'apprenti maîtrise une compétence, le **patron la valide** depuis son téléphone (une photo ou une courte vidéo du travail réalisé, puis un clic ou une touche USSD).
- Des **évaluateurs agréés** passent périodiquement confirmer les étapes clés.
- Chaque compétence validée devient une **micro-certification vérifiable par QR** sur BéninChain.
- À la fin, le livret complet prépare directement le **Certificat de Qualification Professionnelle (CQP)**, dont le programme prévoit la réforme pour mieux l'aligner sur le marché.

**Ce que ça débloque**
- Pour l'apprenti : une preuve de compétence pour trouver du travail, accéder au crédit ARCH artisan, au dispositif AZOLI, aux ateliers d'excellence.
- Pour le patron : reconnaissance de son rôle de formateur, possibles incitations (bonus, accès prioritaire aux bases d'appui à l'artisanat).
- Pour l'État : pour la première fois, une vision réelle de la formation professionnelle informelle, métier par métier, commune par commune.

**Accessibilité** : patrons et apprentis peu alphabétisés → validation par photo, pictogrammes, audio, USSD.

**M12. Tuteur vocal sur téléphone basique**
- L'enfant (ou le parent pour lui) appelle un **numéro gratuit** et suit 10 minutes de calcul, de lecture ou de français en **quiz vocal** : il répond avec les touches du téléphone.
- Fonctionne sans smartphone, sans data, sans que le parent sache lire.
- Le niveau s'adapte aux réponses ; la progression remonte dans le livret scolaire (M1) et l'enseignant la voit.
- Utilisable le soir, le week-end, pendant les vacances, et pendant les fermetures d'école.
- Financement : numéro gratuit négocié avec les opérateurs dans le cadre des accords État–télécoms, ou sponsorisé.

**M13. « École dans une boîte » — le serveur local hors ligne**
- Un **mini-serveur solaire** (type Raspberry Pi) installé dans l'école diffuse un **wifi local** sans internet.
- Il héberge la version locale de Kplɔn : cours, quiz, vidéos sous-titrées et signées, livres, appel et notes.
- Les téléphones et tablettes de l'école s'y connectent comme à un site web normal.
- Quand un agent ou l'enseignant passe dans une zone connectée, la boîte **synchronise** : nouveaux contenus descendent, présences et notes remontent.
- Coût faible, entretien simple, fonctionne dans les zones sans couverture (modèle Kolibri).

**M14. Back-office**
- Programmes, matières, contenus, établissements, calendrier scolaire.

### 2.4 Accessibilité (obligatoire)
- Déficients visuels : lecteur d'écran, navigation clavier, lecture audio intégrée, contrastes élevés.
- Déficients auditifs : sous-titres, vidéos signées, alertes visuelles et vibration.
- Parents non alphabétisés : bulletin vocal en langue locale, pictogrammes.

### 2.5 La blockchain dans Kplɔn
- **Résultats d'examens** : dès la délibération, le jury signe et inscrit l'empreinte des résultats. Aucune note ne peut être modifiée après coup sans que ce soit visible.
- **Diplômes vérifiables** : chaque diplôme est une attestation avec QR ; un employeur au Bénin ou à l'étranger le vérifie en quelques secondes. Fin des faux diplômes.
- **Livret scolaire** : chaque fin d'année, l'empreinte du livret est inscrite ; l'élève qui change d'école ou de pays emporte un parcours certifié.
- **Bourses et transferts fléchés** : attribution et versement tracés ; la présence agrégée qui déclenche un versement est scellée.
- **Formation des enseignants** : certifications de formation continue vérifiables, utiles pour les carrières et les affectations.
- **Micro-certifications d'apprentissage** : chaque compétence validée par un patron puis confirmée par un évaluateur est scellée ; l'apprenti présente un QR que tout employeur vérifie.
- **Synchronisation des boîtes hors ligne** : les données remontées par chaque école sont signées par la boîte et ancrées dès la synchronisation.

### 2.6 Indicateurs
Taux de présence · apprentis avec livret actif et compétences validées · insertion des apprentis certifiés · minutes de tutorat vocal suivies · écoles équipées d'une boîte hors ligne · taux de décrochage détecté et rattrapé · temps entre alerte et contact parent · enseignants formés · élèves ayant un livret complet · insertion des diplômés à 12 mois.

### 2.7 Inspirations
France : INE, ENT/Pronote, Livret Scolaire Unique, Parcoursup, M@gistère. USA : Khan Academy, Section 508/IDEA (accessibilité), Kolibri (offline, conçu pour l'Afrique). Afrique : Eneza (Kenya, cours par SMS), programmes d'apprentissage dual en Afrique de l'Ouest, Open Badges et micro-certifications numériques.

---

## 3. Gbɛ — Plateforme nationale de suivi des patients

### 3.1 Mission
Donner à chaque Béninois un **carnet de santé digital**, faire travailler ensemble patients, soignants, pharmacies, agents communautaires et institutions, et fournir au ministère des données fiables pour piloter.

**Engagements du programme couverts, et comment la plateforme y répond**

| Engagement du programme | Réponse de Gbɛ |
|---|---|
| Carnet de santé digital (dossier patient électronique) pour chaque Béninois, adossé à un Système d'Information Hospitalier généralisé à toutes les structures | Dossier patient lié au NPI, accessible par app, carte QR ou résumé vocal, partagé entre établissements |
| Prise en charge systématique des urgences vitales pour toute la population, via un dispositif de paiement différé | Module urgences : accès aux informations vitales et ouverture automatique du dossier de paiement différé |
| Généralisation de la télémédecine et usage de l'IA pour mieux soigner | Téléconsultation, télé-expertise entre soignants, aide à la décision |
| Plus de 16 000 agents de santé communautaire pour rapprocher les soins des populations | Application terrain hors ligne pour le suivi à domicile |
| Généralisation de l'assurance maladie ARCH | Vérification des droits en temps réel, facturation et remboursement |
| Qualité, traçabilité et sécurité des médicaments sur tout le territoire | Ordonnance à usage unique, vérification d'authenticité, suivi des stocks des pharmacies |
| Transferts monétaires numériques fléchés vers la santé (soins prénataux, vaccinations) | Versement automatique déclenché par la confirmation d'une vaccination ou d'une consultation prénatale |
| Nouveau dispositif d'identification, de formation et d'accréditation des professionnels de santé | Registre public des soignants accrédités, vérifiable par tous |
| Urgences vitales prises en charge pour tous : une urgence obstétricale ou un accident grave exige souvent du sang dans l'heure | Module HEMORA : mobilisation instantanée de donneurs compatibles à proximité et suivi des stocks de sang |

### 3.2 Acteurs

| Acteur | Ce qu'il fait dans Gbɛ |
|---|---|
| **Patient** | Consulte son carnet, prend rendez-vous, reçoit rappels, contrôle qui accède à son dossier |
| **Agent de santé communautaire** | Suivi à domicile (grossesse, vaccins, malnutrition, fièvre), hors ligne |
| **Médecin, infirmier, sage-femme** | Consultation, prescription, orientation, téléconsultation |
| **Centre de santé / hôpital** | Admissions, lits, laboratoire, facturation, stock |
| **Pharmacie** | Vérifie et délivre les ordonnances, gère ses stocks, signale les ruptures |
| **Laboratoire / imagerie** | Publie les résultats directement dans le dossier |
| **Assurance (ARCH, mutuelles)** | Vérifie les droits, rembourse |
| **Donneur de sang** | S'inscrit, porte sa carte donneur certifiée, répond aux alertes, suit ses dons et ses récompenses (HEMORA) |
| **Banque de sang / service de transfusion** | Gère les stocks par groupe, lance les campagnes, valide les dons (HEMORA) |
| **Ministère, ARS, agences** | Indicateurs, épidémiologie, accréditations, régulation |

### 3.3 Modules fonctionnels

**M1. Dossier patient / carnet de santé digital**
- Identité (NPI), groupe sanguin, allergies, antécédents, vaccins, grossesses, traitements, résultats.
- Accès par app, par **carte QR imprimée** (pour ceux sans smartphone), ou **résumé vocal** par appel.
- Le patient voit qui a consulté son dossier et peut retirer un accès.

**M2. Consultation et parcours de soins**
- Recherche patient par NPI / QR, résumé en un écran, saisie rapide.
- Orientation vers un spécialiste ou hôpital avec transmission du dossier.

**M3. Prescription et pharmacie**
- Ordonnance numérique avec QR sécurisé.
- La pharmacie scanne, délivre, marque « délivrée » : une ordonnance ne sert qu'une fois.
- Vérification d'authenticité d'un médicament par code (modèle mPedigree, Ghana).
- Gestion des stocks et alerte de rupture remontée au ministère.

**M4. Santé communautaire (hors ligne)**
- Formulaires simples : consultations prénatales, vaccination, périmètre brachial (malnutrition), paludisme.
- Synchronisation au retour du réseau.
- Rappels automatiques aux familles.

**M5. Rendez-vous et rappels**
- Prise de rendez-vous (appli, USSD, relais).
- Rappels par SMS ou appel vocal en langue locale : vaccins, CPN, renouvellement de traitement.

**M6. Urgences**
- Accès « bris de glace » aux informations vitales, tracé.
- Dossier de prise en charge en paiement différé ouvert automatiquement et lié au NPI : le patient est soigné d'abord, la question du paiement (ARCH, mutuelle, échéancier) est traitée ensuite, sans bloquer les soins.

**M7. Télémédecine**
- Téléconsultation (appel vidéo ou audio simple), télé-expertise entre soignants (photo + avis).

**M8. Assurance et financement**
- Vérification des droits ARCH en temps réel.
- Facturation, prise en charge, remboursement.
- Transferts fléchés : quand une vaccination ou une consultation prénatale est confirmée dans le dossier, un versement Mobile Money part automatiquement vers le ménage bénéficiaire. L'aide récompense un soin réellement effectué.

**M9. Professionnels et établissements**
- Registre des soignants accrédités (vérifiable publiquement), établissements, services disponibles, carte des pharmacies de garde.

**M10. Surveillance épidémiologique et pilotage**
- Indicateurs anonymisés : couverture vaccinale, CPN, cas de paludisme, alertes épidémiques par commune.
- Export vers DHIS2 (déjà utilisé au Bénin).

**M11. HEMORA — Don de sang et urgences transfusionnelles** ⭐ *module intégré*

> Projet existant, développé pour le hackathon international Bitcoin Mastermind 2026 (dépôt `Handsomeboy990/BMM`, initialement « Bitcoin Blood »), pensé dès le départ comme une solution de production. Il devient le module sang de Gbɛ.

**Le problème**
En Afrique subsaharienne, les ruptures de stock de sang et la difficulté à mobiliser vite des donneurs lors d'une urgence causent des décès évitables : hémorragies de l'accouchement, accidents de la route, anémies graves de l'enfant liées au paludisme, drépanocytose. Aujourd'hui, la famille du patient part souvent elle-même chercher un donneur.

**Ce que fait HEMORA**

*Pour les hôpitaux et banques de sang*
- **Matching d'urgence** : score de pertinence sur 100 pour chaque donneur :
  - compatibilité stricte ABO et Rhésus (O− donneur universel, etc.),
  - proximité calculée par la formule de Haversine : `score = max(0, 100 − km × 5)`,
  - bonus d'assiduité : +10 points par don validé, plafonné à 40.
- **Déclaration d'urgence vitale** avec besoins chiffrés par groupe sanguin.
- **Campagnes géociblées** : choix d'un rayon en kilomètres et notification groupée des donneurs.
- **Scan et validation du don** : le soignant scanne la carte QR du donneur, vérifie son identité et son groupe, enregistre la présentation (prélèvement ou ajournement), ce qui déclenche le défraiement.
- **Compte d'approvisionnement** propre à chaque structure pour financer ses campagnes.

*Pour les donneurs*
- **Carte donneur numérique et physique** : badge QR, groupe sanguin certifié, statut de validation, disponible **hors ligne** (PWA).
- **Portefeuille de reconnaissance** : défraiements, avantages santé, badges ; retrait en Mobile Money (ou Lightning sur option).
- **Commande d'une carte physique** imprimable avec photo.

*Pour l'administration*
- **Validation manuelle** des hôpitaux, banques de sang et ONG, pour empêcher toute usurpation d'identité sanitaire.
- **Journal comptable** complet de chaque récompense versée.

**Les 3 piliers cryptographiques**
1. **Preuve de possession (BIP-322)** : le donneur signe l'empreinte de son profil avec sa clé, sans jamais la révéler. On sait que le portefeuille lui appartient.
2. **Horodatage infalsifiable (OpenTimestamps sur Bitcoin)** : l'empreinte SHA-256 du profil est ancrée dans Bitcoin. N'importe quel soignant peut vérifier, même hors ligne, que la carte n'a pas été modifiée depuis son émission. Transfuser le mauvais groupe peut tuer : cette vérification protège le receveur.
3. **Micro-versements instantanés** : Mobile Money par défaut ; Lightning via Breez Liquid SDK (nœud non-dépositaire, frais quasi nuls) pour les donneurs qui le choisissent. **Règle médicale codée en dur** : aucun versement si le donneur a déjà donné dans les 60 derniers jours, le temps que son sang se reconstitue.

**Base technique existante**
Next.js 16, React 19, Tailwind v4, shadcn/ui · API versionnée `/api/v1/` validée par Zod, protection IDOR · PostgreSQL (Supabase) avec Row Level Security, Drizzle ORM · javascript-opentimestamps, bip322-js, bitcoinjs-lib, Breez Liquid SDK · domaines découplés (auth, donors, emergencies, campaigns, matching, bitcoin, transfers, stock) · **502 tests unitaires et d'intégration** (Vitest, 51 suites), ESLint, Prettier, Husky. C'est la même stack que celle recommandée pour les 4 plateformes : l'intégration est naturelle.

**Intégration dans Gbɛ et dans le socle national**

| HEMORA aujourd'hui | HEMORA dans Gbɛ |
|---|---|
| Identifiant propre au donneur | Rattaché au **NPI** : le groupe sanguin vient du dossier patient validé par un laboratoire, pas d'une déclaration |
| Notifications par e-mail (EmailJS) | **SMS et appel vocal** en langues locales, en plus de l'e-mail : la plupart des donneurs potentiels n'ont pas l'e-mail comme réflexe |
| Ancrage OpenTimestamps propre au projet | OpenTimestamps devient l'**ancrage public de toute BéninChain** : HEMORA est la preuve de concept de l'architecture nationale |
| Stocks gérés par structure | Tableau de bord national des stocks par groupe et par département pour l'agence nationale de transfusion sanguine |
| Urgence déclarée par l'hôpital | Déclenchée aussi depuis le module Urgences (M6) de Gbɛ, avec paiement différé |

**Choix de conception pour un déploiement national conforme**

*1. Une récompense compatible avec le don bénévole*
L'OMS recommande le don volontaire et non rémunéré, car un paiement peut pousser à cacher des facteurs de risque. HEMORA passe donc d'une logique de « paiement du don » à une logique de **reconnaissance et de défraiement** :
- **Défraiement du transport** : montant forfaitaire fixe, versé **à chaque présentation au centre, que le donneur soit prélevé ou ajourné** après le questionnaire médical. Il n'y a donc aucun intérêt à mentir pour « être accepté ».
- **Avantages en services, pas en argent** : bilan de santé gratuit (groupe, hémoglobine, dépistages avec résultats confidentiels), crédits utilisables dans le réseau de soins, priorité de rendez-vous.
- **Reconnaissance** : badges de fidélité (5, 10, 25 dons), certificat vérifiable de « donneur engagé », mise en avant par la commune.
- **Auto-exclusion confidentielle** : dans le questionnaire pré-don, le donneur peut indiquer discrètement que son sang ne doit pas être utilisé, sans perdre son défraiement.
- Les **tests de dépistage** restent obligatoires avant toute utilisation de la poche ; la règle des 60 jours entre deux dons reste bloquante dans le code.
- Les montants et avantages sont fixés avec l'agence nationale de transfusion sanguine et paramétrables sans redéploiement.

*2. Un rail de paiement conforme au cadre UEMOA*
- **Par défaut : Mobile Money en FCFA** (MTN MoMo, Moov Money, Celtiis Cash). Les comptes d'approvisionnement des structures sont tenus en FCFA.
- **En option, sur choix explicite du donneur : Lightning**, avec montant fixé en FCFA et converti au moment du versement. Le moteur de récompense est indépendant du rail de paiement : on ajoute ou retire un canal sans toucher à la logique métier.
- **OpenTimestamps n'est pas concerné** : l'horodatage sur Bitcoin ne fait circuler aucune monnaie, c'est une preuve d'existence et d'intégrité.
- **BIP-322** reste utilisé pour les donneurs qui choisissent Lightning ; pour les autres, la preuve d'identité passe par le NPI + OTP SMS.

*3. Une empreinte impossible à deviner*
Il n'existe que 8 groupes sanguins : une empreinte sans secret se retrouve par simple essai. La règle devient :

```
profileHash = SHA-256( sel || données canonisées )
  sel            = 32 octets aléatoires, générés à l'inscription
  données        = JSON trié : { npi_pseudonymisé, groupe, rhesus, date_certification, labo_id }
  stockage du sel = base chiffrée (jamais sur la chaîne, jamais dans les logs)
```

```ts
import { createHash, randomBytes } from "node:crypto";

export function buildProfileHash(profile: Record<string, string>, salt = randomBytes(32)) {
  const canonical = JSON.stringify(Object.keys(profile).sort().reduce(
    (acc, k) => ({ ...acc, [k]: profile[k] }), {} as Record<string, string>));
  const hash = createHash("sha256").update(Buffer.concat([salt, Buffer.from(canonical)])).digest("hex");
  return { hash, salt: salt.toString("hex") }; // le sel va en base chiffrée
}
```

- **Vérification hors ligne** : le QR de la carte contient les données minimales, le sel et la **signature de l'institution** (Ed25519). L'app du soignant vérifie la signature sans réseau ; la preuve OpenTimestamps est contrôlée contre les en-têtes de blocs Bitcoin mis en cache dans l'app, ou dès le retour du réseau.
- **Effacement** : si le donneur quitte le programme, on détruit le sel ; l'empreinte ancrée sur Bitcoin devient inexploitable (effacement cryptographique, voir 0.1).
- **Test à ajouter** : vérifier que deux profils identiques produisent deux empreintes différentes, et qu'aucun sel n'apparaît dans les logs ni dans les réponses d'API.

**Indicateurs propres**
Délai entre l'alerte et le premier donneur compatible arrivé · urgences couvertes / déclarées · donneurs actifs et réguliers · ruptures de stock par groupe et par département · cartes falsifiées détectées.

**Inspirations**
France : application « Don de sang » de l'EFS (lieux de collecte, rappels, niveaux de stock). USA : Blood Donor App de la Croix-Rouge américaine. Afrique : LifeBank (Nigeria), qui livre du sang aux hôpitaux avec une chaîne de traçabilité.

**M12. Transport d'urgence obstétricale par zémidjans formés** ⭐ *module innovant prioritaire*

> **Le problème** : beaucoup de décès maternels sont liés au délai : la femme en travail compliqué n'arrive pas à temps au centre de santé. Les ambulances sont trop peu nombreuses et loin des villages ; le zémidjan, lui, est partout.

**La solution**
- Un réseau de **conducteurs volontaires** (zémidjans, tricycles, taxis-brousse) **recrutés, formés et équipés** : premiers gestes, position de la femme, trousse simple, gilet identifiable.
- Une femme enceinte suivie (M4, M5) est **pré-enregistrée** avec son centre de référence.
- En urgence, elle, un proche ou l'agent de santé communautaire **lance l'alerte** : un bip, une touche USSD ou un appel au numéro court.
- La plateforme **géolocalise et appelle** automatiquement le conducteur disponible le plus proche (même logique de matching par proximité que HEMORA).
- Le centre de santé est **prévenu à l'avance** : il prépare la salle, et si besoin déclenche une alerte sang dans HEMORA.
- La course est payée **à tarif fixe par le dispositif de paiement différé des urgences** : la famille ne paie rien sur le moment.
- Le conducteur est payé en Mobile Money dès l'arrivée confirmée par le centre (scan QR).

**Pour qui** : femmes enceintes, nouveau-nés, et extensible aux autres urgences (accident, enfant en détresse).
**Inspirations** : programmes de transport d'urgence communautaire en Afrique de l'Est, Flare (Kenya, dispatch d'ambulances), expériences de « moto-ambulances ».

**M13. « Où trouver mon médicament ? »**
- Le patient ou le soignant cherche un médicament (par nom, photo de la boîte ou appel vocal).
- La plateforme indique **les pharmacies proches qui l'ont en stock**, avec prix indicatif et pharmacie de garde.
- Les stocks sont alimentés automatiquement par les ventes et les ordonnances délivrées (M3) : pas de double saisie pour le pharmacien.
- Évite de faire le tour de 5 pharmacies à moto, et oriente loin des vendeurs de rue (faux médicaments).
- Pour le ministère : carte en temps réel des **ruptures de stock** par molécule et par commune.

**M14. Mutuelle communautaire en micro-cotisation**
- Pour les travailleurs du secteur informel aux revenus irréguliers : cotisation **quotidienne ou hebdomadaire** de quelques centaines de FCFA par Mobile Money, quand ils peuvent.
- Couverture de base complémentaire à ARCH : consultations, médicaments essentiels, accouchement, transport d'urgence.
- Cotisation possible en groupe : marché, association, coopérative, tontine.
- Le droit à la prise en charge est vérifié instantanément par le centre de santé via le NPI.
- Chaque cotisation et chaque remboursement sont tracés sur BéninChain : la gestion de la mutuelle devient transparente pour ses membres (principal problème des mutuelles classiques : la confiance).

**M15. Back-office**
- Médicaments, protocoles, vaccins, établissements, fiches de prévention audio.

### 3.4 La blockchain dans Gbɛ
- **Ordonnance à usage unique** : le smart contract passe l'ordonnance à l'état « délivrée » au premier scan ; toute seconde tentative, dans n'importe quelle pharmacie du pays, est refusée.
- **Certificats de vaccination** : attestations vérifiables, reconnues pour l'école, le voyage, les transferts fléchés.
- **Journal des accès et consentements** : chaque consultation du dossier et chaque consentement donné ou retiré est inscrit. Le patient voit un historique que personne ne peut effacer, même un administrateur.
- **Traçabilité du médicament** : chaque lot est suivi du fabricant ou de l'importateur jusqu'à la pharmacie ; un faux médicament n'a pas de trace valide.
- **Accréditations** : un soignant radié est immédiatement visible comme tel partout.
- **Carte donneur de sang (HEMORA)** : groupe sanguin certifié et horodaté sur Bitcoin via OpenTimestamps, vérifiable hors ligne avant une transfusion ; chaque don validé et chaque récompense versée sont tracés.
- **Transport d'urgence** : alerte, prise en charge par le conducteur et arrivée au centre sont horodatées ; le paiement du conducteur est déclenché par smart contract.
- **Mutuelle** : cotisations et remboursements tracés, auditables par les membres.
- **Aucune donnée médicale sur la chaîne** : diagnostics, résultats et antécédents restent dans le dossier chiffré.

### 3.5 Sécurité des données
Contrôle d'accès par rôle · consentement du patient · journal d'audit de chaque accès · chiffrement des données sensibles · statistiques uniquement agrégées pour l'administration · structuration en norme **HL7 FHIR** pour l'interopérabilité entre hôpitaux.

### 3.6 Indicateurs
Patients avec dossier actif · délai entre alerte obstétricale et arrivée au centre · conducteurs formés et actifs · adhérents mutualistes · recherches de médicaments satisfaites · délai de mobilisation d'un donneur de sang en urgence · couverture vaccinale · CPN complètes · délai de délivrance des résultats · ordonnances frauduleuses détectées · ruptures de stock · téléconsultations réalisées.

### 3.7 Inspirations
France : Mon espace santé / DMP, carte Vitale, ordonnance numérique, Doctolib. USA : Blue Button, Health Information Exchange, HL7 FHIR, HIPAA. Monde/Afrique : DHIS2, OpenMRS, CommCare, mPedigree.

---

## 4. Anyigba — Plateforme nationale de gestion et de sécurisation du foncier

### 4.1 Mission
Rendre l'information foncière **visible, vérifiable et infalsifiable** : qui détient quelle terre, avec quel droit, quels litiges, quelles transactions. Réduire les ventes multiples, accélérer les titres, sécuriser les successions.

**Engagements du programme couverts, et comment la plateforme y répond**

| Engagement du programme | Réponse d'Anyigba |
|---|---|
| Extension du cadastre numérique à toutes les villes et zones rurales, sur la base du système numérique unique d'identification des parcelles déjà déployé progressivement dans les 77 communes | Carte foncière nationale, enregistrement terrain par GPS, validation communautaire pour les zones rurales |
| Réduction d'au moins 50 % des délais des démarches les plus utilisées, dont les titres fonciers | Workflow numérique géomètre → notaire → ANDF, suivi en temps réel de chaque dossier |
| Hébergement public sécurisé des actes judiciaires, notariés et d'huissier, garantissant intégrité, traçabilité et conservation | Coffre-fort des actes avec empreinte numérique, preuve ancrée sur blockchain |
| Mécanisme d'identification des successibles pour sécuriser les successions et prévenir les fraudes | Module successions lié à l'état civil via le NPI |
| Cour spéciale des affaires foncières et modes alternatifs de règlement des litiges avec l'appui des chefs traditionnels | Module litiges : médiation, gel de parcelle, publication des décisions |
| Partage de la plus-value foncière avec les communes quand une zone est revalorisée (routes, marchés, équipements) | Observatoire des prix et calcul automatique de la part communale à chaque mutation |
| Programme d'accès au logement et aux terrains viabilisés | Identification des parcelles disponibles et sécurisation des attributions |
| Interconnexion des bases (état civil, fiscalité, foncier) | Lien NPI avec l'état civil et la fiscalité locale |

### 4.2 Acteurs

| Acteur | Ce qu'il fait dans Anyigba |
|---|---|
| **Citoyen / propriétaire** | Consulte ses parcelles et titres, vérifie un terrain avant achat, reçoit une alerte si quelqu'un tente de vendre sa parcelle |
| **Acheteur** | Vérifie le statut d'une parcelle (web, SMS, USSD) |
| **Géomètre** | Levés, bornage, dépôt des plans |
| **Notaire** | Actes de vente, successions, mutations |
| **ANDF** | Instruction, validation, délivrance des titres et certificats |
| **Mairie / commune** | Lotissements, permis de construire, fiscalité foncière, plus-value |
| **CSAF / médiation** | Litiges, gel de parcelles, décisions |
| **Chefs traditionnels** | Confirmation des droits coutumiers, médiation |
| **Banques / SFD** | Vérifient un titre, enregistrent une garantie (hypothèque) |

### 4.3 Modules fonctionnels

**M1. Carte foncière nationale**
- Parcelles cartographiées avec statut : 🟢 titre foncier · 🔵 certificat de propriété foncière · 🟡 droit coutumier déclaré · 🔴 en litige · ⚪ non renseignée.
- Couches : zones agricoles, zones constructibles, domaine public, forêts classées, bâtis.

**M2. Registre des droits**
- Pour chaque parcelle : détenteur(s), type de droit, quote-parts (indivision familiale), baux, servitudes, hypothèques.
- Historique complet des mutations (la « chaîne des titres »).

**M3. Vérification publique**
- Par numéro de parcelle, clic sur la carte, ou SMS/USSD.
- Réponse : parcelle existante, type de droit, litige oui/non, mutation en cours oui/non (identité du détenteur partiellement masquée).

**M4. Enregistrement et régularisation**
- Levé GPS terrain, photos, pièces justificatives.
- **Validation par les voisins** (appel vocal : « confirmez-vous la limite ? ») et par le chef de village pour les terres coutumières.
- Instruction par l'ANDF, délivrance du titre ou du certificat.

**M5. Mutations (ventes, donations)**
- Déclaration d'intention de vente → la parcelle est **verrouillée** : impossible de la vendre à quelqu'un d'autre.
- Le propriétaire actuel est alerté par SMS/appel.
- Acte notarié, validation ANDF, inscription du nouveau détenteur.

**M6. Successions**
- Décès enregistré (lien état civil via NPI) → identification des héritiers → accord ou médiation → partage.

**M7. Litiges**
- Ouverture d'un litige, gel de la parcelle, suivi médiation puis CSAF, publication de la décision.

**M8. Coffre-fort des actes**
- Titres, plans, actes notariés et d'huissier stockés avec leur empreinte numérique (hash) : toute modification est détectée.

**M9. Urbanisme et fiscalité**
- Bâtis identifiés, permis de construire, taxe foncière, calcul et reversement de la plus-value aux communes.

**M10. Observatoire des prix**
- Prix des transactions en données ouvertes (modèle DVF France), utile aux acheteurs, aux banques et aux communes.

**M11. Convention de vente assistée au village** ⭐ *module innovant prioritaire*

> **Le problème** : en zone rurale et périurbaine, la plupart des ventes de terrain se font encore par une simple « convention de vente » sur papier, parfois sans témoin fiable, sans plan, sans bornes. Ce sont ces papiers-là qui produisent la majorité des litiges : même terrain vendu deux fois, limites contestées, héritiers qui n'étaient pas d'accord.

**La solution**
- Un **agent foncier mobile** (agent communal formé, ou géomètre agréé) se déplace sur la parcelle au moment de la vente.
- Avec l'app Anyigba, il enregistre sur place :
  - le **tracé GPS** de la parcelle et les **photos des bornes** ;
  - l'identité du vendeur et de l'acheteur par **NPI** ;
  - les **témoignages vocaux** des témoins, des voisins et du chef de village (« je confirme que cette terre appartient à la famille X et que les limites sont celles-ci »), dans leur langue ;
  - le **consentement des membres de la famille** du vendeur quand la terre est familiale ;
  - le prix et les modalités de paiement.
- Avant validation, la plateforme vérifie qu'aucune parcelle déjà enregistrée ne chevauche ce tracé et qu'aucun verrou ou litige n'existe.
- Le dossier complet est **ancré sur BéninChain** et la parcelle passe au statut « convention assistée » sur la carte.
- Le paiement peut passer par un **séquestre Mobile Money** : l'argent n'est libéré au vendeur qu'après l'enregistrement.

**Ce que ce n'est pas** : ce n'est pas encore un titre foncier. C'est une **preuve solide, datée, infalsifiable**, qui protège tout de suite l'acheteur et qui prépare la régularisation (certificat, puis titre) avec l'ANDF.

**Modèle économique** : frais de service modestes partagés entre acheteur et vendeur, reversés en partie à la commune.

**M12. Cartographie par drone communal**
- Chaque commune (ou groupement de communes) dispose d'un **drone** et d'un opérateur formé.
- Survol des villages et des zones agricoles → **orthophoto** haute résolution.
- Les limites des parcelles sont tracées sur l'image, puis **validées par les voisins** (appel vocal) et le chef de village.
- Permet de cartographier des milliers de parcelles beaucoup plus vite et moins cher qu'un levé parcelle par parcelle (modèle de la régularisation foncière au Rwanda, adapté à l'échelle communale).
- Les images servent aussi à l'urbanisme, à l'identification des bâtis et à la couche agricole d'AgriSɛn.

**M13. Carnet de famille foncier**
- La famille déclare **de son vivant** comment les terres seront transmises : quelles parcelles, à quels héritiers, en quelles parts.
- Les héritiers concernés **consentent par NPI** (OTP ou enregistrement vocal), accompagnés si besoin par un notaire ou un médiateur traditionnel.
- Le carnet est scellé sur BéninChain ; il peut être modifié, mais chaque version reste visible.
- Au décès, le module **Successions (M6)** s'appuie directement sur le carnet : moins de conflits, partage plus rapide.
- Particulièrement utile pour les terres familiales en indivision, source majeure de litiges.

**M14. Tableau de bord et back-office**
- Délais de traitement, litiges par zone, recettes, parcelles régularisées ; gestion des types de droits, documents, zones.

### 4.4 La couche blockchain : sécurisation et tokenisation des parcelles

**Principe** : le foncier est le cas d'usage le plus avancé de BéninChain. Le registre officiel reste dans la base de données de l'ANDF. La blockchain garde la **preuve** de chaque état validé et rend l'historique impossible à réécrire en silence.

```
Registre officiel ANDF (données complètes, protégées)
        │   empreinte (hash) de chaque parcelle et de chaque acte validé
        ▼
Smart contract "Registre foncier"
  1 parcelle validée = 1 token (titre miroir)
  aucune donnée personnelle en clair sur la chaîne
        ▼
Vérification publique : n'importe qui compare l'empreinte
```

**Ce que fait le token**
- **Création** uniquement par l'ANDF après validation terrain.
- **Transfert interdit** entre particuliers : seule une mutation validée par notaire + ANDF le déplace. Pas de revente spéculative.
- **Verrou** pendant une vente ou un litige ; **gel** sur décision de la CSAF.
- **Succession** : transfert vers les héritiers, en quote-parts si indivision.
- Chaque événement (création, mutation, litige) est public et horodaté.

**Tokenisation : usages concrets**
1. **Indivision familiale** : parts d'héritage représentées clairement, fin des « ventes par un seul frère ».
2. **Garantie de crédit** : la parcelle est nantie auprès d'une banque/SFD de façon visible ; impossible de la revendre pendant le prêt (lien avec la plateforme de crédit en moins de 48 heures prévue par le programme : un titre tokenisé et vérifiable rend la garantie immédiatement contrôlable par le prêteur, ce qui accélère la décision).
3. **Baux agricoles programmables** : location d'une terre à un producteur, durée et loyer Mobile Money, fin automatique (lien AgriSɛn).
4. **Plus-value automatique** : à chaque mutation, le smart contract compare le prix de vente au dernier prix enregistré, calcule la plus-value liée aux aménagements publics de la zone et reverse automatiquement la part prévue à la commune, qui finance de nouveaux projets locaux.
5. **Convention de vente assistée** : dossier complet (tracé, bornes, témoignages vocaux, consentements) ancré sur la chaîne ; paiement en séquestre libéré par smart contract.
6. **Carnet de famille foncier** : versions successives scellées, consentements des héritiers horodatés.

**Choix technique**
- Le contrat « Registre foncier » est déployé sur **BéninChain** (voir 0.1) : nœuds ANDF, CSAF, Chambre des notaires, communes.
- Ancrage périodique sur **Bitcoin via OpenTimestamps** (la Géorgie ancre aussi ses titres sur Bitcoin) → preuve vérifiable par tous.
- Prototype : Solidity + OpenZeppelin (ERC-721 à transferts restreints + contrôle des rôles), sur testnet.

**Gestion des clés pour les citoyens**
- L'usager ne manipule jamais de clé. Portefeuille géré par l'institution, rattaché au NPI, récupérable en agence.
- Il interagit par USSD, appel vocal ou app : « Votre terrain est sécurisé ✅ ».

**Limites à assumer**
- La blockchain ne vérifie pas la vérité de la donnée d'entrée → validation géomètre + voisins + ANDF avant inscription.
- Le token n'a de valeur juridique que si la loi le reconnaît → au départ, c'est une **preuve miroir** du titre officiel.
- Vendre des fractions de terrain à des investisseurs relève de la réglementation financière UEMOA → hors périmètre sans cadre légal.

### 4.5 Indicateurs
Parcelles cartographiées et régularisées · conventions de vente assistées · villages cartographiés par drone · familles ayant un carnet foncier · délai moyen d'obtention d'un titre · tentatives de double vente bloquées · litiges ouverts/résolus · falsifications détectées · recettes foncières communales.

### 4.6 Inspirations
France : cadastre.gouv.fr, Géoportail, DVF, publicité foncière. USA : County Recorder, assurance titre, pilote blockchain de Cook County. Monde : Géorgie (NAPR + blockchain), Suède (Lantmäteriet), Rwanda (régularisation massive), STDM de la FAO (droits coutumiers). Leçons d'échecs : Honduras, Bitland (Ghana).

---

## 5. Ponts entre les plateformes

| Pont | Effet |
|---|---|
| **Parcelle agricole AgriSɛn = parcelle Anyigba** | Le producteur prouve son droit sur la terre → accès au crédit et à l'assurance |
| **Bail agricole tokenisé (Anyigba) → AgriSɛn** | Les producteurs sans terre louent en sécurité |
| **Vaccination confirmée (Gbɛ) → versement** | Transfert fléché santé automatique |
| **Présence scolaire (Kplɔn) → versement** | Transfert fléché éducation automatique |
| **Formation agricole (Kplɔn) → AgriSɛn** | Jeunes diplômés des lycées agricoles orientés vers les coopératives |
| **Décès (état civil) → Anyigba + Gbɛ** | Succession déclenchée, dossier médical clôturé |
| **Warrantage (AgriSɛn) → titre foncier (Anyigba)** | Récépissé de stock et droit sur la terre se combinent pour des crédits plus importants |
| **Livret d'apprentissage (Kplɔn) → crédit artisan** | Compétences certifiées ouvrent l'accès au crédit ARCH artisan et aux ateliers d'excellence |
| **Diagnostic photo (AgriSɛn) → surveillance** | Chaque photo géolocalisée alimente l'alerte régionale |
| **Transport d'urgence (Gbɛ) → HEMORA** | L'arrivée annoncée d'une urgence obstétricale déclenche si besoin une alerte sang |
| **Drone communal (Anyigba) → AgriSɛn** | Les orthophotos donnent les surfaces cultivées réelles |
| **Tous les ponts passent par BéninChain** | Un événement inscrit par une plateforme (vaccination, présence, titre) déclenche l'action de l'autre via un smart contract : pas de ressaisie, pas de manipulation possible entre les deux |

---

## 6. Architecture : 4 applications Next.js, 4 déploiements différents

### 6.1 Une seule technologie : Next.js pour tout le code applicatif
Les 4 plateformes, les applications terrain, les back-offices, les tableaux de bord et les interfaces de BéninChain sont **tous développés en Next.js**, avec la stack déjà éprouvée sur HEMORA.

| Couche | Choix commun aux 4 plateformes |
|---|---|
| Framework | **Next.js 16** (App Router), React 19, TypeScript strict |
| Interface | Tailwind CSS v4, shadcn/ui, **design system commun** (même logique d'icônes, de couleurs, de lecture audio sur les 4 plateformes) |
| État et données | Zustand, TanStack Query |
| API | **Route Handlers Next.js** versionnés `/api/v1/`, validation stricte par Zod, protection IDOR |
| Hébergement applicatif | **Vercel**, un projet par plateforme |
| Données | **PostgreSQL + PostGIS sur Neon** (une base par plateforme), Drizzle ORM et migrations versionnées, **données fictives** injectées par seed · Row Level Security pour la production |
| Conteneurisation | **Docker** + Docker Compose : environnement local complet et images portables vers l'infrastructure nationale |
| Hors ligne | **PWA Next.js** (service worker via Serwist, IndexedDB) : l'app terrain est une PWA installable sur Android, pas une app native séparée |
| Canaux USSD / SMS / IVR | Les agrégateurs opérateurs appellent des **Route Handlers Next.js** dédiés (`/api/v1/ussd`, `/api/v1/ivr`, `/api/v1/sms`) : un seul code métier pour le web, le téléphone basique et la voix |
| Blockchain | Les apps Next.js parlent à BéninChain via un **SDK TypeScript commun** (viem pour les smart contracts, javascript-opentimestamps pour l'ancrage) ; l'explorateur public et la console d'administration du consortium sont aussi en Next.js |
| Qualité | Vitest, Playwright, ESLint, Prettier, Husky, audits d'accessibilité automatiques |

Seuls deux éléments ne sont pas du Next.js, par nature : les **nœuds BéninChain** (Hyperledger Besu) et les **smart contracts** (Solidity). Tout ce que les humains utilisent est en Next.js.

### 6.2 Organisation du code : un monorepo, des applications indépendantes

```
benin-platforms/                (monorepo Turborepo)
├── apps/
│   ├── agrisen/                Next.js — Agriculture
│   ├── kplon/                  Next.js — Éducation
│   ├── gbe/                    Next.js — Santé (intègre HEMORA)
│   ├── anyigba/                Next.js — Foncier
│   └── beninchain-explorer/    Next.js — explorateur public et console du consortium
├── packages/
│   ├── ui/                     design system commun (accessibilité, audio, pictogrammes)
│   ├── auth-npi/               connexion NPI + OTP
│   ├── payments/               Mobile Money (+ Lightning en option)
│   ├── channels/               USSD, SMS, IVR, WhatsApp
│   ├── beninchain-sdk/         empreintes salées, ancrage, attestations vérifiables
│   ├── geo/                    référentiel géographique, PostGIS
│   └── i18n-audio/             langues nationales et bibliothèque audio
└── contracts/                  smart contracts Solidity (Foundry)
```

Le code partagé est écrit une seule fois ; chaque plateforme reste **une application autonome**, avec sa base de données, son équipe, son calendrier de mise en production et sa propre autorité de tutelle. Une panne ou une mise à jour de l'une n'affecte pas les autres.

### 6.3 Chaque plateforme est déployée différemment, selon ses usagers et ses données

| | **AgriSɛn** (Agriculture) | **Kplɔn** (Éducation) | **Gbɛ** (Santé) | **Anyigba** (Foncier) |
|---|---|---|---|---|
| **Profil d'usage** | Millions de producteurs ruraux, pics saisonniers, forte part de téléphones basiques | Très nombreux élèves et parents, pics aux rentrées et aux résultats d'examens, écoles sans réseau | Données les plus sensibles, disponibilité vitale 24h/24 | Données juridiques à forte valeur, trafic modéré, exigence de preuve maximale |
| **Déploiement Vercel** | Projet Vercel dédié ; pages de conseil, prix et fiches en génération statique ; menus USSD et appels vocaux simulés dans un faux téléphone à l'écran | Projet Vercel dédié ; contenus pédagogiques en génération statique ; la « boîte » d'école est présentée avec une **copie exportée** de la même app Next.js | Projet Vercel dédié, avec **protection d'accès** (mot de passe de démo) même si les patients sont fictifs ; HEMORA avec versements simulés mais enregistrés en base | Projet Vercel dédié ; portail public de vérification en génération statique ; carte des parcelles en PostGIS, données fictives |
| **Cible de production** | Cloud souverain national, mise à l'échelle automatique pendant les campagnes | Hybride : instance centrale + serveur local dans chaque école | Hébergement de santé isolé, deux sites, au Bénin | Infrastructure ANDF, avec un nœud BéninChain |
| **Hors ligne** | PWA des agents ATDA et des magasiniers ; diagnostic photo avec modèle embarqué | Boîte d'école autonome, synchro périodique | PWA des agents de santé communautaire, carte QR et vérification HEMORA sans réseau | PWA des agents fonciers mobiles et opérateurs drone, synchro au retour |
| **Canaux dominants** | USSD, appel vocal, SMS, PWA | PWA, appel vocal (parents, tuteur), wifi local | PWA soignants, QR, SMS/vocal patients | Portail web, SMS « VERIF », PWA terrain |
| **Données sur BéninChain** | Paiements, 3 parts, récépissés, assurance, traçabilité | Examens, diplômes, micro-certifications | Ordonnances, accès, consentements, vaccins, carte donneur | Parcelles, titres, mutations, conventions, successions |
| **Rythme de mise en production** | Calé sur les campagnes agricoles (jamais en pleine récolte) | Calé sur le calendrier scolaire (jamais en période d'examens) | Déploiements progressifs par hôpital, fenêtres de maintenance nocturnes, retour arrière immédiat | Déploiements rares, validés par l'ANDF, chaque version de smart contract auditée |
| **Autorité de tutelle** | Ministère de l'Agriculture | Ministères de l'Éducation | Ministère de la Santé, agence nationale de transfusion (HEMORA) | ANDF, Ministère du Cadre de vie, Justice (CSAF) |

**Conséquence importante** : les 4 plateformes peuvent **démarrer à des moments différents**. Le socle commun (packages partagés + BéninChain) permet de lancer la première, puis d'ajouter les autres sans tout refaire. HEMORA, déjà en Next.js et testé, est le point de départ naturel de Gbɛ.

### 6.4 Hébergement et souveraineté
**Phase présentation** : Vercel + Neon, données fictives uniquement, aucune donnée réelle. **Production** : les données des citoyens doivent rester hébergées au Bénin, conformément à la future loi sur la localisation des données. Les interfaces Next.js pourront rester sur Vercel si le cadre juridique le permet, avec les données et les API sensibles hébergées au Bénin ; sinon, les mêmes apps Next.js sont redéployées telles quelles sur l'infrastructure nationale (c'est l'intérêt d'avoir tout en Next.js). Les nœuds de BéninChain sont répartis dans plusieurs villes ; seule l'empreinte de Merkle quitte le territoire, via l'ancrage sur Bitcoin.

---

## 7. Déploiement par phases

| Phase | Contenu |
|---|---|
| **Phase 0 — Socle de confiance (3-6 mois)** | Mise en place du consortium BéninChain : premiers nœuds (ANDF, ministères pilotes), charte de gouvernance, smart contracts audités, cadre juridique de la preuve blockchain avec l'autorité de protection des données. |
| **Phase 1 — Pilote (6-12 mois)** | Démarrage par Gbɛ à partir de HEMORA, déjà en Next.js et testé, puis les 3 autres plateformes en décalé. Une commune rurale + une commune urbaine par plateforme. Enregistrement assisté par les relais. Premiers cas d'usage immuables : titres fonciers, diplômes, ordonnances, paiements agricoles. |
| **Phase 2 — Département / pôle** | Extension aux 6 pôles de développement territorial du programme. Ponts entre plateformes activés. |
| **Phase 3 — National** | 77 communes, ouverture des API aux acteurs privés (banques, assureurs, startups labellisées). |
| **Phase 4 — Export** | Solution « labellisée Bénin » proposée à d'autres pays (ambition du programme : faire du Bénin un exportateur de solutions technologiques, avec un label national qui atteste qu'une solution a fait ses preuves dans le contexte béninois). |

**Financement possible** : budget État et fonds national d'investissements stratégiques (alimenté par les revenus des ressources naturelles et les dividendes des sociétés publiques, pour financer les grands projets sans alourdir la dette), partenaires techniques et financiers, commissions sur transactions (marché agricole, frais de vérification foncière), abonnements des acteurs privés (pharmacies, banques, assureurs).
