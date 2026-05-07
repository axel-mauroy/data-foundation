import os
import pandas as pd
from google.cloud import bigquery

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = ".gcp/application_default_credentials.json"
client = bigquery.Client(project="dealk-data-dev")
dataset_id = "dealk-data-dev.verity_dev"

sources = {
    "erp_companies": "verity/data/companies.csv",
    "erp_associations": "verity/data/associations.csv",
    "erp_stock_declarations": "verity/data/stock_declarations.csv",
    "erp_donations": "verity/data/donations.csv"
}

for table_id, file_path in sources.items():
    table_ref = f"{dataset_id}.{table_id}"
    print(f"Loading {file_path} into {table_ref}...")
    df = pd.read_csv(file_path)
    job = client.load_table_from_dataframe(df, table_ref)
    job.result()
    print(f"Loaded {job.output_rows} rows into {table_ref}.")
