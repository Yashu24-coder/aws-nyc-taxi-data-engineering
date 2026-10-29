"""AWS Glue PySpark job starter. Run this inside an AWS Glue Spark job."""
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["JOB_NAME", "INPUT_PATH", "SILVER_PATH", "GOLD_PATH"])
sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

source = spark.read.parquet(args["INPUT_PATH"])
for old, new in [
    ("tpep_pickup_datetime", "pickup_datetime"),
    ("lpep_pickup_datetime", "pickup_datetime"),
    ("tpep_dropoff_datetime", "dropoff_datetime"),
    ("lpep_dropoff_datetime", "dropoff_datetime"),
]:
    if old in source.columns and new not in source.columns:
        source = source.withColumnRenamed(old, new)

required = {"pickup_datetime", "dropoff_datetime"}
missing = required - set(source.columns)
if missing:
    raise ValueError(f"Missing required timestamp columns: {sorted(missing)}")

source = source.withColumn("pickup_datetime", F.to_timestamp("pickup_datetime"))
source = source.withColumn("dropoff_datetime", F.to_timestamp("dropoff_datetime"))
invalid_condition = (
    F.col("pickup_datetime").isNull()
    | F.col("dropoff_datetime").isNull()
    | (F.col("dropoff_datetime") < F.col("pickup_datetime"))
)
for col in ("trip_distance", "fare_amount"):
    if col in source.columns:
        source = source.withColumn(col, F.col(col).cast("double"))
        invalid_condition = invalid_condition | (F.col(col) < 0)

source = source.dropDuplicates()
invalid = source.filter(invalid_condition).withColumn(
    "quarantine_reason", F.lit("timestamp or measure validation failed")
)
valid = source.filter(~invalid_condition).withColumn(
    "trip_date", F.to_date("pickup_datetime").cast("string")
).withColumn("pickup_hour", F.hour("pickup_datetime"))
invalid.write.mode("overwrite").parquet(args["SILVER_PATH"].rstrip("/") + "_quarantine/")
valid.write.mode("overwrite").partitionBy("trip_date").parquet(args["SILVER_PATH"])

aggregations = [F.count("*").alias("trip_count")]
if "trip_distance" in valid.columns:
    aggregations.append(F.avg("trip_distance").alias("avg_trip_distance"))
if "fare_amount" in valid.columns:
    aggregations.append(F.sum("fare_amount").alias("total_fare_amount"))
if "total_amount" in valid.columns:
    aggregations.append(F.sum("total_amount").alias("total_amount"))
valid.groupBy("trip_date").agg(*aggregations).write.mode("overwrite").parquet(args["GOLD_PATH"])
job.commit()
