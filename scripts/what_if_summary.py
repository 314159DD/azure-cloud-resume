"""Turns `az deployment group what-if --output json` into a short Markdown summary for pull requests.

Separates changes to resources (create/delete) from property-level modifications so reviewers see the
real impact first. Property changes the platform fills in on its own ("noise") are still listed, but
collapsed, because a reviewer should look at them deliberately instead of trusting a green check.
"""
import json
import sys
from collections import Counter

ICONS = {"Create": "+", "Delete": "-", "Modify": "~", "Deploy": "*", "Unsupported": "?"}


def short_id(resource_id: str) -> str:
    return resource_id.split("/providers/", 1)[-1]


def main(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        changes = json.load(f).get("changes", [])

    counts = Counter(c["changeType"] for c in changes)
    print("### What-if preview\n")
    if not changes:
        print("No changes.")
        return
    print(" · ".join(f"**{n}** {kind}" for kind, n in sorted(counts.items())) + "\n")

    structural = [c for c in changes if c["changeType"] in ("Create", "Delete", "Unsupported")]
    if structural:
        print("#### Resources created or deleted\n")
        for c in structural:
            print(f"- `{ICONS.get(c['changeType'], '?')}` {c['changeType']} `{short_id(c['resourceId'])}`")
        print()

    modified = [c for c in changes if c["changeType"] == "Modify"]
    if modified:
        print("<details><summary>Property changes on existing resources</summary>\n")
        for c in modified:
            paths = [d["path"] for d in c.get("delta") or []]
            print(f"- `{short_id(c['resourceId'])}`: " + ", ".join(f"`{p}`" for p in paths[:8]))
        print("\n</details>")


if __name__ == "__main__":
    main(sys.argv[1])
