-- Replace database/table names with the names registered in your Glue Catalog.
SELECT
    trip_date,
    COUNT(*) AS trip_count,
    ROUND(AVG(trip_distance), 2) AS avg_trip_distance,
    ROUND(SUM(fare_amount), 2) AS total_fare_amount,
    ROUND(SUM(total_amount), 2) AS total_amount
FROM taxi_lakehouse.silver_trips
WHERE trip_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY trip_date
ORDER BY trip_date;
