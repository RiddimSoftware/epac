# OCL subject-matter mapping completeness

_As of 2026-06-03. Source: https://lobbycanada.gc.ca/app/secure/ocl/lrs/do/cmmLgSms._

Lists every OCL subject-matter code seen in monthly communication reports
over the most recent reporting periods published by the Office of the
Commissioner of Lobbying (the current month plus the six prior periods —
≈ 6–7 months of activity, as much as the OCL public dashboard surfaces
without ingesting the full open-data CSV). Each row is flagged
`mapped` or `unmapped` against the EPAC monitored-topic mapping.
EPAC-2150 already shipped `backend/lobbying/ocl_topic_map.json`, but it
keys mappings by synthetic `SMT-N` strings rather than the integer OCL
codes the live registry uses; until that key format is reconciled the
report carries an empty mapping and every code surfaces as `unmapped`,
doubling as a backlog of codes that still need an EPAC topic
assignment.

- Total active OCL codes: **53**
- Mapped to EPAC topics: **0**
- Unmapped: **53**

| OCL code | Label (EN) | Communications (recent periods) | Status | EPAC topic |
|---:|---|---:|---|---|
| 45 | Economic Development | 8,963 | unmapped | — |
| 20 | Industry | 6,898 | unmapped | — |
| 13 | Environment | 6,330 | unmapped | — |
| 33 | Taxation and Finance | 5,718 | unmapped | — |
| 25 | International Trade | 5,628 | unmapped | — |
| 21 | Infrastructure | 5,046 | unmapped | — |
| 36 | Budget | 5,001 | unmapped | — |
| 11 | Energy | 4,535 | unmapped | — |
| 30 | Science and Technology | 4,493 | unmapped | — |
| 18 | Health | 4,087 | unmapped | — |
| 41 | Climate | 4,074 | unmapped | — |
| 10 | Employment and Training | 3,974 | unmapped | — |
| 40 | Research and Development | 3,936 | unmapped | — |
| 35 | Transportation | 3,832 | unmapped | — |
| 29 | Regional Development | 3,120 | unmapped | — |
| 2 | Aboriginal Affairs | 3,032 | unmapped | — |
| 53 | Natural Resources | 2,939 | unmapped | — |
| 3 | Agriculture | 2,674 | unmapped | — |
| 17 | Government Procurement | 2,630 | unmapped | — |
| 8 | Defence | 2,399 | unmapped | — |
| 27 | Labour | 2,360 | unmapped | — |
| 51 | Federal-Provincial Relations | 2,197 | unmapped | — |
| 44 | Housing | 1,975 | unmapped | — |
| 24 | International Relations | 1,961 | unmapped | — |
| 39 | National Security/Security | 1,935 | unmapped | — |
| 9 | Education | 1,824 | unmapped | — |
| 23 | Internal Trade | 1,701 | unmapped | — |
| 28 | Mining | 1,565 | unmapped | — |
| 31 | Small Business | 1,555 | unmapped | — |
| 54 | Foreign Affairs | 1,490 | unmapped | — |
| 19 | Immigration | 1,421 | unmapped | — |
| 26 | Justice and Law Enforcement | 1,260 | unmapped | — |
| 22 | Intellectual Property | 1,216 | unmapped | — |
| 14 | Financial Institutions | 1,202 | unmapped | — |
| 7 | Consumer Issues | 1,199 | unmapped | — |
| 15 | Fisheries | 968 | unmapped | — |
| 37 | International Development | 887 | unmapped | — |
| 4 | Arts and Culture | 807 | unmapped | — |
| 1 | Telecommunications | 785 | unmapped | — |
| 46 | Municipalities | 777 | unmapped | — |
| 34 | Tourism | 643 | unmapped | — |
| 42 | Bilingualism/Official Languages | 560 | unmapped | — |
| 43 | Privacy and Access to Information | 543 | unmapped | — |
| 16 | Forestry | 503 | unmapped | — |
| 5 | Broadcasting | 416 | unmapped | — |
| 50 | Child Services | 392 | unmapped | — |
| 6 | Constitutional Issues | 356 | unmapped | — |
| 32 | Sports | 316 | unmapped | — |
| 38 | Pensions | 272 | unmapped | — |
| 52 | Media | 214 | unmapped | — |
| 49 | Animal Welfare | 210 | unmapped | — |
| 47 | Religion | 150 | unmapped | — |
| 48 | Elections | 61 | unmapped | — |
