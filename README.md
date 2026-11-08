# Laveur de vitres

Godot 4 game project (working title).

- Product (vision, decisions, scope, roadmap): Confluence, page [Laveur de vitres](https://lgolivier.atlassian.net/wiki/spaces/DL/pages/4194307/Laveur+de+vitres)
- Work items: Jira project [LAV](https://lgolivier.atlassian.net/jira/software/projects/LAV/boards/2)
- Instructions for Claude Code: [`CLAUDE.md`](CLAUDE.md)

## Builds

CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) builds every push:

- **Web, main**: https://olivier-lapabe.github.io/laveur-de-vitres/
- **Web, other branches**: `https://olivier-lapabe.github.io/laveur-de-vitres/preview/<branch>/`, with each `/` in the branch name replaced by `-`. Only the latest branch preview stays online.
- **Windows**: the `laveur-de-vitres-windows` artifact of each CI run.

## Working on the project locally

Open the folder in the Godot version pinned as `GODOT_VERSION` in the CI workflow. The project uses the Compatibility renderer, the only one the Web export supports.
