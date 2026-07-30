"""
Architecture guard.

Repository boundaries do NOT prevent modules from tangling — dependency
rules do. This test enforces those rules automatically, so a violation
fails CI instead of being discovered eighteen months later.

THE RULE — dependencies point in ONE direction only:

    labcore/    ->  (nothing)          domain rules, the stable core
    adapters/   ->  labcore            source format -> canonical schema
    ingest/     ->  labcore, adapters  orchestration
    labtool/    ->  labcore            existing lab pipeline
    labgateway/ ->  labcore            alerting / publishing

FORBIDDEN, and why:
    labcore  -> adapters   the core would depend on a data source.
                           Change the Excel layout, break the domain rules.
    adapters -> adapters   two sources coupled. Delete the Korean plant,
                           break the Chinese one.
    adapters -> ingest     an adapter that orchestrates is not an adapter.

Uses only the standard library. No import-linter, no extra dependency.
"""

import ast
import pathlib
import pytest

SRC = pathlib.Path(__file__).resolve().parent.parent / "src"

# layer -> layers it is allowed to import from
ALLOWED: dict[str, set[str]] = {
    "labcore":    set(),
    "adapters":   {"labcore"},
    "ingest":     {"labcore", "adapters"},
    "labtool":    {"labcore"},
    "labgateway": {"labcore"},
}

FIRST_PARTY = set(ALLOWED)


def _imported_layers(path: pathlib.Path) -> set[str]:
    """Return the set of first-party layers a Python file imports from."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found: set[str] = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                if root in FIRST_PARTY:
                    found.add(root)

        elif isinstance(node, ast.ImportFrom):
            # Ignore relative imports (level > 0): they stay inside the layer.
            if node.level == 0 and node.module:
                root = node.module.split(".")[0]
                if root in FIRST_PARTY:
                    found.add(root)

    return found


def _python_files(layer: str) -> list[pathlib.Path]:
    layer_dir = SRC / layer
    if not layer_dir.is_dir():
        return []
    return [p for p in layer_dir.rglob("*.py") if "__pycache__" not in p.parts]


@pytest.mark.parametrize("layer", sorted(ALLOWED))
def test_layer_dependencies(layer: str) -> None:
    """No module may import from a layer it is not permitted to depend on."""
    permitted = ALLOWED[layer]
    violations: list[str] = []

    for path in _python_files(layer):
        for imported in _imported_layers(path):
            if imported == layer:
                continue  # intra-layer imports within the same package are fine
            if imported not in permitted:
                rel = path.relative_to(SRC)
                violations.append(
                    f"  {rel} imports '{imported}' "
                    f"(layer '{layer}' may only import: "
                    f"{sorted(permitted) or 'nothing'})"
                )

    assert not violations, (
        f"\nDependency direction violated in '{layer}':\n"
        + "\n".join(violations)
        + "\n\nFix by moving the shared logic into labcore/, not by "
          "adding an exception here."
    )


def test_adapters_are_mutually_independent() -> None:
    """
    Adapters must never import one another.

    Two sources that share code have coupled release cycles: a change to
    the Chinese Excel adapter can then break the Korean CSV adapter.
    Shared logic belongs in labcore/.
    """
    adapters_dir = SRC / "adapters"
    if not adapters_dir.is_dir():
        pytest.skip("adapters/ does not exist yet")

    # Files that are legitimately shared infrastructure, not adapters.
    INFRA = {"base.py", "__init__.py", "registry.py"}

    violations: list[str] = []
    for path in _python_files("adapters"):
        if path.name in INFRA:
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                parts = node.module.split(".")
                if parts[0] == "adapters" and len(parts) > 1:
                    if f"{parts[1]}.py" not in INFRA:
                        violations.append(
                            f"  {path.name} imports adapters.{parts[1]}"
                        )

    assert not violations, (
        "\nAdapters must not import each other:\n"
        + "\n".join(violations)
        + "\n\nMove the shared logic into labcore/ or adapters/base.py."
    )


def test_labcore_has_no_io_dependencies() -> None:
    """
    labcore/ is pure domain logic. It must not import database drivers,
    HTTP clients, or file-format readers.

    If labcore needs psycopg to work, it is no longer reusable and no
    longer unit-testable without a live database.
    """
    FORBIDDEN = {
        "psycopg", "psycopg2", "sqlalchemy", "pyodbc",
        "requests", "httpx", "flask", "fastapi",
        "openpyxl", "pandas",
    }

    if not (SRC / "labcore").is_dir():
        pytest.skip("labcore/ does not exist yet")

    violations: list[str] = []
    for path in _python_files("labcore"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            roots: list[str] = []
            if isinstance(node, ast.Import):
                roots = [a.name.split(".")[0] for a in node.names]
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                roots = [node.module.split(".")[0]]
            for r in roots:
                if r in FORBIDDEN:
                    violations.append(
                        f"  {path.relative_to(SRC)} imports '{r}'"
                    )

    assert not violations, (
        "\nlabcore/ must stay free of I/O dependencies:\n"
        + "\n".join(violations)
        + "\n\nI/O belongs in adapters/ or ingest/."
    )
