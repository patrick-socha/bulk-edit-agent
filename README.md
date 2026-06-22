# Bulk-Edit Assistant

An **Agentforce employee agent** that lets sales reps configure Salesforce Revenue
Cloud product bundles on quotes using plain language: inspect a configuration,
change attributes and quantities, select or swap bundle components, and apply a
change in **bulk across every instance of a bundle**, optionally **limited to
specific groups or regions** on the quote. It is backed by the **Salesforce Product
Configurator Business APIs** called through Invocable Apex.

It replaces slow, manual clicking through the configurator UI with a conversational,
rules-respecting, deterministic automation layer.

---

## What it can do

| Capability | Description |
|---|---|
| **Inspect** | "What's configured on this bundle?" Returns current attributes, values, quantities, and bundle structure. |
| **Update attributes** | Change attribute values, including picklist attributes (resolves the correct picklist value automatically). |
| **Change quantities** | Update line-item quantities, respecting which lines are quantity-locked by bundle rules. |
| **Select / deselect / swap components** | Turn predefined bundle options on or off, or swap one option for another, within a component group's rules. |
| **Bulk edit (components)** | Apply the **same** component change to **every instance** of a bundle on a quote in one deterministic pass. |
| **Bulk edit (attributes)** | Set the **same** attribute value on **every instance** of a bundle in one pass (picklist values validated up front). |
| **Scoped bulk edit (by group/region)** | Limit a bulk change to **named groups or regions** (and their subgroups), e.g. "California and New York" while leaving Texas untouched. |
| **Guardrails** | Redirects off-topic requests; asks for clarification on ambiguous ones. |

**By design, the agent can only toggle _predefined_ bundle options.** It cannot
invent new products or delete arbitrary records, and it always enforces the
configurator's bundle rules (min/max selections, required components).

---

## Architecture

Three layers plus a finite-state-machine conversation model.

```
Layer 1  Agentforce / Agent Script  (conversation + routing)
   start_agent (router)
      - ConfigurationManagement   (inspect / update / select / bulk)
      - off_topic                 (guardrail)
      - ambiguous_question        (guardrail)
        |
        |  apex:// actions
        v
Layer 2  Invocable Apex  (the action layer)
   ConfiguratorClient    (shared util: session + node payloads)
   QuoteLineGroupScope   (shared util: region/group resolution)
   + configurator wrappers, discovery helpers, constrained selection
        |
        |  REST callout (Named Credential / OAuth)
        v
Layer 3  Salesforce Product Configurator Business APIs
   (the rules engine; enforces all bundle rules)
```

