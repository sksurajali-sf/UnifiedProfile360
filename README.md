# Unified Profile 360

A Salesforce-native replacement for the landing page behind the **View** button in Data Cloud
Profile Explorer. The standard search screen is untouched; the page it opens becomes a full
unified customer view — reconciled winner values with the evidence behind them, a cross-channel
engagement timeline, orders, calculated insights, segment membership, and ad-hoc access to any
related data model object without writing SQL.

| | |
| --- | --- |
| **Install (any org)** | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ9000000l3kP |
| **Implementation guide** | [`docs/Unified_Profile_360_Implementation_Guide.pdf`](docs/Unified_Profile_360_Implementation_Guide.pdf) |
| **API version** | 67.0 |
| **Requires** | Salesforce Data Cloud, at least one Identity Resolution ruleset that has run |

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
| ApexClass | 12 | 6 controllers + 6 test classes |
| AuraDefinitionBundle | 8 | `dcProfileLayout` plus one thin shell per panel |
| LightningComponentBundle | 12 | 8 panels, the shared page-context module, and the 3-part standalone explorer |
| CustomObject | 1 | `ProfileExplorerDmo__mdt` |
| CustomMetadata | 1 | `ProfileExplorerDmo.Unified_Individual` |
| FlexiPage | 1 | `Data_Cloud_Profile_Explorer` — CDP record page for `UnifiedIndividual__dlm` |

Aura shells exist because a Lightning web component cannot target a CDP record page. Each shell
implements `flexipage:availableForAllPageTypes` and passes `recordId` / `sObjectName` through to
its LWC. `dcProfileLayout` ("Unified Profile Page") is the whole layout in one drop; the seven
single-panel shells are there for pages that need their own arrangement.

## Deploy from source

```bash
sf org login web --alias TARGET_ORG
sf project deploy start --manifest manifest/package.xml --target-org TARGET_ORG --wait 30
sf apex run test --target-org TARGET_ORG \
  --tests UnifiedProfileControllerTest --tests UnifiedProfileRegistryTest \
  --tests UnifiedSegmentControllerTest --tests UnifiedInsightControllerTest \
  --tests UnifiedDmoExplorerControllerTest --tests ProfileExplorerControllerTest \
  --result-format human --wait 20
```

Then activate `Data Cloud Profile Explorer` as the org default CDP record page for Unified
Individual (Setup → Lightning App Builder → open the page → Activation). Section 9 of the
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
- Data Cloud objects are absent from `getGlobalDescribe` and `EntityDefinition`, so the object
  picker on the standalone search page reads `ProfileExplorerDmo__mdt`. Add one record per
  profile DMO per data space you want listed.
