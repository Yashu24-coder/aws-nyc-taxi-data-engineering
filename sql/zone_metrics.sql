-- Top pickup zones by trip count. Join a zone lookup table if one is cataloged.
SELECT
    PULocationID AS pickup_zone_id,
    COUNT(*) AS trip_count,
    ROUND(AVG(trip_distance), 2) AS avg_trip_distance
FROM taxi_lakehouse.silver_trips
WHERE trip_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY PULocationID
ORDER BY trip_count DESC
LIMIT 20;
