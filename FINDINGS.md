## EPAC-1761: ASO Partnership Outreach Spike

### 1. Candidate Outlets & Traffic Analysis (Estimates)

| Outlet | Traffic (Monthly) | App Link Presence | Suitability |
| :--- | :--- | :--- | :--- |
| **La Presse** | ~15M - 20M | High | High (National, RJO) |
| **Le Devoir** | ~2M - 4M | Medium | High (Independent) |
| **The Hub** | ~500K - 1M | Low | Medium (Policy Focus) |
| **The Tyee** | ~500K - 1M | Low | Medium (Solutions Journalism) |
| **The Maple** | ~200K - 500K | Very Low | Low (Investigative/Niche) |
| **The Walrus** | ~500K - 1M | Medium | Medium (Cultural/Ideas) |
| **Le Soleil** | ~1M - 2M | Low | Medium (Regional/Assembly) |

### 2. Outreach Plan
- **Who:** Marketing/Partnerships lead.
- **Offer:** Neutral, non-promotional embed widgets (e.g., 'View voting record on this Bill', 'Follow this MP's latest activity').
- **Format:** WordPress/Ghost block integration, OEmbed-style standard for stability.
- **Criteria for Link:** Must be editorially neutral; link must serve the reader’s information needs (primary source of Hansard data), not promote the app.

### 3. Estimated Effort & Lift
- **Design:** 2-3 days (embed assets, component design).
- **Engineering:** 5-10 days (deep-link API, embed script, stable URL contract).
- **Partnerships:** 10-15 days (initial outreach, relationship building, technical integration help).
- **Estimated Lift:** 0.1% - 0.5% conversion rate on embedded link clicks. 1M impressions $\rightarrow$ 1,000 - 5,000 clicks $\rightarrow$ 10 - 50 installs/month per major partner.

### 4. Recommendation
**Go / No-Go:** **Conditional Go.**
- Focus on **La Presse** and **Le Devoir** first as a pilot. The editorial volume and national presence justify the technical investment in a stable embed widget. 
- Avoid heavy investment in small-niche outlets until the widget is proven reliable.

### 5. Risks
- **Editorial Integrity:** Must avoid any 'sponsored' appearance.
- **Technical Fragility:** Need a strict contract for the epac:// URL structure.
- **Acceptance:** Very low initial interest expected.
