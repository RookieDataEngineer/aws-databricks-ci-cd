import dlt
from pyspark.sql import functions as F


# Define the pipeline
@dlt.table(name="bronze_data", comment="Raw data from source system")
def bronze_data():
    # Sample data generation - replace with your actual data source
    return spark.range(0, 1000).withColumn("timestamp", F.current_timestamp())


@dlt.table(name="silver_data", comment="Cleaned and transformed data")
def silver_data():
    # Apply transformations
    return dlt.read("bronze_data").withColumn("processed_at", F.current_timestamp())


@dlt.table(name="gold_data", comment="Business-level aggregations")
def gold_data():
    # Apply business logic
    return (
        dlt.read("silver_data")
        .groupBy()
        .agg(
            F.count("*").alias("total_records"),
            F.min("timestamp").alias("min_timestamp"),
            F.max("timestamp").alias("max_timestamp"),
        )
    )
