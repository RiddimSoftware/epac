---
workflow_template:
  managed: true
  source_ref: templates/WORKFLOW.template.md
  version: sha256:a2b3385d92813396c4cab52753fa924d69a79a5437115a19ae403d2803a8a4d9
  managed_block_sha256: 57ea2da2ae0b7a838d894600c56d1e3e99cc759c1099349362e32523eff50a3b
  repo_name: epac
  verification_command: 'Run `cd ios && make build`. See the Verification Expectations section for area-specific commands.'
  disabled_prompt_instruction_ids: []
extends: ../agent-config/symphony/shared.yml
tracker:
  project_slug: EPAC
repositories:
  - epac

server:
  port: 4781
---
