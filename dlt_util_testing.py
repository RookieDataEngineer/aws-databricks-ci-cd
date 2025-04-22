import dlt
from pyspark.sql.functions import col, upper, length, expr

# Define the name of your source table
source_table_name = "atlaspoc.poc_schema.customer_test"

# ---------------------------------------------------------------------------
# Bronze Layer: Ingest Raw Data
# ---------------------------------------------------------------------------
# This first table reads directly from your source.
# It acts as the entry point for data into the DLT pipeline.
# We are not modifying it here, but applying a simple quality check.
# DLT will automatically handle schema evolution and infer the schema.
# ---------------------------------------------------------------------------
@dlt.table(
    name="customer_bronze", # Explicit name for this DLT table
    comment=f"Raw customer data ingested from {source_table_name}. Includes basic quality check for non-null ID.",
    table_properties={"quality": "bronze"} # Optional: Tagging table quality
)
@dlt.expect_or_drop("valid_id", "ID IS NOT NULL") # Data Quality Rule: Drop rows where ID is NULL
def ingest_customer_data():
  """
  Reads the source customer table and applies an initial quality check.
  Rows with NULL ID will be dropped and recorded in DLT metrics.
  """
  print(f"Reading from source table: {source_table_name}")
  df = spark.read.table(source_table_name)
  # You could add more expectations here, e.g., @dlt.expect(...)
  return df

# ---------------------------------------------------------------------------
# Silver Layer: Cleaned and Transformed Data
# ---------------------------------------------------------------------------
# This table reads from the 'customer_bronze' DLT table created above.
# It performs cleaning and transformation steps.
# ---------------------------------------------------------------------------
@dlt.table(
    name="customer_silver", # Explicit name for this DLT table
    comment="Cleaned and transformed customer data. Filters young customers, standardizes state, checks email format.",
    table_properties={"quality": "silver"} # Optional: Tagging table quality
)
@dlt.expect("valid_email_format", "Email LIKE '%@%.%'") # Warn if email doesn't look like a basic email format
@dlt.expect_or_fail("valid_state_code", "length(State_Upper) == 2") # Fail pipeline if cleaned state code isn't 2 chars
def clean_customer_data():
  """
  Filters customers (e.g., Age <= 40), converts State to uppercase,
  renames columns for clarity, and applies more specific data quality rules.
  """
  print("Processing data from customer_bronze")
  # Read from the upstream DLT table 'customer_bronze'
  bronze_df = dlt.read("customer_bronze")

  # Apply transformations:
  # 1. Filter for customers age 40 or younger
  # 2. Convert State to uppercase and rename
  # 3. Select relevant columns
  silver_df = (bronze_df
               .filter(col("Age") <= 40)
               .withColumn("State_Upper", upper(col("State")))
               .select(
                   col("ID").alias("CustomerID"), # Rename columns
                   col("Name").alias("CustomerName"),
                   col("Age"),
                   col("Address"),
                   col("City"),
                   col("State_Upper"), # Use the standardized state
                   col("Email")
               )
              )
  return silver_df

# ---------------------------------------------------------------------------
# Gold Layer: Aggregated or Business-Ready Data (Example)
# ---------------------------------------------------------------------------
# This table reads from the 'customer_silver' DLT table.
# It creates an aggregated view, e.g., count of customers by state.
# ---------------------------------------------------------------------------
@dlt.table(
    name="customer_count_by_state_gold", # Explicit name for this DLT table
    comment="Aggregated count of customers per state.",
    table_properties={"quality": "gold"} # Optional: Tagging table quality
)
def aggregate_customer_by_state():
  """
  Calculates the count of customers per state based on the cleaned silver data.
  """
  print("Aggregating data from customer_silver")
  silver_df = dlt.read("customer_silver")
  gold_df = silver_df.groupBy("State_Upper").count().alias("CustomerCount")
  return gold_df