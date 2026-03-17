import uuid
import random
from pathlib import Path
from faker import Faker
import polars as pl

fake = Faker("fr_FR")
Faker.seed(42)
random.seed(42)

CATEGORIES = ["textile", "hygiene", "electromenager", "bricolage", "jouets", "mobilier"]
REGIONS = ["IDF", "PACA", "ARA", "NAQ", "BFC", "NOR", "OCC", "GES"]
CONDITIONS = ["neuf", "bon_etat", "usage"]
PROJECT_ROOT = Path(__file__).parent.parent
OUTPUT_DIR = PROJECT_ROOT / "data" / "raw"


DESCRIPTION_MAP = {
    "textile": [
        "Lot de t-shirts en coton bio", "Pantalons en denim", "Vestes d'hiver imperméables",
        "Chaussettes de sport", "Robes d'été légères", "Chemises formelles"
    ],
    "hygiene": [
        "Gel douche hydratant 500ml", "Dentifrice protection complète", "Savon liquide mains",
        "Shampoing usage fréquent", "Lotion corporelle apaisante", "Déodorant sans aluminium"
    ],
    "electromenager": [
        "Machine à café espresso", "Bouilloire électrique 1.7L", "Grille-pain 2 fentes",
        "Mixeur plongeant haute puissance", "Aspirateur balai sans fil", "Micro-ondes 20L"
    ],
    "bricolage": [
        "Perceuse sans fil 18V", "Jeu de tournevis précision", "Marteau de menuisier",
        "Niveau à bulle magnétique", "Scie circulaire compacte", "Coffret de douilles"
    ],
    "jouets": [
        "Puzzle 1000 pièces paysages", "Voiture télécommandée tout-terrain", "Poupée articulée avec accessoires",
        "Jeu de construction blocs", "Jeux de société stratégie", "Peluche animal douce"
    ],
    "mobilier": [
        "Chaise de bureau ergonomique", "Table basse en bois massif", "Étagère modulable 5 niveaux",
        "Lampadaire design moderne", "Fauteuil relax en tissu", "Commode 3 tiroirs"
    ]
}


def ensure_output_dir() -> None:
    """Creates the output directory if it doesn't exist."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def generate_companies(n: int = 50) -> pl.DataFrame:
    """Generate master data for companies."""
    data = [{
        "company_id": str(uuid.uuid4()),
        "company_name": fake.company(),
        "region": random.choice(REGIONS),
        "sector": random.choice(["retail", "industrie", "distribution", "ecommerce"]),
        "created_at": fake.date_between(start_date="-2y", end_date="today"),
    } for _ in range(n)]
    return pl.DataFrame(data)


def generate_associations(n: int = 100) -> pl.DataFrame:
    """Generate master data for charities/associations."""
    data = [{
        "association_id": str(uuid.uuid4()),
        "association_name": f"{fake.company()} Solidaire",
        "region": random.choice(REGIONS),
        "type": random.choice(["reseau_alimentaire", "reinsertion", "scolaire", "sante"]),
        "capacity_kg": random.randint(100, 5000),
        "accepted_categories": ",".join(random.sample(CATEGORIES, k=random.randint(2, 5))),
        "created_at": fake.date_between(start_date="-3y", end_date="today"),
    } for _ in range(n)]
    return pl.DataFrame(data)


def generate_stock_declarations(df_comp: pl.DataFrame, n: int = 500) -> pl.DataFrame:
    """Generate stock declarations linked to existing companies."""
    company_ids = df_comp["company_id"].to_list()
    data = []
    for _ in range(n):
        cat = random.choice(CATEGORIES)
        data.append({
            "declaration_id": str(uuid.uuid4()),
            "company_id": random.choice(company_ids),
            "category": cat,
            "quantity_kg": round(random.uniform(10, 2000), 2),
            "condition": random.choice(CONDITIONS),
            "description": random.choice(DESCRIPTION_MAP[cat]),
            "declared_at": fake.date_time_between(start_date="-1y", end_date="now"),
            "expiry_days": random.randint(7, 90),
        })
    return pl.DataFrame(data)


def generate_donations(
    df_decl: pl.DataFrame, 
    df_assoc: pl.DataFrame, 
    n: int = 1000
) -> pl.DataFrame:
    """Generate donation events matching declarations and associations."""
    decl_ids = df_decl["declaration_id"].to_list()
    assoc_ids = df_assoc["association_id"].to_list()

    data = [{
        "donation_id": str(uuid.uuid4()),
        "declaration_id": random.choice(decl_ids),
        "association_id": random.choice(assoc_ids),
        "outcome": random.choices(["accepted", "rejected", "pending"], weights=[70, 20, 10])[0],
        "matched_at": fake.date_time_between(start_date="-1y", end_date="now"),
        "transport_cost_eur": round(random.uniform(20, 500), 2),
        "distance_km": round(random.uniform(5, 800), 2),
    } for _ in range(n)]
    return pl.DataFrame(data)


if __name__ == "__main__":
    ensure_output_dir()

    print("🚀 Starting data generation...")
    companies = generate_companies(50)
    associations = generate_associations(100)
    declarations = generate_stock_declarations(companies, 500)
    donations = generate_donations(declarations, associations, 1000)

    files = {
        "companies.json": companies,
        "associations.json": associations,
        "stock_declarations.json": declarations,
        "donations.json": donations,
    }

    for filename, df in files.items():
        df.write_ndjson(OUTPUT_DIR / filename)
        print(f"💾 Written: {filename} ({len(df)} rows)")

    print(f"\n✅ Success! Files are in {OUTPUT_DIR}")