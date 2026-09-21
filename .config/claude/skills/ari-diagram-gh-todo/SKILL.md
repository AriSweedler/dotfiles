---
name: ari-diagram-gh-todo
description: "Track TODO items with dependencies as a status-colored Mermaid graph posted as a GitHub PR or issue comment, with a baked mermaid.ink URL for embedding elsewhere."
user_invocable: true
---

# ari-diagram-gh-todo

Track TODO items with dependencies as color-coded mermaid diagrams, posted as GitHub PR/issue comments.

## Color Scheme (status-based)

| Status | Color | Hex |
|--------|-------|-----|
| Unstarted / Blocked | Red | `#F82B60` |
| In Progress | Yellow | `#FCB400` |
| Done / Complete | Green | `#20C933` |

## Workflow

1. **Gather TODOs** from user — each item needs: name, status (unstarted/in-progress/done), dependencies
2. **Set up the session** — emit exactly this one Bash call; it prints the `diagram_file=` path to write to:
   ```zsh
   zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/init.zsh --name todo-diagram
   ```
3. **Build mermaid `graph TD`** and write it to that `diagram_file`:
   - Line 1 is the `%%{init: …}%%` directive that opens `/ari-diagram-mermaid`'s color theme block, copied verbatim: it pins the theme and halos free-standing text, bake refuses the file without it, and GitHub renders it
   - Each TODO as a node, labeled with task name
   - Dependency arrows (`A --> B` means B depends on A)
   - Status-based classDefs and class assignments; every fill carries a text color that passes bake's contrast gate:
     ```mermaid
     classDef red fill:#F82B60,stroke:#C42249,color:#fff
     classDef yellow fill:#FCB400,stroke:#B88000,color:#333
     classDef green fill:#20C933,stroke:#168E24,color:#333
     ```
4. **Bake** the file init printed:
   ```zsh
   zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/bake /tmp/ari-diagram-mermaid/<timestamp>/todo-diagram.mmd
   ```
5. **Post as a GitHub comment** using `gh`. The comment MUST have this format:
   - An `## <Title>` header
   - A single sentence describing the diagram
   - A horizontal rule (`---`)
   - The mermaid fenced block

   ```bash
   gh issue comment <number> --body "$(cat <<'EOF'
   ## <Title>
   <One-sentence description of the diagram.>

   ---

   ```mermaid
   <diagram source>
   ```
   EOF
   )"
   ```

   Or for PRs, use `gh pr comment` with the same format.
   GitHub natively renders mermaid in comments — no image URL needed.
6. **Also provide** the mermaid.ink URL for embedding elsewhere (Google Docs, Slack, etc.)

## Example

For TODOs:
- "Design API" (done)
- "Implement backend" (in-progress, depends on Design API)
- "Write tests" (unstarted, depends on Implement backend)
- "Deploy" (unstarted, depends on Write tests)

### GitHub comment body:

```markdown
## API Launch Progress
4 tasks tracked — 1 done, 1 in progress, 2 remaining.

---

```mermaid
%%{init: {'theme':'default', 'themeCSS': '.messageText, text.text, text.actor, .loopText, .noteText, .labelText, .titleText { paint-order: stroke; stroke: #ffffff; stroke-width: 4px; stroke-linejoin: round; }'}}%%
graph TD
    A["Design API"]
    B["Implement backend"]
    C["Write tests"]
    D["Deploy"]

    A --> B
    B --> C
    C --> D

    classDef red fill:#F82B60,stroke:#C42249,color:#fff
    classDef yellow fill:#FCB400,stroke:#B88000,color:#333
    classDef green fill:#20C933,stroke:#168E24,color:#333

    class A green
    class B yellow
    class C,D red
```
```
