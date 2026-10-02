-- Taobao User Behavior Analysis
-- MySQL 8.0+
-- Dataset fields: user_id, item_id, category_id, behavior, timestamp

CREATE DATABASE IF NOT EXISTS taobao_analysis
DEFAULT CHARACTER SET utf8mb4;

USE taobao_analysis;
SET time_zone = '+08:00';


-- =========================================================
-- 0. Raw table
-- =========================================================
CREATE TABLE IF NOT EXISTS taobao (
    user_id INT,
    item_id BIGINT,
    category_id BIGINT,
    behavior VARCHAR(20),
    `timestamp` BIGINT
) ENGINE = InnoDB;


-- =========================================================
-- 1. Data quality
-- =========================================================

-- 1.1 Dataset size
SELECT
    COUNT(*) AS row_cnt,
    COUNT(DISTINCT user_id) AS user_cnt,
    COUNT(DISTINCT item_id) AS item_cnt,
    COUNT(DISTINCT category_id) AS category_cnt
FROM taobao;

-- 1.2 Null and invalid values
SELECT
    SUM(user_id IS NULL) AS null_user,
    SUM(item_id IS NULL) AS null_item,
    SUM(category_id IS NULL) AS null_category,
    SUM(behavior IS NULL) AS null_behavior,
    SUM(`timestamp` IS NULL) AS null_time,
    SUM(behavior NOT IN ('pv', 'fav', 'cart', 'buy')) AS invalid_behavior
FROM taobao;

-- 1.3 Exact duplicates
SELECT COUNT(*) AS duplicate_cnt
FROM (
    SELECT
        user_id,
        item_id,
        category_id,
        behavior,
        `timestamp`,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, item_id, category_id, behavior, `timestamp`
            ORDER BY `timestamp`
        ) AS rn
    FROM taobao
) t
WHERE rn > 1;


-- =========================================================
-- 2. Analysis table
-- Window: 2017-11-24 to 2017-11-30
-- =========================================================

DROP TABLE IF EXISTS taobao_clean;

CREATE TABLE taobao_clean AS
SELECT DISTINCT
    user_id,
    item_id,
    category_id,
    behavior,
    `timestamp`,
    FROM_UNIXTIME(`timestamp`) AS dt,
    DATE(FROM_UNIXTIME(`timestamp`)) AS day_date,
    HOUR(FROM_UNIXTIME(`timestamp`)) AS hour_num
FROM taobao
WHERE `timestamp` BETWEEN
      UNIX_TIMESTAMP('2017-11-24 00:00:00')
  AND UNIX_TIMESTAMP('2017-11-30 23:59:59');


-- =========================================================
-- 3. User behavior coverage
-- =========================================================

WITH user_behavior AS (
    SELECT
        user_id,
        MAX(behavior = 'pv') AS has_pv,
        MAX(behavior = 'fav') AS has_fav,
        MAX(behavior = 'cart') AS has_cart,
        MAX(behavior = 'buy') AS has_buy
    FROM taobao_clean
    GROUP BY user_id
)
SELECT
    SUM(has_pv) AS pv_user,
    SUM(has_fav) AS fav_user,
    SUM(has_cart) AS cart_user,
    SUM(has_buy) AS buy_user,
    ROUND(SUM(has_fav) / NULLIF(SUM(has_pv), 0), 4) AS pv_to_fav_rate,
    ROUND(SUM(has_cart) / NULLIF(SUM(has_pv), 0), 4) AS pv_to_cart_rate,
    ROUND(SUM(has_buy) / NULLIF(SUM(has_cart), 0), 4) AS cart_to_buy_rate,
    ROUND(SUM(has_buy) / NULLIF(SUM(has_pv), 0), 4) AS pv_to_buy_rate
FROM user_behavior;

WITH user_behavior AS (
    SELECT
        user_id,
        MAX(behavior = 'cart') AS has_cart,
        MAX(behavior = 'buy') AS has_buy
    FROM taobao_clean
    GROUP BY user_id
)
SELECT
    COUNT(*) AS cart_not_buy_user
FROM user_behavior
WHERE has_cart = 1
  AND has_buy = 0;


-- =========================================================
-- 4. Hourly traffic and buyer rate
-- =========================================================

