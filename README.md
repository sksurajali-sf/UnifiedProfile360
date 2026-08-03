# Unified Profile 360

A Salesforce-native replacement for the landing page behind the **View** button in Data Cloud
Profile Explorer. The standard search screen is untouched; the page it opens becomes a full
unified customer view — reconciled winner values with the evidence behind them, a cross-channel
engagement timeline, orders, calculated insights, segment membership, and ad-hoc access to any
related data model object without writing SQL.

| | |
| --- | --- |
| **Install (any org)** | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000l3ke |
| **Installation password** | `GDC@India` |
| **Implementation guide** | [`docs/Unified_Profile_360_Implementation_Guide.pdf`](docs/Unified_Profile_360_Implementation_Guide.pdf) |
| **API version** | 67.0 |
| **Requires** | Salesforce Data Cloud, at least one Identity Resolution ruleset that has run |

For a sandbox, replace `login` with `test` in the install URL.

## What the page shows

| Panel | What it answers |
| --- | --- |
| Profile header | The reconciled winner name, unified id, email, phone and address, plus when Identity Resolution last ran |
| Identity breakdown | Every contributing individual, email, phone and address, with the winning row marked and the reason it won |
| Engagement timeline | Email and web engagement across every source individual, newest first, filterable by event type |
| Sales order timeline | Orders with status filter and totals per currency |
| Calculated insights | Any calculated insight in the org keyed by this profile, with its measures and dimensions |
| Segments | Published segments the profile belongs to, with publish status, schedule and member counts |
| Explore related data | Any DMO related to the individual — pick fields, pick the match column, page through the latest 100 rows |

## How a page finds its profile

A CDP record page hands over a DMO row id, not the unified id, and the DMO family behind a
profile depends on which Identity Resolution ruleset built it. `UnifiedProfileRegistry` derives
that family from the Unified Individual DMO name on the page, so a ruleset suffix (`Mc`, `Poc1`,
…) resolves to its own link and contact-point DMOs with no code change:

```
UnifiedIndividual__dlm        -> IndividualIdentityLink__dlm, UnifiedContactPointEmail__dlm, …
UnifiedssotIndividualMc__dlm  -> UnifiedLinkssotIndividualMc__dlm, UnifiedssotContactPointEmailMc__dlm, …
```

Engagement, orders and related objects are then read for **every** source individual behind the
profile — and, for email engagement, for every email address on the profile as well, so events
loaded from a file that carries only an address are not lost.

## Contents

| Type | Count | Members |
| --- | --- | --- |
| ApexClass | 10 | 5 controllers + 5 test classes |
| AuraDefinitionBundle | 1 | `dcProfileLayout` |
| LightningComponentBundle | 9 | 8 panels + the shared page-context module |
| FlexiPage | 1 | `Unified_Profile_360` — CDP record page for `UnifiedIndividual__dlm` |

21 members, 4 metadata types. No custom object, no stored data, no scheduled job, nothing written
back to Data Cloud.

The Aura shell exists because a Lightning web component cannot target a CDP record page.
`dcProfileLayout` implements `flexipage:availableForAllPageTypes`, passes `recordId` /
`sObjectName` through to `unifiedProfileView`, and appears in App Builder as **Unified Profile
Page** — the single component you drop, which renders all seven panels in their intended
positions.

## Deploy from source

```bash
sf org login web --alias TARGET_ORG
sf project deploy start --manifest manifest/package.xml --target-org TARGET_ORG --wait 30
sf apex run test --target-org TARGET_ORG \
  --tests UnifiedProfileControllerTest --tests UnifiedProfileRegistryTest \
  --tests UnifiedSegmentControllerTest --tests UnifiedInsightControllerTest \
  --tests UnifiedDmoExplorerControllerTest \
  --result-format human --wait 20
```

116 tests, every class above 75% coverage. Then activate `Unified Profile 360` as the org default
CDP record page for Unified Individual (Setup → Lightning App Builder → open the page →
Activation). Section 9 of the
implementation guide covers this, including how to build the same page for a ruleset other than
the standard Unified Individual.

## Data Cloud objects read

All read-only, all resolved at runtime: the Unified Individual DMO and its identity link and
unified contact point DMOs, `ssot__Individual__dlm` and the source contact point DMOs,
`ssot__EmailEngagement__dlm`, `ssot__WebsiteEngagement__dlm`, `ssot__BulkEmailMessage__dlm`,
`ssot__SalesOrder__dlm`, the ruleset's segment membership tables, every `__cio` calculated
insight, and whichever DMO the user picks in Explore Related Data. Nothing is written back.

## Notes and limits

- Calculated insights and the sales order timeline go through `ConnectApi.CdpQuery`, which is a
  callout: those methods cannot be `cacheable`, so their panels load once per page view.
- The reconciliation rule itself is not exposed by any API. The winner tooltip therefore reports
  observable evidence — which row the ruleset attributed the profile to, how many sources agree,
  and when the winning row was linked.
- Data Cloud objects are absent from `getGlobalDescribe` and `EntityDefinition`, so Explore
  Related Data builds its object list from the Data Cloud metadata service at runtime rather than
  from Apex schema describe.
- Only the page for the standard Unified Individual is packaged. Rulesets such as Unified
  Individual MC carry org-specific DMO names, so their pages are built in App Builder — five
  clicks, same components, covered in Section 9.2 of the guide.
