"""Convert NDJSON raw data files to CSV for Verity DataFusion ingestion."""
import polars as pl
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
NDJSON_DIR = PROJECT_ROOT / "src" / "data" / "raw"
CSV_DIR = Path(__file__).parent.parent / "data"


def convert_all() -> None:
    """Read each .json (NDJSON) file and write a .csv equivalent."""
    CSV_DIR.mkdir(parents=True, exist_ok=True)

    files = sorted(NDJSON_DIR.glob("*.json"))
    if not files:
        print(f"⚠️  No NDJSON files found in {NDJSON_DIR}")
        print("   Run `just generate-data` first.")
        return

    for src in files:
        dst = CSV_DIR / src.with_suffix(".csv").name
        df = pl.read_ndjson(src)
        df.write_csv(dst)
        print(f"✅ {src.name} → {dst.name} ({len(df)} rows)")

    print(f"\n📁 CSV files written to {CSV_DIR}")


if __name__ == "__main__":
    convert_all()
