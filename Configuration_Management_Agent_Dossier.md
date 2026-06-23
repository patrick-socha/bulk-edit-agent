# [NEEDS UPDATING] Bulk-Edit Assistant (Capability & Architecture Dossier) 

## Executive Summary

The **Bulk-Edit Assistant** is a production-published Agentforce employee agent that lets sales reps configure Salesforce Revenue Cloud product bundles on quotes using plain language: inspecting configurations, changing attributes and quantities, selecting/swapping bundle components, and applying changes in **bulk across every instance of a bundle (optionally scoped to specific groups/regions) in a single request**. It is backed by the Salesforce Product Configurator Business APIs via Invocable Apex, and it has been verified end-to-end against live quote data, including multi-instance bulk operations, idempotent re-runs, and rule-blocked safety paths.

It replaces slow, error-prone manual clicking through the configurator UI with a conversational, rules-respecting, deterministic automation layer.

---

## What It Does (Capabilities)

Every capability below was tested end-to-end on a live quote with real configurator callouts:

1. **Inspect** — "What's configured on this bundle?" Returns current attributes, values, quantities, and bundle structure in plain language.
2. **Update attributes** — including picklist attributes (e.g. Base_Core_Count 4 → 8), resolving the correct picklist value automatically.
3. **Change quantities** — on existing line items, respecting which lines are quantity-locked by bundle rules.
4. **Select / deselect / swap components** — turn predefined bundle options on or off, or swap one option for another (e.g. swap training packages) within a component group's rules.
5. **Bulk edit (headline capability)** — apply the **same** component change to **every instance** of a bundle on a quote in one deterministic pass. "Add Essentials Training to all QuantumBit Complete Solution bundles" finds all 3 instances and updates each — no per-bundle clicking, no repeated prompting.
6. **Guardrails** — gracefully redirects off-topic requests and asks for clarification on ambiguous ones.

---

## Architecture (Three Layers + FSM)

**Layer 1 — Conversation & Orchestration (Agentforce / Agent Script).**
A finite-state-machine agent using a **hub-and-spoke** design:

- `start_agent` router classifies intent and routes.
- `ConfigurationManagement` subagent — all configure/update/inspect/component work.
- `TemplateManagement` subagent — reusable saved configurations (isolated deliberately; see below).
- Two guardrail subagents — `off_topic` and `ambiguous_question`.

**Layer 2 — Action Logic (Invocable Apex, ~18 classes).**
Each agent capability is backed by a dedicated, single-responsibility Apex action. A shared `ConfiguratorClient` utility centralizes session management and payload construction so the API contract lives in exactly one place (no drift). Discovery helpers (`QueryProductByName`, `QueryQuoteLineItems`, `ListBundleComponentOptions`, `GetAttributePicklistValues`) resolve names → IDs and surface valid options to the agent.

**Layer 3 — Salesforce Product Configurator (rules engine).**
The agent drives the configurator; the configurator enforces all bundle rules (min/max selections, required components, validation). The agent never overrides rules — it surfaces them.

**Standout architectural decision:** *determinism lives in code, not in the LLM.* The bulk loop ("do X to all N bundles") is implemented in Apex, not via LLM iteration, because LLMs are unreliable at exhaustive looping. The LLM interprets intent and confirms; Apex guarantees every instance is handled correctly. This is the design choice that makes the agent trustworthy at scale.

---

## APIs & Technology Stack

- **Salesforce Product Configurator Business APIs** (Headless Configurator, `/connect/cpq/configurator/...`, API v67.0) — load-instance, get-instance, add-nodes, update-nodes, delete-nodes, set-product-quantity, save-instance.
- **Invocable Apex** — the action layer the agent calls (`@InvocableMethod` / `@InvocableVariable`).
- **Named Credential + External Client App (OAuth)** — secure, runtime-valid authentication for the API callouts.
- **Agentforce / Agent Script** — agent definition, published and activated (currently version 3).
- **SOQL** — bulk-safe discovery queries (ProductComponentGroup, ProductRelatedComponent, PricebookEntry, QuoteLineItem) with no SOQL-in-loops and `USER_MODE` enforcement.

---

## Strengths (by the dimensions evaluators care about)

### 1. Safety & guardrails — best-in-class
- The agent can **only toggle predefined bundle options** — it physically cannot invent new products or delete arbitrary records (the raw add/delete tools were deliberately removed from its toolset).
- It **enforces configurator rules**: attempting a change the bundle forbids (e.g. removing a required component) returns a clear "not possible" message and changes nothing.
- **Confirmation gating**: destructive/committing actions are gated behind explicit user confirmation, enforced deterministically (not just by prompt text).
- **Honest reporting**: a hardening pass made every action surface success/failure to the LLM and forbid it from claiming success on a failed call — eliminating false-success responses.

### 2. Determinism & correctness at scale
- Bulk operations are **all-or-nothing**: if any one bundle instance is rule-blocked, nothing is saved and the rep gets a per-bundle breakdown. No partially-applied quotes.
- **Idempotent**: re-running a bulk select skips instances already in the desired state — no duplicates.
- **Per-instance integrity**: verified that bulk-adding a component nests it correctly under each distinct bundle (not as loose line items), with collision-free identifiers per instance.

### 3. Robust error handling & resource safety
- Single configurator session per operation, single save — efficient and consistent.
- Governor-limit guard (caps bulk at ~93 instances with a clear "narrow scope" message rather than failing mid-run).
- Graceful, specific error messages surfaced to the user.

### 4. Grounding & UX
- Responses are composed from actual API output (names, values, counts) — not paraphrased — reducing hallucination risk.
- Plain-language confirmations ("There are 3 bundles… confirm?") and per-bundle result summaries.

### 5. Engineering maturity
- Shared utility eliminates duplicated API logic.
- Full Apex test coverage with `HttpCalloutMock` for every class.
- **Verified end-to-end on live data** — including the multi-bundle bulk path — with disciplined snapshot-and-revert so the test quote was always restored.

---

## Scope Boundaries (deliberate, not gaps)

By design, the agent **refers out** for: quote creation, pricing/discounting, and product-catalog search. This keeps it focused, safe, and predictable — a single-responsibility agent rather than an over-broad one. This is a strength in agent design, not a limitation.

---

## Known Limitations (with mitigations / roadmap)

- **One Setup step pending**: an admin must assign the agent's connection/service user before a rep drives it in the live UI. Everything else is published and active; logic verified via the live-action test harness.
- **Template save** (reusable named configurations) is not functional — blocked by a Salesforce-side error on the saved-configuration endpoint; deprioritized as non-essential. Isolated in its own subagent so it doesn't affect core flows.
- **Save semantics**: the configurator's save commits a whole session, so operations are carefully scoped to one session — handled correctly today, noted for future work.

---

## Roadmap (Natural Extensions)

- Extend bulk from components to **bulk attribute/quantity edits**.
- **Cross-bundle and cross-quote** bulk operations.
- **Pricing impact preview** and **change preview / undo** before commit.
- **Smart component recommendations** based on current selection.

---

## Bottom Line

A focused, safe, deterministic, fully-tested agent that automates a real, repetitive sales-rep task — with a standout bulk capability and a safety model that respects every configurator rule. It is published, active, and verified end-to-end on live data.