**Key design principle: determinism lives in Apex, not the LLM.** Repetitive,
must-be-correct logic (for example "apply this to all N bundle instances in these
regions") is implemented in Apex, because LLMs are unreliable at exhaustive looping.
The LLM interprets intent and confirms; Apex guarantees every instance is handled.

### Apex classes

**Shared utilities**
- `ConfiguratorClient`: session lifecycle (`load-instance` / `save-instance`),
  generic callout, blocking-rule-message detection, pricebook resolution, and the
  node payload builders. The API contract lives here once so single and bulk paths
  cannot drift.
- `QuoteLineGroupScope`: resolves casual region/group names (for example
  "California, New York") to the exact set of `QuoteLineGroup` IDs a bulk operation
  should target, including all descendant subgroups. Tolerant name matching with a
  cycle-safe subgroup walk.

**Configurator API wrappers**: `LoadConfiguratorSession`, `GetConfiguratorInstance`,
`SaveConfiguratorInstance`, `ExecuteConfiguration`, `ExecuteConfigurationRules`,
`AddConfiguratorNodes`, `UpdateConfiguratorNodes`, `DeleteConfiguratorNodes`,
`SetProductQuantity`.

**Discovery helpers (SOQL to IDs)**: `QueryProductByName` (product name to Product2 Id),
`QueryQuoteLineItems` (find all line items / bundle instances for a product on a quote),
`ListBundleComponentOptions` (a bundle's component groups and selectable options),
`GetAttributePicklistValues` (valid picklist values for an attribute),
`ListQuoteLineGroups` (the quote's group/region hierarchy with per-group bundle counts,
used to ground region names and confirm scope before a scoped bulk change).

**Constrained selection (what the agent uses to change components)**
- `SelectBundleComponent`: select or deselect a predefined option on **one** bundle.
- `BulkSelectBundleComponent`: apply one component change to **every instance** of a
  bundle in a single session, optionally limited to named groups/regions,
  **all-or-nothing**, with a per-instance result report.

**Bulk attribute updates**
- `BulkUpdateBundleAttribute`: set the same attribute value (for example Operating
  System, Base Core Count) on **every instance** of a bundle, optionally limited to
  named groups/regions, **all-or-nothing**. Handles picklist attributes (validates
  the requested value against allowed values up front and rejects invalid input) and
  free-text/numeric attributes.

---

## How group/region scoping works

Quotes are organized with the **`QuoteLineGroup`** object: each group has a `Name`,
a `QuoteId`, and a self-referential `ParentQuoteLineGroupId` that nests **subgroups**
(for example region "GEO #2 - CALIFORNIA" with subgroups "LOS ANGELES" and
"SAN FRANCISCO"). Each `QuoteLineItem` links to its group via `QuoteLineGroupId`.

When a rep names regions ("California and New York"), `ListQuoteLineGroups` grounds
those words to the real group names, and `QuoteLineGroupScope` expands each matched
group to include all of its subgroups (a region often holds no bundles directly:
they live in its subgroups). The bulk action then changes only the instances in
those groups.

This is safe because grouping is purely a Salesforce-data concept: the configurator
session always loads the **whole quote** and the save is a whole-quote replace.
Scoping only narrows **which instances are mutated**, so out-of-scope groups stay
loaded, untouched, and are preserved on save.

---

## Repository layout

```
force-app/main/default/
  aiAuthoringBundles/Configuration_Management_Agent/   # the agent (Agent Script)
  classes/                                             # Apex classes + tests
  permissionsets/Configurator_API_Access...            # the access bundle
Product Configurator API Documentation/                # API reference
Configuration_Management_Agent_Dossier.md              # architecture dossier
```

---

## Prerequisites

- A Salesforce org with **Revenue Cloud / Product Configurator** licensed, and the
  **Headless Configurator** org feature **enabled** (see note in Setup, Auth below).
- Salesforce CLI (`sf`).
- The running user holding the relevant **Product Configuration / Revenue Cloud**
  permission set licenses.

---

## Setup and Permissions (required for the agent to work)

The agent calls the org's own REST API from Apex. That requires an **OAuth token**,
which requires a registered client app. The chain below is what makes the callouts
authenticate successfully **from the agent runtime**.

> Why not just use the session ID? An earlier version authenticated with
> `UserInfo.getSessionId()`. It works in synchronous/anonymous Apex but returns
> **HTTP 401** when the Apex runs inside the Agentforce agent runtime (the runtime
> session is not valid for REST callouts). The Named Credential below is the fix.

### 1. Enable the Headless Configurator feature
The Product Configurator Business APIs are gated by an **org-level feature**, separate
from the user licenses. If a call returns
`403 FUNCTIONALITY_NOT_ENABLED: [IHeadlessConfiguratorFamily]`, the feature is off.
Enable Headless Configuration in Setup (or via Salesforce support) even if the
Product Configuration licenses are already assigned.

### 2. Create a Connected App / External Client App (the OAuth client)
Holds the consumer key/secret and scopes that let the org mint a token.
- Enable OAuth; scopes: **`api`**, **`refresh_token offline_access`**.
- Callback URL: temporary at first; replaced in step 3.
- After saving, copy the **Consumer Key** and **Consumer Secret**.

### 3. Create an Auth. Provider (`Configurator_Auth_Provider`)
- Type: **Salesforce**; paste the Consumer Key/Secret from step 2.
- Authorize/Token endpoints: the org's My Domain
  (`https://<mydomain>.my.salesforce.com/services/oauth2/authorize` and `/token`).
- Scopes: `api refresh_token offline_access`.
- After saving, copy the generated **Callback URL** and paste it back into the
  Connected App's callback URL (step 2). A mismatch here causes `redirect_uri_mismatch`.

### 4. Create an External Credential (`Configurator_API_Cred`)
- Authentication Protocol: **OAuth 2.0**, Flow Type: **Browser Flow**.
- **Identity Provider**: the lookup to the Auth. Provider from step 3.
  This field is a lookup to an Auth. Provider record; it is empty until step 3 exists.
- Add a **Named Principal** named **`Configurator_Principal`**, scopes
  `api refresh_token offline_access`.

### 5. Create a Named Credential (`Configurator_API`)
- URL: the org's My Domain (`https://<mydomain>.my.salesforce.com`).
- External Credential: `Configurator_API_Cred`.
- **Generate Authorization Header: ON** (this injects `Authorization: Bearer ...`
  so the Apex sets no auth header itself).
- The Apex calls `callout:Configurator_API/services/data/v67.0/...`, so the
  Named Credential **name must be exactly `Configurator_API`**.

### 6. Authenticate the principal
External Credential, Principals, `Configurator_Principal`, **Authenticate**.
Approve the browser popup. Status must show authenticated/configured, otherwise
callouts fail even with the permission set assigned.

### 7. Deploy and assign the permission set (`Configurator_API_Access`)
This single permission set grants **both** required accesses:
- **External Credential Principal Access** to `Configurator_API_Cred-Configurator_Principal`
  (lets the running user use the credential), **and**
- **Apex class access** to every class the agent uses.

```bash
sf project deploy start --metadata PermissionSet:Configurator_API_Access
sf org assign permset --name Configurator_API_Access
```

> The Agentforce planner validates **every** action across **all** subagents at
> startup. If the running user lacks access to even one class, the whole agent
> fails. The permission set covers all of them, so assign it to every user
> (and the agent's running user).

The running user also needs **read access to the `QuoteLineGroup` object and the
`QuoteLineItem.QuoteLineGroupId` field**, or group scoping resolves to "group not
found" for everyone.

### 8. Assign the agent's connection/bot user
For an **employee agent**, the published agent needs a running user assigned in
**Setup, Agentforce Agents, Bulk-Edit Assistant**. Until this is set,
the live in-UI experience cannot execute actions (the CLI `--use-live-actions`
preview works without it). (The agent's developer/API name remains
`Configuration_Management_Agent`, which is what the CLI commands below use.)

---

## Deploy the agent

```bash
# Apex + permission set
sf project deploy start --source-dir force-app/main/default/classes
sf project deploy start --metadata PermissionSet:Configurator_API_Access

# Agent bundle
sf project deploy start --metadata AiAuthoringBundle:Configuration_Management_Agent
sf agent validate authoring-bundle --api-name Configuration_Management_Agent
sf agent publish  authoring-bundle --api-name Configuration_Management_Agent
sf agent activate --api-name Configuration_Management_Agent
```

Preview against live Apex without publishing:

```bash
sf agent preview start --use-live-actions --authoring-bundle Configuration_Management_Agent
```

---

## Usage examples (what a rep types)

- "Show me the current configuration of quote `<quoteId>`."
- "Change Base Core Count on the QuantumBit Complete Solution bundle to 8 on quote `<quoteId>`."
- "Add the Essentials Training option to the QuantumBit Complete Solution bundle on quote `<quoteId>`."
- **Bulk component:** "Add the Essentials Training option to **all** of the QuantumBit Complete Solution bundles."
- **Bulk attribute:** "Swap the Operating System to Redhat Enterprise Linux on **all** instances of the QuantumBit Complete Solution bundle."
- **Scoped by region:** "Add the Fundamentals Training package to the QuantumBit bundles in **California and New York**." (Texas is left untouched.)
- **Scoped attribute:** "Set the Operating System to Redhat on the QuantumBit bundles in **California only**."
- **Exclusion phrasing:** "Add Essentials Training to every QuantumBit bundle **except the Texas ones**."

The agent resolves "this quote" from the record page when launched there; otherwise
pass the Quote **Id** (it does not look up by quote number). For scoped requests it
grounds casual region names to the real groups, confirms which regions will and will
not be affected, then applies the change once.

---

## Safety model

- **Predefined options only**: cannot create new products or delete arbitrary records.
- **Rule-enforcing**: a change the bundle forbids (for example removing a required
  component) is reported as not possible and nothing is saved.
- **Confirmation-gated**: commits require explicit user confirmation, enforced
  deterministically.
- **All-or-nothing bulk**: if any instance is rule-blocked, nothing is saved and the
  rep gets a per-instance breakdown.
- **Scoping is non-destructive**: limiting a bulk change to named regions never drops
  the out-of-scope groups; they are loaded with the quote and preserved on save. An
  unknown region name fails fast (before any callout) and lists the available groups;
  any unmatched region in the request fails the whole request rather than silently
  changing a subset.
- **Honest reporting**: actions surface success/failure; the agent does not claim
  success on a failed call, and reports exactly which regions were affected.

> `save-instance` is a whole-quote replace. The configurator's save commits the
> entire session and prunes anything not in scope. All operations are therefore scoped
> to a single session. Always snapshot a quote's line items before bulk write tests.

---

## Known limitations

- **Connection/bot user assignment (step 8)** is required before live in-UI use.
- **Bulk is capped at ~93 bundle instances** per request (governor-limit safety guard).
  When a region is named, the cap applies to the scoped count, not the whole quote.
- **Out of scope by design:** quote creation, pricing/discounting, product-catalog search.

---

## Roadmap

- Bulk **quantity** edits (today bulk covers components and attributes).
- **Cross-quote** bulk operations (group/region scoping covers within-quote today).
- **Pricing-impact preview** and **change preview / undo** before commit.
- **Smart component recommendations** based on current selection.
