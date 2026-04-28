# App Store Keyword Research — April 2026

**Ticket:** EPAC-310
**Date:** 2026-04-27
**Method:** Structured brainstorm using audience personas + competitor analysis framework

## Methodology

Without AppFollow/AppTweak access, keyword candidates were generated using:
- Audience persona search intent mapping (civic-minded Canadians, journalists, students)
- Removal of terms already in title/subtitle (parliament, pocket)
- Removal of non-user-search terms (siri, spotlight — system features, not queries)
- Competitor gap analysis (CBC, Globe and Mail target news; epac targets raw government data)
- French Canadian market parallel set

## English Keyword Candidates (ranked by expected relevance)

| Keyword | Rationale | Include? |
|---|---|---|
| hansard | Unique to parliament; high intent signal | ✓ |
| mp | Short, high volume; "member of parliament" search shorthand | ✓ |
| vote | Action word; bill tracking context | ✓ |
| bills | Legislative tracking | ✓ |
| senate | Second chamber coverage | ✓ |
| election | Electoral history, voting records | ✓ |
| mpp | Ontario MPP coverage | ✓ |
| riding | Riding lookup; unique Canadian term | ✓ |
| federal | Scopes to federal level specifically | ✓ |
| debate | Core feature description | ✓ |
| expenditure | MP expense tracking feature | ✓ |
| petition | E-petition tracking feature | ✓ |
| accountability | Positioning word; differentiates from news apps | ✓ |
| committee | Committee transcripts feature | considered — dropped for space |
| government | Broad term; low signal-to-noise | ✗ excluded |
| ontario | Geographic; covered by mpp/riding | ✗ excluded |
| siri | iOS system feature, not a user search term | ✗ removed |
| spotlight | Same — iOS system feature | ✗ removed |
| parliament | Already in subtitle — Apple combines with keywords | ✗ removed |
| canada | Weak alone; too broad; no meaningful ranking uplift | ✗ removed |

## Final English Keyword String

```
hansard,mp,vote,bills,senate,election,mpp,riding,federal,debate,expenditure,petition,accountability
```

Character count: 99/100

## French Canadian Keyword Candidates

| Keyword | Rationale |
|---|---|
| parlement | Direct translation |
| depute | MP equivalent (député without accent for App Store compatibility) |
| senat | Senate |
| chambre | House of Commons shorthand |
| vote | Same in French |
| projet-de-loi | Bill/law (compound; used in Canadian French political discourse) |
| politique | Politics |
| canada | Included in fr-CA string where it adds geographic signal |
| gouvernement | Government |
| hansard | Same term used in French Canada |
| depenses | Expenditures |

## Final French Keyword String (fr-CA)

```
parlement,depute,senat,chambre,vote,projet-de-loi,politique,canada,gouvernement,hansard,depenses
```

Character count: 96/100

## Next Refresh

Schedule: 2026-07-27 (quarterly, EPAC-210)
Trigger: after 4 weeks of impression data from App Store Connect showing impact of this change