WITH hourly AS (
    SELECT
        hour_num,
        SUM(behavior = 'pv') AS pv_cnt,
        COUNT(DISTINCT CASE WHEN behavior = 'pv' THEN user_id END) AS pv_user,
        COUNT(DISTINCT CASE WHEN behavior = 'buy' THEN user_id END) AS buy_user,
        SUM(behavior = 'buy') AS buy_cnt
    FROM taobao_clean
    GROUP BY hour_num
),
scored AS (
    SELECT
        *,
        ROUND(buy_user / NULLIF(pv_user, 0), 4) AS viewer_to_buyer_rate,
        NTILE(4) OVER (ORDER BY pv_cnt) AS traffic_level,
        NTILE(4) OVER (
            ORDER BY buy_user / NULLIF(pv_user, 0)
        ) AS conversion_level
    FROM hourly
)
SELECT
    hour_num,
    pv_cnt,
    pv_user,
    buy_user,
    buy_cnt,
    viewer_to_buyer_rate,
    CASE
        WHEN traffic_level = 4 AND conversion_level <= 2
            THEN 'high_traffic_low_rate'
        WHEN traffic_level = 4 AND conversion_level = 4
            THEN 'high_traffic_high_rate'
        WHEN traffic_level <= 2 AND conversion_level = 4
            THEN 'lower_traffic_high_rate'
        ELSE 'normal'
    END AS hour_type
FROM scored
ORDER BY hour_num;


-- =========================================================
-- 5. Category performance
-- =========================================================

WITH category_user AS (
    SELECT
        category_id,
        user_id,
        MAX(behavior = 'pv') AS has_pv,
        MAX(behavior = 'buy') AS has_buy
    FROM taobao_clean
    GROUP BY category_id, user_id
),
category_stats AS (
    SELECT
        category_id,
        SUM(has_pv) AS pv_user,
        SUM(has_buy) AS buy_user,
        SUM(has_pv = 1 AND has_buy = 1) AS pv_and_buy_user
    FROM category_user
    GROUP BY category_id
),
category_event AS (
    SELECT
        category_id,
        SUM(behavior = 'pv') AS pv_cnt,
        SUM(behavior = 'cart') AS cart_cnt,
        SUM(behavior = 'buy') AS buy_cnt
    FROM taobao_clean
    GROUP BY category_id
),
base AS (
    SELECT
        e.category_id,
        e.pv_cnt,
        e.cart_cnt,
        e.buy_cnt,
        s.pv_user,
        s.buy_user,
        ROUND(
            s.pv_and_buy_user / NULLIF(s.pv_user, 0),
            4
        ) AS viewer_to_buyer_rate
    FROM category_event e
    JOIN category_stats s USING (category_id)
    WHERE e.pv_cnt > 0
),
ranked AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY pv_cnt) AS traffic_level,
        NTILE(4) OVER (
            ORDER BY viewer_to_buyer_rate
        ) AS conversion_level
    FROM base
)
SELECT
    category_id,
    pv_cnt,
    cart_cnt,
    buy_cnt,
    pv_user,
    buy_user,
    viewer_to_buyer_rate,
    CASE
        WHEN traffic_level = 4 AND conversion_level = 4
            THEN 'core'
        WHEN traffic_level = 4 AND conversion_level <= 2
            THEN 'high_traffic_low_conversion'
        WHEN traffic_level <= 2 AND conversion_level = 4
            THEN 'potential'
        WHEN traffic_level <= 2 AND conversion_level <= 2
            THEN 'low_priority'
        ELSE 'mid'
    END AS business_type
FROM ranked
ORDER BY pv_cnt DESC;


-- =========================================================
-- 6. Cart without purchase by category
-- user_id + item_id level
-- =========================================================

WITH cart_item AS (
    SELECT
        user_id,
        item_id,
        category_id,
        MIN(dt) AS first_cart_time,
        COUNT(*) AS cart_cnt
    FROM taobao_clean
    WHERE behavior = 'cart'
    GROUP BY user_id, item_id, category_id
),
buy_item AS (
    SELECT
        user_id,
        item_id,
        MIN(dt) AS first_buy_time
    FROM taobao_clean
    WHERE behavior = 'buy'
    GROUP BY user_id, item_id
),
cart_not_buy AS (
    SELECT
        c.user_id,
        c.item_id,
        c.category_id,
        c.first_cart_time,
        c.cart_cnt
    FROM cart_item c
    LEFT JOIN buy_item b
        ON c.user_id = b.user_id
       AND c.item_id = b.item_id
       AND b.first_buy_time >= c.first_cart_time
    WHERE b.user_id IS NULL
)
SELECT
    category_id,
    COUNT(*) AS lost_user_item,
    COUNT(DISTINCT user_id) AS lost_user,
    COUNT(DISTINCT item_id) AS lost_item,
    ROUND(AVG(cart_cnt), 2) AS avg_cart_cnt
