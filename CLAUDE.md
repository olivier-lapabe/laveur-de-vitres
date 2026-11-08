# Laveur de vitres

A Godot 4 game project. Everything about the product (vision, decisions, scope, roadmap, open questions) lives in Atlassian; this repo holds only the code, the build configuration and this file.

## Sources of truth

- **Confluence**, in French: space `DL` ("Développement logiciel") on `lgolivier.atlassian.net` (cloudId `2bcf678e-e5d9-4926-8909-d61dfb40824c`). Pages: hub 4194307, Vision 4259841, PRD 4259862, Roadmap 4292609, Décisions 4325377.
- **Jira**: project `LAV` (board 2), one EPIC per chunk of work with its scope and done criteria.

Before any task, read the Décisions page and the Jira issue you are working on. Before any game-design, economy or scope work, also read the PRD and the Roadmap. If the Atlassian connector is missing from the session, ask the PO to connect it before going further.

Keep product content in Confluence and Jira only. A product decision is the PO's call (the PO is Olivier, "olivier lg" on Atlassian): propose it with a recommendation; once he agrees, record it as the next D-number on the Décisions page and update the PRD and the Jira issue it affects.

## How we work

- **One branch and one pull request per change.** The PO plays the build from the PR and merges it himself.
- **CI is the test bench.** GitHub Actions downloads the pinned Godot version, imports and checks the project headless, exports Web and Windows builds, and deploys the Web build to GitHub Pages (the repo is public). A PR is done when CI is green and its description says what to try in the build.
- **Godot may not run in Claude's cloud sandbox**: on 2026-11-08, downloads from `release-assets.githubusercontent.com` were blocked there. Let CI run Godot rather than hunting for another download route.
- **Stay on the Compatibility renderer.** Godot's Web export only supports it, and GitHub Pages cannot send cross-origin isolation headers, so export the Web build without thread support.
- **Pin the Godot version once**, in the CI workflow, and keep `project.godot` consistent with it.
- **Languages**: talk to the PO in the language he writes in; Confluence and Jira content stays in French; code, comments and commit messages are in English; in-game text is French for now.