FROM cart_not_buy
GROUP BY category_id
HAVING COUNT(*) >= 5
ORDER BY lost_user_item DESC;


-- =========================================================
-- 7. User segmentation
-- No monetary field is available in this dataset.
-- =========================================================

WITH user_value AS (
    SELECT
        user_id,
        COUNT(DISTINCT day_date) AS active_days,
        SUM(behavior = 'pv') AS pv_cnt,
        SUM(behavior = 'cart') AS cart_cnt,
        SUM(behavior = 'buy') AS buy_cnt,
        COUNT(
            DISTINCT CASE WHEN behavior = 'buy' THEN item_id END
        ) AS buy_item_cnt,
        MAX(
            CASE WHEN behavior = 'buy' THEN day_date END
        ) AS last_buy_date
    FROM taobao_clean
    GROUP BY user_id
),
segmented AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY active_days) AS active_level,
        NTILE(4) OVER (ORDER BY buy_cnt) AS buy_level
    FROM user_value
)
SELECT
    user_id,
    active_days,
    pv_cnt,
    cart_cnt,
    buy_cnt,
    buy_item_cnt,
    last_buy_date,
    CASE
        WHEN buy_level = 4 AND active_level = 4
            THEN 'high_activity_high_purchase'
        WHEN buy_level = 4 AND active_level <= 2
            THEN 'high_purchase_low_activity'
        WHEN buy_level <= 2 AND active_level = 4
            THEN 'high_activity_low_purchase'
        WHEN cart_cnt > 0 AND buy_cnt = 0
            THEN 'cart_no_purchase'
        ELSE 'regular'
    END AS user_type
FROM segmented
ORDER BY buy_cnt DESC, active_days DESC;


-- =========================================================
-- 8. Daily trend
-- =========================================================

SELECT
    day_date,
    SUM(behavior = 'pv') AS pv_cnt,
    COUNT(DISTINCT user_id) AS active_user,
    COUNT(
        DISTINCT CASE WHEN behavior = 'buy' THEN user_id END
    ) AS buy_user,
    SUM(behavior = 'buy') AS buy_cnt,
    ROUND(
        COUNT(
            DISTINCT CASE WHEN behavior = 'buy' THEN user_id END
        ) / NULLIF(COUNT(DISTINCT user_id), 0),
        4
    ) AS active_to_buy_rate
FROM taobao_clean
GROUP BY day_date
ORDER BY day_date;


-- =========================================================
-- 9. Retention
-- first_date = first observed date inside the analysis window
-- =========================================================

WITH first_day AS (
    SELECT
        user_id,
        MIN(day_date) AS first_date
    FROM taobao_clean
    GROUP BY user_id
),
user_day AS (
    SELECT DISTINCT
        user_id,
        day_date
    FROM taobao_clean
),
base AS (
    SELECT
        f.user_id,
        f.first_date,
        d.day_date
    FROM first_day f
    LEFT JOIN user_day d
        ON f.user_id = d.user_id
),
data_end AS (
    SELECT MAX(day_date) AS max_date
    FROM taobao_clean
)
SELECT
    b.first_date,
    COUNT(DISTINCT b.user_id) AS cohort_user,
    CASE
        WHEN DATE_ADD(b.first_date, INTERVAL 1 DAY) <= e.max_date
        THEN ROUND(
            COUNT(
                DISTINCT CASE
                    WHEN b.day_date = DATE_ADD(
                        b.first_date,
                        INTERVAL 1 DAY
                    )
                    THEN b.user_id
                END
            ) / NULLIF(COUNT(DISTINCT b.user_id), 0),
            4
        )
    END AS day1_retention,
    CASE
        WHEN DATE_ADD(b.first_date, INTERVAL 3 DAY) <= e.max_date
        THEN ROUND(
            COUNT(
                DISTINCT CASE
                    WHEN b.day_date = DATE_ADD(
                        b.first_date,
                        INTERVAL 3 DAY
                    )
                    THEN b.user_id
                END
            ) / NULLIF(COUNT(DISTINCT b.user_id), 0),
            4
        )
    END AS day3_retention
FROM base b
CROSS JOIN data_end e
GROUP BY b.first_date, e.max_date
ORDER BY b.first_date;
